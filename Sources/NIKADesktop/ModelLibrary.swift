import Foundation
import CryptoKit
import SwiftUI
import UniformTypeIdentifiers

struct VisionProjector: Codable, Equatable, Sendable {
    let bytes: Int64; let sha256: String; let url: URL
}
struct DesktopModel: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let name: String
    let publisher: String
    let parameters: String
    let quantization: String
    let bytes: Int64
    let sha256: String
    let url: URL?
    let filename: String
    var imported = false
    var repository: String?
    var license: String?
    var contextLimit: Int?
    var architecture: String?
    var visionProjector: VisionProjector?
    var auxiliaryFor: String?
    var tags: [String]?
    var summary: String { repository != nil || imported ? "\(architecture ?? "GGUF") · \(quantization)" : "Qwen3.5 · \(parameters) · \(quantization)" }
    var memoryEstimate: Int64 { LocalMemoryBudget.requiredBytes(modelBytes: bytes, context: 4096) }
    func fits(memory: UInt64) -> Bool { memoryEstimate < Int64(clamping: memory) }
    static let legacyCatalogue: [DesktopModel] = [
        .init(id: "mini", name: "NIKA Mini", publisher: "Qwen · GGUF by unsloth", parameters: "0.8B", quantization: "Q8_0", bytes: 811_843_840,
              sha256: "0ad885ffd4bb022fc4f0d33a3308fa108ef8613159d3b3a67e23abca056b7a6c",
              url: URL(string: "https://huggingface.co/unsloth/Qwen3.5-0.8B-GGUF/resolve/6ab461498e2023f6e3c1baea90a8f0fe38ab64d0/Qwen3.5-0.8B-Q8_0.gguf?download=true"), filename: "Qwen3.5-0.8B-Q8_0.gguf", contextLimit: 262144, architecture: "qwen35",
              visionProjector: .init(bytes: 204987232, sha256: "56e4c6cfe73b0c82e3e82bc518d7591997e61d81f723fc41a586f4fa69ea2453", url: URL(string: "https://huggingface.co/unsloth/Qwen3.5-0.8B-GGUF/resolve/6ab461498e2023f6e3c1baea90a8f0fe38ab64d0/mmproj-F16.gguf")!)),
        .init(id: "balance", name: "NIKA Balance", publisher: "Qwen · GGUF by unsloth", parameters: "2B", quantization: "Q5_K_M", bytes: 1_435_238_656,
              sha256: "1885b3a9195f8cc09da9a7a7a75afdc1e8d5cbf9fc4a499c3961dddea37098ac",
              url: URL(string: "https://huggingface.co/unsloth/Qwen3.5-2B-GGUF/resolve/f6d5376be1edb4d416d56da11e5397a961aca8ae/Qwen3.5-2B-Q5_K_M.gguf?download=true"), filename: "Qwen3.5-2B-Q5_K_M.gguf", contextLimit: 262144, architecture: "qwen35",
              visionProjector: .init(bytes: 668227264, sha256: "7035e9cb8d7c6a9681d07eef9a364783e86ea4cd73faab2eabb4f43a101830c7", url: URL(string: "https://huggingface.co/unsloth/Qwen3.5-2B-GGUF/resolve/f6d5376be1edb4d416d56da11e5397a961aca8ae/mmproj-F16.gguf")!)),
        .init(id: "smart", name: "NIKA Smart", publisher: "Qwen · GGUF by unsloth", parameters: "4B", quantization: "Q4_K_M", bytes: 2_740_937_888,
              sha256: "00fe7986ff5f6b463e62455821146049db6f9313603938a70800d1fb69ef11a4",
              url: URL(string: "https://huggingface.co/unsloth/Qwen3.5-4B-GGUF/resolve/e87f176479d0855a907a41277aca2f8ee7a09523/Qwen3.5-4B-Q4_K_M.gguf?download=true"), filename: "Qwen3.5-4B-Q4_K_M.gguf", contextLimit: 262144, architecture: "qwen35",
              visionProjector: .init(bytes: 672423616, sha256: "cd88edcf8d031894960bb0c9c5b9b7e1fea6ebee02b9f7ce925a00d12891f864", url: URL(string: "https://huggingface.co/unsloth/Qwen3.5-4B-GGUF/resolve/e87f176479d0855a907a41277aca2f8ee7a09523/mmproj-F16.gguf")!))
    ]
    // Keep stable legacy IDs/filenames so existing chats, downloads and projectors still resolve.
    static let catalogue: [DesktopModel] = [
        legacyCatalogue[2],
        .init(id: "desktop-quality", name: "NIKA Quality", publisher: "Qwen · GGUF by unsloth", parameters: "4B", quantization: "Q5_K_M", bytes: 3_143_656_608,
              sha256: "8814232b85594dcd46c50e5b8b29324a7efe9e746edbe8a3d1df3d3fce7aad39",
              url: URL(string: "https://huggingface.co/unsloth/Qwen3.5-4B-GGUF/resolve/e87f176479d0855a907a41277aca2f8ee7a09523/Qwen3.5-4B-Q5_K_M.gguf?download=true"), filename: "Qwen3.5-4B-Q5_K_M.gguf", contextLimit: 262144, architecture: "qwen35", visionProjector: legacyCatalogue[2].visionProjector),
        legacyCatalogue[1]
    ]

}

