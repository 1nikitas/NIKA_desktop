import Foundation
import Darwin

/// Conservative admission estimate, not a measurement of free RAM or a guarantee against swap.
enum LocalMemoryBudget {
    static func contextLimit(memory: UInt64) -> Int { memory <= 8 * 1_073_741_824 ? 4096 : 16384 }
    static func requiredBytes(modelBytes: Int64, context: Int) -> Int64 {
        modelBytes + Int64(max(0, min(context, 16384))) * 262_144 + 1_073_741_824 + 3 * 1_073_741_824
    }
    static func permits(modelBytes: Int64, context: Int, memory: UInt64) -> Bool {
        context > 0 && context <= contextLimit(memory: memory)
            && requiredBytes(modelBytes: modelBytes, context: context) < Int64(clamping: memory)
    }
}

struct InferenceSettings: Codable, Equatable, Sendable {
    var context = 4096
    var temperature = 0.7
    var topP = 0.9
    var maxTokens = 1024
    var thinking: Bool?
}
struct InferenceMessage: Encodable, Sendable {
    let role: String; let content: String; var images: [String] = []
    enum CodingKeys: String, CodingKey { case role, content }
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self); try container.encode(role, forKey: .role)
        if images.isEmpty { try container.encode(content, forKey: .content) }
        else {
            var parts: [BFFJSONValue] = [.object(["type": .string("text"), "text": .string(content)])]
            parts += images.map { .object(["type": .string("image_url"), "image_url": .object(["url": .string($0)])]) }
            try container.encode(parts, forKey: .content)
        }
    }
}

protocol LocalModelProvider: Sendable {
    func load(model: URL, settings: InferenceSettings) async throws
    func unload() async
    func generate(messages: [InferenceMessage], settings: InferenceSettings) async throws -> AsyncThrowingStream<String, Error>
    func cancel() async
}

