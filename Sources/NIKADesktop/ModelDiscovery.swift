import SwiftUI
import CryptoKit

struct HubRepository: Decodable, Identifiable {
    let id: String
    let downloads: Int?
    let tags: [String]?
}
struct HubModelInfo: Decodable {
    struct File: Decodable {
        struct LFS: Decodable { let sha256: String; let size: Int64 }
        let rfilename: String; let lfs: LFS?
    }
    let id: String
    let sha: String
    let siblings: [File]
    let cardData: [String: BFFJSONValue]?
    let gguf: [String: BFFJSONValue]?
    let tags: [String]?
    func models() -> [DesktopModel] {
        siblings.compactMap { file in
            guard file.rfilename.lowercased().hasSuffix(".gguf"), !file.rfilename.lowercased().contains("mmproj"),
                  !file.rfilename.contains("-of-"), let lfs = file.lfs, lfs.sha256.count == 64, lfs.size > 0 else { return nil }
            let name = URL(fileURLWithPath: file.rfilename).deletingPathExtension().lastPathComponent
            let identity = String(SHA256.hash(data: Data((id + sha + file.rfilename).utf8)).map { String(format: "%02x", $0) }.joined().prefix(20))
            var model = DesktopModel(id: "hub-" + identity, name: name, publisher: id.components(separatedBy: "/").first ?? id,
                                     parameters: "См. карточку издателя", quantization: name.components(separatedBy: "-").last ?? "GGUF",
                                     bytes: lfs.size, sha256: lfs.sha256,
                                     url: URL(string: "https://huggingface.co")!.appendingPathComponent(id).appendingPathComponent("resolve").appendingPathComponent(sha).appendingPathComponent(file.rfilename), filename: identity + ".gguf", imported: false)
            model.repository = id; model.tags = tags
            if case .string(let value) = cardData?["license"] { model.license = value }
            if case .number(let value) = gguf?["context_length"] { model.contextLimit = Int(value) }
            if case .string(let value) = gguf?["architecture"] { model.architecture = value }
            if let projector = siblings.first(where: { $0.rfilename == "mmproj-F16.gguf" }), let lfs = projector.lfs {
                model.visionProjector = VisionProjector(bytes: lfs.size, sha256: lfs.sha256, url: URL(string: "https://huggingface.co")!.appendingPathComponent(id).appendingPathComponent("resolve").appendingPathComponent(sha).appendingPathComponent(projector.rfilename))
            }
            return model
        }
    }
}
enum HubDiscovery {
    static func search(_ query: String) async throws -> [HubRepository] {
        var parts = URLComponents(string: "https://huggingface.co/api/models")!
        parts.queryItems = [.init(name: "search", value: query), .init(name: "filter", value: "gguf"), .init(name: "sort", value: "downloads"), .init(name: "direction", value: "-1"), .init(name: "limit", value: "30")]
        return try await fetch(parts.url!)
    }
    static func details(_ id: String) async throws -> HubModelInfo {
        var parts = URLComponents(url: URL(string: "https://huggingface.co/api/models")!.appendingPathComponent(id), resolvingAgainstBaseURL: false)!
        parts.queryItems = [.init(name: "blobs", value: "true")]
        return try await fetch(parts.url!)
    }
    private static func fetch<T: Decodable>(_ url: URL) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 30))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw DesktopError("Каталог недоступен. Проверьте соединение или попробуйте позже.") }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
struct ModelDiscoveryView: View {
    @ObservedObject var library: ModelLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var query = "Qwen"
    @State private var repositories: [HubRepository] = []
    @State private var variants: [DesktopModel] = []
    @State private var selected: String?
    @State private var loading = false
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { Text("Найти локальную модель").font(.title2); Spacer(); Button("Готово") { dismiss() } }
            HStack {
                TextField("Название или издатель", text: $query).textFieldStyle(.roundedBorder).onSubmit { search() }
                Button("Найти", action: search).disabled(loading)
            }
            Text("Публичный каталог Hugging Face · цельные GGUF-файлы с проверяемой SHA-256. Совместимость с движком проверяется при загрузке.").font(.caption).foregroundStyle(.secondary)
            if loading { ProgressView() }
            if let error { Text(error).foregroundStyle(.red) }
            HSplitView {
                List(repositories) { repo in
                    Button { selected = repo.id; variants = []; loading = true; Task {
                        do { let info = try await HubDiscovery.details(repo.id); if selected == repo.id { variants = info.models(); error = variants.isEmpty ? "Нет цельных GGUF с контрольной суммой. Шардированные модели требуют другого пакета." : nil } }
                        catch { self.error = error.localizedDescription }; loading = false
                    } } label: { VStack(alignment: .leading, spacing: 4) { Text(repo.id).font(.callout); if let n = repo.downloads { Text("\(n) загрузок за месяц").font(.caption).foregroundStyle(.secondary) } } }.buttonStyle(.plain)
                }.frame(minWidth: 220, idealWidth: 270)
                ScrollView { LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(variants) { model in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(model.name).font(.headline)
                            Text("\(ByteCountFormatter.string(fromByteCount: model.bytes, countStyle: .file)) · \(model.license ?? "Лицензия не указана")").font(.caption)
                            if !library.compatible(model) { Label("Может не хватить памяти", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
                            HStack {
                                if let repository = model.repository, let url = URL(string: "https://huggingface.co/" + repository) { Link("Карточка", destination: url) }
                                Spacer()
                                Button(library.installed.contains(model.id) ? "Установлена" : library.progress[model.id] != nil ? "В загрузках" : "Загрузить") { library.addDiscovered(model); library.download(model) }
                                    .disabled(library.installed.contains(model.id) || library.progress[model.id] != nil)
                            }
                        }.padding(16).nikaGlass()
                    }
                }.padding(10) }.frame(minWidth: 350)
            }
        }.padding(24).frame(width: DesktopFormLayout.width(840), height: DesktopFormLayout.height(580)).background { AuroraCanvas() }.task { search() }
    }
    private func search() { loading = true; error = nil; Task { do { repositories = try await HubDiscovery.search(query) } catch { self.error = error.localizedDescription }; loading = false } }
}