struct ModelProgress {
    var received: Int64 = 0
    var total: Int64 = 0
    var started = Date()
    var initialBytes: Int64 = 0
    var state = "Ожидание"
    var fraction: Double { total > 0 ? min(1, Double(received) / Double(total)) : 0 }
    var speed: Double { Double(max(0, received - initialBytes)) / max(1, Date().timeIntervalSince(started)) }
}

@MainActor
final class ModelLibrary: ObservableObject {
    @Published var models = DesktopModel.catalogue
    @Published var installed: Set<String> = []
    @Published var progress: [String: ModelProgress] = [:]
    @Published var error: String?
    @Published var loadedID: String?
    @Published var loadingID: String?
    @Published var relocating = false
    @Published var residentBytes: Int64?
    @Published var directory: URL
    let runtime = LlamaProvider()
    private var tasks: [String: DurableDownload] = [:]
    private var cancelled = Set<String>()
    private var queue: [DesktopModel] = []
    private var paused = Set<String>()
    private var bookmark: URL?
    private let manifest: URL

    init(root: URL = DesktopStore.supportDirectory) {
        manifest = root.appendingPathComponent("imported-models.json")
        directory = root.appendingPathComponent("Models", isDirectory: true)
        if root == DesktopStore.supportDirectory, ProcessInfo.processInfo.environment["NIKA_DESKTOP_DATA"] == nil, let data = UserDefaults.standard.data(forKey: "models.bookmark") {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, bookmarkDataIsStale: &stale), url.startAccessingSecurityScopedResource() {
                directory = url; bookmark = url
            }
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: manifest.path) {
                let saved = try JSONDecoder().decode([DesktopModel].self, from: Data(contentsOf: manifest))
                models += saved.filter { item in !models.contains { $0.id == item.id } }
            }
        } catch { self.error = error.localizedDescription }
        models += DesktopModel.legacyCatalogue.filter { legacy in !models.contains { $0.id == legacy.id } }
        for model in models {
            if FileManager.default.fileExists(atPath: file(model).path) { installed.insert(model.id) }
            else if FileManager.default.fileExists(atPath: partialFile(model.id).path) { progress[model.id] = ModelProgress(received: Int64((try? partialFile(model.id).resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0), total: model.bytes, state: "Приостановлено"); paused.insert(model.id) }
        }
    }
    func file(_ model: DesktopModel) -> URL { directory.appendingPathComponent(model.filename) }
    func resumeFile(_ id: String) -> URL { directory.appendingPathComponent(".\(id).resume") }
    func partialFile(_ id: String) -> URL { directory.appendingPathComponent(".\(id).part") }
    func compatible(_ model: DesktopModel) -> Bool { model.fits(memory: ProcessInfo.processInfo.physicalMemory) }
    var freeBytes: Int64 { Int64((try? FileManager.default.attributesOfFileSystem(forPath: directory.path)[.systemFreeSize] as? NSNumber)?.int64Value ?? 0) }

    func download(_ model: DesktopModel) {
        guard !relocating, progress[model.id]?.state != "Проверка SHA-256" else { return }
        guard !installed.contains(model.id), !queue.contains(where: { $0.id == model.id }), tasks[model.id] == nil else { return }
        let prefix = Int64((try? partialFile(model.id).resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        guard freeBytes > max(0, model.bytes - prefix) + 512_000_000 else { error = "Недостаточно места на диске."; return }
        paused.remove(model.id); cancelled.remove(model.id)
        progress[model.id] = ModelProgress(received: prefix, total: model.bytes, initialBytes: prefix)
        queue.append(model); startNext()
    }
    private func startNext() {
        guard tasks.isEmpty, !queue.isEmpty else { return }
        let model = queue.removeFirst()
        guard let url = model.url else { startNext(); return }
        let key = model.id
        do {
            let transfer = try DurableDownload(url: url, partial: partialFile(key), expected: model.bytes, progress: { [weak self] received in
                Task { @MainActor in self?.progress[key]?.received = received }
            }, finished: { [weak self] error in Task { @MainActor in await self?.complete(key: key, failure: error) } })
            tasks[key] = transfer; progress[key]?.state = "Загрузка"; transfer.start()
        } catch { self.error = error.localizedDescription; progress[key]?.state = "Ошибка — повторите загрузку"; startNext() }
    }
    func pause(_ model: DesktopModel) {
        paused.insert(model.id); queue.removeAll { $0.id == model.id }
        progress[model.id]?.state = "Приостановлено"; tasks[model.id]?.cancel()
    }
    func cancel(_ model: DesktopModel) {
        paused.insert(model.id); cancelled.insert(model.id); queue.removeAll { $0.id == model.id }
        progress.removeValue(forKey: model.id)
        if let task = tasks[model.id] { task.cancel() }
        else { try? FileManager.default.removeItem(at: partialFile(model.id)) }
        try? FileManager.default.removeItem(at: resumeFile(model.id))
    }
    private func complete(key: String, failure: Error?) async {
        guard tasks.removeValue(forKey: key) != nil, let model = models.first(where: { $0.id == key }) else { return }
        defer { startNext() }
        if cancelled.contains(key) { try? FileManager.default.removeItem(at: partialFile(key)); return }
        if paused.contains(key) { return }
        if let failure { progress[key]?.state = "Ошибка — повторите загрузку"; error = failure.localizedDescription; return }
        progress[key]?.state = "Проверка SHA-256"
        let temporary = partialFile(key)
        do {
            try await Task.detached { try Self.verify(temporary, expectedBytes: model.bytes, expectedHash: model.sha256) }.value
            guard !paused.contains(key) else { return }
            let final = file(model)
            if FileManager.default.fileExists(atPath: final.path) { throw DesktopError("Файл уже существует.") }
            try FileManager.default.moveItem(at: temporary, to: final)
            installed.insert(key); progress.removeValue(forKey: key)
        } catch {
            // An invalid complete prefix cannot be repaired by requesting more bytes.
            try? FileManager.default.removeItem(at: temporary)
            self.error = error.localizedDescription; progress[key]?.state = "Проверка не пройдена — повторите"
        }
    }
    nonisolated static func verify(_ file: URL, expectedBytes: Int64, expectedHash: String) throws {
        let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard Int64(size) == expectedBytes else { throw DesktopError("Размер файла отличается от каталога.") }
        guard try digest(file) == expectedHash.lowercased() else { throw DesktopError("Контрольная сумма не совпала. Файл не установлен.") }
    }
    nonisolated static func digest(_ file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file); defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty { try Task.checkCancellation(); hash.update(data: chunk) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    func visionModel(_ model: DesktopModel) -> DesktopModel? { models.first { $0.auxiliaryFor == model.id } }
    func downloadVision(_ model: DesktopModel) {
        guard let vision = model.visionProjector else { return }
        let item = DesktopModel(id: model.id + "-vision", name: model.name + " · изображения", publisher: model.publisher, parameters: "Проектор", quantization: "F16", bytes: vision.bytes, sha256: vision.sha256, url: vision.url, filename: model.id + "-mmproj.gguf", repository: model.repository, license: model.license, auxiliaryFor: model.id)
        addDiscovered(item); download(item)
    }
    func load(_ model: DesktopModel, settings: InferenceSettings, vision: Bool = false) async throws {
        guard !relocating, loadingID == nil else { throw DesktopError("Другая модель ещё загружается.") }
        loadingID = model.id; defer { loadingID = nil }
        let url = file(model)
        try await Task.detached { try Self.verify(url, expectedBytes: model.bytes, expectedHash: model.sha256) }.value
        var projector: URL?
        if vision {
            guard let item = visionModel(model), installed.contains(item.id) else { throw DesktopError("Для изображений установите дополнение в карточке модели → Работа с изображениями.") }
            let path = file(item)
            try await Task.detached { try Self.verify(path, expectedBytes: item.bytes, expectedHash: item.sha256) }.value
            projector = path
        }
        try await runtime.load(model: url, settings: settings, projector: projector)
        loadedID = model.id
    }
    func unload() async { await runtime.unload(); loadedID = nil }
    func delete(_ model: DesktopModel) async {
        guard !relocating else { error = "Дождитесь переноса файлов."; return }
        do {
            if loadedID == model.id || model.auxiliaryFor == loadedID { await unload() }
            cancel(model)
            try FileManager.default.removeItem(at: file(model)); installed.remove(model.id)
            if model.imported { models.removeAll { $0.id == model.id }; try persistImports() }
        } catch { self.error = error.localizedDescription }
    }
    private func persistImports() throws { try JSONEncoder().encode(models.filter { $0.imported || $0.repository != nil || $0.auxiliaryFor != nil }).write(to: manifest, options: .atomic) }
    func addDiscovered(_ model: DesktopModel) {
        guard !models.contains(where: { $0.id == model.id }) else { return }
        models.append(model)
        do { try persistImports() } catch { self.error = error.localizedDescription }
    }
    func importModel(_ source: URL) async {
        guard !relocating else { error = "Дождитесь переноса файлов."; return }
        let access = source.startAccessingSecurityScopedResource(); defer { if access { source.stopAccessingSecurityScopedResource() } }
        do {
            let destination = directory.appendingPathComponent("\(UUID().uuidString)-\(source.lastPathComponent)")
            let size = Int64(try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
            guard freeBytes > size + 512_000_000 else { throw DesktopError("Недостаточно места для импорта.") }
            let hash = try await Task.detached {
                let handle = try FileHandle(forReadingFrom: source); defer { try? handle.close() }
                guard try handle.read(upToCount: 4) == Data("GGUF".utf8) else { throw DesktopError("Выберите файл модели GGUF.") }
                try FileManager.default.copyItem(at: source, to: destination)
                return try Self.digest(destination)
            }.value
            let model = DesktopModel(id: UUID().uuidString, name: source.deletingPathExtension().lastPathComponent,
                                     publisher: "Импортировано с Mac", parameters: "Не проверено", quantization: "GGUF",
                                     bytes: size, sha256: hash, url: nil, filename: destination.lastPathComponent, imported: true)
            models.append(model); installed.insert(model.id); try persistImports()
        } catch { self.error = error.localizedDescription }
    }
    func chooseDirectory(_ url: URL) async throws {
        guard url.standardizedFileURL != directory.standardizedFileURL else { return }
        guard tasks.isEmpty, queue.isEmpty, loadingID == nil, loadedID == nil, !relocating else { throw DesktopError("Приостановите загрузки и выгрузите модель из памяти перед переносом.") }
        relocating = true; defer { relocating = false }
        let access = url.startAccessingSecurityScopedResource()
        let original = directory
        let files = models.flatMap { model -> [URL] in [file(model), partialFile(model.id), resumeFile(model.id)].filter { FileManager.default.fileExists(atPath: $0.path) } }
        do {
            let bookmarkData = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            try await Task.detached {
                let manager = FileManager.default
                let total = try files.reduce(Int64(0)) { $0 + Int64(try $1.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) }
                let available = (try manager.attributesOfFileSystem(forPath: url.path)[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
                guard available > total + 512_000_000 else { throw DesktopError("В новой папке недостаточно свободного места.") }
                for file in files where manager.fileExists(atPath: url.appendingPathComponent(file.lastPathComponent).path) { throw DesktopError("В новой папке уже есть файл \(file.lastPathComponent). Выберите пустую папку.") }
                var copied: [URL] = []
                do {
                    for file in files {
                        let target = url.appendingPathComponent(file.lastPathComponent)
                        try manager.copyItem(at: file, to: target); copied.append(target)
                        guard try Self.digest(file) == Self.digest(target) else { throw DesktopError("Проверка перенесённого файла не пройдена.") }
                    }
                } catch { for file in copied { try? manager.removeItem(at: file) }; throw error }
            }.value
            UserDefaults.standard.set(bookmarkData, forKey: "models.bookmark")
            directory = url; bookmark?.stopAccessingSecurityScopedResource(); bookmark = access ? url : nil
            for file in files where file.deletingLastPathComponent() == original { try? FileManager.default.removeItem(at: file) }
        } catch { if access { url.stopAccessingSecurityScopedResource() }; throw error }
    }
    func pauseAll() { for model in models where tasks[model.id] != nil { pause(model) } }
}
