import Foundation

/// A durable prefix survives process death. Immutable catalogue URLs and final SHA-256
/// make a resumed file verifiable even if the server ignored or changed a range.
final class DurableDownload: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private var session: URLSession!
    private var task: URLSessionDataTask?
    private var handle: FileHandle?
    private let partial: URL
    private let expected: Int64
    private var offset: Int64 = 0
    private var received: Int64 = 0
    private var reported: Int64 = 0
    private var failure: Error?
    private let progress: @Sendable (Int64) -> Void
    private let finished: @Sendable (Error?) -> Void
    init(url: URL, partial: URL, expected: Int64, progress: @escaping @Sendable (Int64) -> Void, finished: @escaping @Sendable (Error?) -> Void) throws {
        self.partial = partial; self.expected = expected; self.progress = progress; self.finished = finished
        super.init()
        if !FileManager.default.fileExists(atPath: partial.path) { FileManager.default.createFile(atPath: partial.path, contents: nil) }
        handle = try FileHandle(forWritingTo: partial)
        offset = Int64(try handle!.seekToEnd()); received = offset
        if offset > expected { try handle!.truncate(atOffset: 0); offset = 0; received = 0 }
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        if offset > 0 { request.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range") }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForResource = 86_400
        let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
        task = session.dataTask(with: request)
    }
    func start() { task?.resume() }
    func cancel() { task?.cancel() }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        do {
            guard let http = response as? HTTPURLResponse else { throw DesktopError("Нет ответа сервера загрузки.") }
            if http.statusCode == 200 {
                try handle?.truncate(atOffset: 0); try handle?.seek(toOffset: 0); received = 0
            } else if http.statusCode == 206 {
                guard Self.validRange(http.value(forHTTPHeaderField: "Content-Range"), offset: offset, total: expected) else { throw DesktopError("Сервер вернул неверный диапазон файла. Отмените загрузку и начните заново.") }
            } else if http.statusCode == 416, offset == expected {
                completionHandler(.cancel); return
            } else { throw DesktopError("Сервер отклонил загрузку (\(http.statusCode)).") }
            progress(received); completionHandler(.allow)
        } catch { failure = error; completionHandler(.cancel) }
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        do {
            guard received + Int64(data.count) <= expected else { throw DesktopError("Файл больше заявленного размера.") }
            try handle?.write(contentsOf: data); received += Int64(data.count)
            if received - reported >= 262_144 || received == expected { reported = received; progress(received) }
        } catch { failure = error; dataTask.cancel() }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        do { try handle?.synchronize(); try handle?.close() } catch { if failure == nil { failure = error } }
        handle = nil
        let result: Error? = failure ?? (received == expected ? nil : error ?? DesktopError("Загрузка оборвалась. Загруженная часть сохранена."))
        finished(result); session.finishTasksAndInvalidate(); self.session = nil
    }
    static func validRange(_ value: String?, offset: Int64, total: Int64) -> Bool {
        guard let value, value.hasPrefix("bytes ") else { return false }
        let parts = value.dropFirst(6).split(separator: "/")
        guard parts.count == 2, Int64(parts[1]) == total else { return false }
        let bounds = parts[0].split(separator: "-")
        return bounds.count == 2 && Int64(bounds[0]) == offset && Int64(bounds[1]) == total - 1
    }
}
