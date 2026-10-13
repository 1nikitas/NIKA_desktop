import SwiftUI

struct MediaView: View {
    @ObservedObject var store: DesktopStore
    @ObservedObject var workspace: Workspace
    let openChat: () -> Void
    let signIn: () -> Void
    @State private var frames: [BFFRemoteMediaFrame] = []
    @State private var loading = false
    @State private var error: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack { Text("Медиа").font(.system(size: 30, weight: .medium, design: .rounded)); Spacer(); Button("Создать изображение") { workspace.newChat(provider: "cloud"); workspace.imageMode = true; openChat() } }
                Text("Изображения, созданные NIKA в ваших разговорах.").foregroundStyle(.secondary)
                if store.client == nil { Button("Войти", action: signIn) }
                else if loading { ProgressView("Загрузка изображений…") }
                else if let error { Text(error).foregroundStyle(.red); Button("Повторить") { Task { await refresh() } } }
                else if frames.isEmpty { EmptyWorkspace(symbol: "photo.on.rectangle", title: "Первый кадр впереди", detail: "Опишите изображение в чате. Сохранённый результат появится здесь.").frame(height: 280) }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 20)], spacing: 20) {
                    ForEach(frames) { frame in VStack(alignment: .leading, spacing: 12) {
                        if let client = store.client { AuthenticatedImage(url: client.baseURL.appendingPathComponent("api/files/\(frame.id)"), client: client).frame(height: 200).clipped() }
                        Text(frame.prompt.isEmpty ? "Изображение NIKA" : frame.prompt).font(.callout).lineLimit(3)
                        Button("Открыть разговор") { Task { do { guard let client = store.client else { return }; await workspace.open(try await client.fetchChatInfo(id: frame.chatID)); openChat() } catch { self.error = error.localizedDescription } } }
                    }.padding(16).background(DesktopStyle.surface, in: RoundedRectangle(cornerRadius: 14)) }
                }
            }.padding(32)
        }.task { await refresh() }
    }
    private func refresh() async {
        guard let client = store.client else { return }; loading = true; defer { loading = false }
        do {
            frames = try await client.listMediaFrames()
        } catch BFFClientError.http(let status, _) where status == 404 {
            // Same deployed-server fallback as the mobile BFFChatService.
            do {
                var found: [BFFRemoteMediaFrame] = []
                for info in try await client.listChatsForDisplay() {
                    let chat = try await client.fetchChat(info)
                    for message in chat.messages where message.role == .assistant {
                        for attachment in message.attachments ?? [] where attachment.mimeType?.hasPrefix("image/") == true || attachment.kind == "image" {
                            guard let id = attachment.fileID else { continue }
                            found.append(BFFRemoteMediaFrame(id: id, chatID: info.id, messageID: message.id, taskID: message.taskID, prompt: message.content, filename: attachment.filename ?? "image", mimeType: attachment.mimeType ?? "image/png", createdAt: message.createdAt))
                        }
                    }
                }
                var ids = Set<String>(); frames = found.filter { ids.insert($0.id).inserted }
            } catch { self.error = error.localizedDescription }
        } catch { self.error = error.localizedDescription }
    }
}
struct AuthenticatedImage: View {
    let url: URL
    let client: BFFClient
    @State private var image: NSImage?
    @State private var failed = false
    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().scaledToFit() }
            else if failed { Label("Не удалось загрузить", systemImage: "photo.badge.exclamationmark") }
            else { ProgressView() }
        }.frame(maxWidth: .infinity).task(id: url) {
            do {
                guard url.host == client.baseURL.host, url.scheme == client.baseURL.scheme else { throw DesktopError("Недопустимый адрес файла.") }
                try await client.ensureFreshAccessToken()
                var request = URLRequest(url: url)
                if let token = await client.currentTokens()?.accessToken { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
                let (data, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200, let decoded = NSImage(data: data) else { throw DesktopError("Изображение недоступно.") }
                image = decoded
            } catch { failed = true }
        }
    }
}