/// Child process owns Metal and heavy allocations. It only listens on loopback and uses
/// a random per-load key. No prompts or models are sent to a remote endpoint.
actor LlamaProvider: LocalModelProvider {
    private var process: Process?
    private var endpoint: URL?
    private var key = ""
    private var loaded: URL?
    private var loadedContext = 0
    private var loadedProjector: URL?
    private var generation: Task<Void, Never>?
    private var generationID = UUID()
    private var logURL: URL?
    private let session = URLSession(configuration: .ephemeral)

    static var executable: URL? {
        let candidates = [Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/llama-server").path,
                          "/opt/homebrew/bin/llama-server", "/usr/local/bin/llama-server"]
        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }).map(URL.init(fileURLWithPath:))
    }

    func load(model: URL, settings: InferenceSettings) async throws { try await load(model: model, settings: settings, projector: nil) }
    func load(model: URL, settings: InferenceSettings, projector: URL?) async throws {
        guard generation == nil else { throw DesktopError("Локальная модель отвечает в другом окне. Сначала остановите ответ.") }
        if loaded == model, loadedProjector == projector, loadedContext == settings.context, process?.isRunning == true { return }
        await unload()
        guard let executable = Self.executable else { throw DesktopError("Локальный движок не найден. Пересоберите приложение с llama.cpp.") }
        let size = ((try model.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0) + (try projector?.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
        guard LocalMemoryBudget.permits(modelBytes: Int64(size), context: settings.context, memory: ProcessInfo.processInfo.physicalMemory) else {
            throw DesktopError("Недостаточно запаса памяти для модели и контекста. На Mac с 8 ГБ выберите контекст 2048 или 4096; для изображений или больших моделей может понадобиться больше памяти.")
        }
        let port = try Self.availablePort()
        key = UUID().uuidString
        let child = Process()
        child.executableURL = executable
        child.arguments = ["-m", model.path, "--host", "127.0.0.1", "--port", String(port),
                           "--api-key", key, "-c", String(settings.context), "-np", "1", "--no-webui",
                           "--jinja", "--log-disable"]
        if let projector { child.arguments! += ["--mmproj", projector.path, "--image-max-tokens", "1024"] }
        let log = FileManager.default.temporaryDirectory.appendingPathComponent("nika-runtime-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let handle = try FileHandle(forWritingTo: log)
        child.standardOutput = handle; child.standardError = handle
        try child.run()
        try handle.close()
        process = child; logURL = log
        let base = URL(string: "http://127.0.0.1:\(port)")!
        do {
            for _ in 0..<240 {
                try Task.checkCancellation()
                guard child.isRunning else {
                    throw DesktopError("llama.cpp завершился (код \(child.terminationStatus)). Модель может быть несовместима с движком.")
                }
                var request = URLRequest(url: base.appendingPathComponent("health"), timeoutInterval: 2)
                request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
                if let (_, response) = try? await session.data(for: request), (response as? HTTPURLResponse)?.statusCode == 200 {
                    loaded = model; loadedProjector = projector; loadedContext = settings.context; endpoint = base
                    return
                }
                try await Task.sleep(for: .milliseconds(500))
            }
            throw DesktopError("Модель не загрузилась за две минуты. Попробуйте меньший контекст.")
        } catch { await unload(); throw error }
    }

    func unload() async {
        generation?.cancel(); generation = nil
        if let process, process.isRunning {
            process.terminate()
            for _ in 0..<20 {
                if !process.isRunning { break }
                try? await Task.sleep(for: .milliseconds(50))
            }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        process = nil; endpoint = nil; loaded = nil; loadedProjector = nil
        if let logURL { try? FileManager.default.removeItem(at: logURL) }
        logURL = nil
    }
    func residentMemory() -> Int64? {
        guard let process, process.isRunning else { return nil }
        let query = Process(); query.executableURL = URL(fileURLWithPath: "/bin/ps"); query.arguments = ["-o", "rss=", "-p", String(process.processIdentifier)]
        let pipe = Pipe(); query.standardOutput = pipe; query.standardError = FileHandle.nullDevice
        do { try query.run(); let data = pipe.fileHandleForReading.readDataToEndOfFile(); query.waitUntilExit(); guard query.terminationStatus == 0, let text = String(data: data, encoding: .utf8), let kib = Int64(text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }; return kib * 1024 } catch { return nil }
    }
    func cancel() async { generationID = UUID(); generation?.cancel(); generation = nil }
    private func cancel(_ id: UUID) { if generationID == id { generation?.cancel(); generation = nil } }

    func generate(messages: [InferenceMessage], settings: InferenceSettings) async throws -> AsyncThrowingStream<String, Error> {
        guard let endpoint, process?.isRunning == true else { throw DesktopError("Сначала загрузите модель.") }
        guard generation == nil else { throw DesktopError("Модель уже отвечает в другом окне.") }
        var request = URLRequest(url: endpoint.appendingPathComponent("v1/chat/completions"))
        request.httpMethod = "POST"; request.timeoutInterval = 600
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        struct Body: Encodable {
            let messages: [InferenceMessage]; let stream = true; let temperature: Double
            let top_p: Double; let max_tokens: Int
            let chat_template_kwargs: [String: Bool]
        }
        request.httpBody = try JSONEncoder().encode(Body(messages: messages, temperature: settings.temperature,
                                                        top_p: settings.topP, max_tokens: settings.maxTokens, chat_template_kwargs: ["enable_thinking": settings.thinking ?? false]))
        let (stream, continuation) = AsyncThrowingStream<String, Error>.makeStream()
        let id = UUID(); generationID = id
        generation = Task {
            do {
                let (bytes, response) = try await session.bytes(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                    throw DesktopError("Движок отклонил запрос. Уменьшите длину разговора или увеличьте контекст.")
                }
                for try await line in bytes.lines {
                    try Task.checkCancellation()
                    if let token = try Self.token(from: line) { continuation.yield(token) }
                }
                continuation.finish()
            } catch { continuation.finish(throwing: error) }
            if self.generationID == id { self.generation = nil }
        }
        continuation.onTermination = { @Sendable [weak self] _ in Task { await self?.cancel(id) } }
        return stream
    }

    nonisolated static func token(from line: String) throws -> String? {
        guard line.hasPrefix("data:") else { return nil }
        let value = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard value != "[DONE]", !value.isEmpty else { return nil }
        struct Chunk: Decodable {
            struct Choice: Decodable { struct Delta: Decodable { let content: String? }; let delta: Delta }
            let choices: [Choice]
        }
        return try JSONDecoder().decode(Chunk.self, from: Data(value.utf8)).choices.first?.delta.content
    }

    private static func availablePort() throws -> UInt16 {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw DesktopError("Не удалось открыть локальный порт.") }
        defer { close(fd) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bound == 0 else { throw DesktopError("Локальный порт недоступен.") }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
        }
        return UInt16(bigEndian: address.sin_port)
    }
}
