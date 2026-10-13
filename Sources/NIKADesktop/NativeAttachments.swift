import SwiftUI
import AVFoundation
import AVKit

@MainActor
enum NativeAttachments {
    static func screenshot() async throws -> URL? {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("NIKA-screen-\(UUID().uuidString).png")
        let code: Int32 = try await withCheckedThrowingContinuation { continuation in
            let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = ["-i", "-x", file.path]
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
        guard code == 0, FileManager.default.fileExists(atPath: file.path) else { return nil }
        return file
    }
    static func paste(into workspace: Workspace) {
        let pasteboard = NSPasteboard.general
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty { workspace.add(urls) }
        else if let image = NSImage(pasteboard: pasteboard), let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let data = bitmap.representation(using: .png, properties: [:]) {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("NIKA-paste-\(UUID().uuidString).png")
            do { try data.write(to: url); workspace.add([url]) } catch { workspace.error = error.localizedDescription }
        } else if let text = pasteboard.string(forType: .string) { workspace.draft += text }
    }
}
final class CameraController: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "nika.camera")
    @Published var ready = false
    @Published var error: String?
    var captured: ((URL) -> Void)?
    func start() async {
        guard await AVCaptureDevice.requestAccess(for: .video) else { await MainActor.run { error = "Разрешите доступ к камере в Системных настройках." }; return }
        guard !Task.isCancelled else { return }
        queue.async { [self] in
            do {
                session.beginConfiguration(); defer { session.commitConfiguration() }
                guard let device = AVCaptureDevice.default(for: .video) else { throw DesktopError("Камера не найдена.") }
                let input = try AVCaptureDeviceInput(device: device)
                guard session.canAddInput(input), session.canAddOutput(output) else { throw DesktopError("Камера недоступна.") }
                session.addInput(input); session.addOutput(output); session.sessionPreset = .photo
            } catch { DispatchQueue.main.async { self.error = error.localizedDescription }; return }
            session.startRunning(); DispatchQueue.main.async { self.ready = true }
        }
    }
    func stop() { queue.async { self.session.stopRunning() } }
    func capture() { queue.async { self.output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self) } }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        do {
            if let error { throw error }
            guard let data = photo.fileDataRepresentation() else { throw DesktopError("Снимок не получен.") }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("NIKA-camera-\(UUID().uuidString).jpg")
            try data.write(to: url); DispatchQueue.main.async { self.captured?(url) }
        } catch { DispatchQueue.main.async { self.error = error.localizedDescription } }
    }
}
struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    final class Preview: NSView {
        var preview: AVCaptureVideoPreviewLayer?
        override func layout() { super.layout(); preview?.frame = bounds }
    }
    func makeNSView(context: Context) -> Preview {
        let view = Preview(); view.wantsLayer = true
        let preview = AVCaptureVideoPreviewLayer(session: session); preview.videoGravity = .resizeAspect
        view.layer?.addSublayer(preview); view.preview = preview; return view
    }
    func updateNSView(_ view: Preview, context: Context) { view.preview?.frame = view.bounds }
}
struct CameraSheet: View {
    @StateObject private var camera = CameraController()
    @Environment(\.dismiss) private var dismiss
    let captured: (URL) -> Void
    var body: some View {
        VStack(spacing: 16) {
            HStack { Text("Снимок с камеры").font(.title2); Spacer(); Button("Отмена") { dismiss() } }
            CameraPreview(session: camera.session).frame(width: DesktopFormLayout.width(628) - 48, height: min(360, DesktopFormLayout.height(520) - 160)).background(.black).clipShape(RoundedRectangle(cornerRadius: 16))
            if let error = camera.error { Text(error).foregroundStyle(.red) }
            Button("Сделать снимок") { camera.capture() }.buttonStyle(.borderedProminent).disabled(!camera.ready)
            Text("Снимок добавится в черновик. Отправка произойдёт после вашего нажатия.").font(.caption).foregroundStyle(.secondary)
        }.padding(24).task { camera.captured = { captured($0); dismiss() }; await camera.start() }.onDisappear { camera.stop() }
    }
}
struct DesktopAttachment: Codable, Equatable, Identifiable {
    var id: String { path }
    let path: String
    let name: String
    let mime: String
}
struct InlineAttachment: View {
    let attachment: DesktopAttachment
    let client: BFFClient
    @State private var player: AVPlayer?
    @State private var file: URL?
    @State private var error: String?
    @State private var loading = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if attachment.mime.hasPrefix("image/"), let url { AuthenticatedImage(url: url, client: client).frame(maxHeight: 380) }
            else if let player { VideoPlayer(player: player).frame(height: attachment.mime.hasPrefix("audio/") ? 90 : 300) }
            HStack {
                Label(attachment.name, systemImage: attachment.mime.hasPrefix("video/") ? "film" : "doc")
                if attachment.mime.hasPrefix("video/") || attachment.mime.hasPrefix("audio/") { Button("Воспроизвести") { Task { await load(play: true) } }.disabled(loading) }
                Button("Сохранить…") { Task { await load(play: false) } }.disabled(loading)
                if loading { ProgressView().controlSize(.small) }
            }.font(.caption)
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }.onDisappear { player?.pause(); player = nil; if let file { try? FileManager.default.removeItem(at: file) }; file = nil }
    }
    private var url: URL? { URL(string: attachment.path, relativeTo: client.baseURL)?.absoluteURL }
    private func load(play: Bool) async {
        guard let url, ["https", "http"].contains(url.scheme ?? "") else { return }
        loading = true; defer { loading = false }
        do {
            let local: URL
            if let file { local = file }
            else {
                var request = URLRequest(url: url)
                if url.host == client.baseURL.host && url.port == client.baseURL.port && url.scheme == client.baseURL.scheme {
                    try await client.ensureFreshAccessToken()
                    if let token = await client.currentTokens()?.accessToken { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
                }
                let (temporary, response) = try await URLSession.shared.download(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw DesktopError("Файл недоступен.") }
                local = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(URL(fileURLWithPath: attachment.name).pathExtension)
                try FileManager.default.moveItem(at: temporary, to: local); file = local
            }
            if play { player = AVPlayer(url: local); player?.play() }
            else { let panel = NSSavePanel(); panel.nameFieldStringValue = attachment.name; if await panel.begin() == .OK, let target = panel.url { try Data(contentsOf: local, options: .mappedIfSafe).write(to: target, options: .atomic) } }
        } catch { self.error = error.localizedDescription }
    }
}
