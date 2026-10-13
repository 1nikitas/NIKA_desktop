import Foundation

/// Additional Muse routes use the same BFF token owner and refresh mechanism.
struct DesktopAPI: Sendable {
    let client: BFFClient
    var session: URLSession = .shared
    func request<T: Decodable>(_ path: String, method: String = "GET", body: [String: BFFJSONValue]? = nil, query: [URLQueryItem] = []) async throws -> T {
        for attempt in 0...1 {
            try await client.ensureFreshAccessToken(margin: attempt == 0 ? 60 : 31_536_000)
            guard let tokens = await client.currentTokens() else { throw BFFClientError.sessionExpired }
            var parts = URLComponents(url: client.baseURL.appendingPathComponent("api").appendingPathComponent(path), resolvingAgainstBaseURL: false)!
            if !query.isEmpty { parts.queryItems = query; parts.percentEncodedQuery = parts.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B") }
            guard let url = parts.url else { throw BFFClientError.invalidResponse }
            var request = URLRequest(url: url)
            request.timeoutInterval = 30; request.httpMethod = method
            request.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
            if let body { request.httpBody = try JSONEncoder().encode(body); request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw BFFClientError.invalidResponse }
            if http.statusCode == 401 && attempt == 0 { continue }
            guard (200..<300).contains(http.statusCode) else { throw BFFClientError.http(statusCode: http.statusCode, message: String(data: data.prefix(1000), encoding: .utf8) ?? "Запрос не выполнен") }
            return try JSONDecoder().decode(T.self, from: data.isEmpty ? Data("{}".utf8) : data)
        }
        throw BFFClientError.sessionExpired
    }
    func activeChats() async throws -> [ActiveDesktopChat] { try await request("chats/active") }
}
struct EmptyResponse: Decodable {}
struct ActiveDesktopChat: Decodable, Identifiable {
    let id: String
    let title: String
    let active_task_text: String?
    let active_task_status: String?
    let tray_status: String
    var status: String { ["working": "В работе", "done": "Готово", "failed": "Не выполнено", "scheduled": "Запланировано"][tray_status] ?? tray_status }
}
struct DesktopMemory: Codable, Identifiable {
    var id = UUID().uuidString
    var title: String
    var detail: String
    var kind = "personal"
    var isPinned = false
    var createdAt = Date()
    var updatedAt = Date()
}
struct DesktopGoal: Identifiable {
    let id: String; let title: String; let note: String; let steps: [Step]; var targetDate: String?
    struct Step: Identifiable { let id: String; let title: String; let done: Bool; var scheduledAt: String? }
    static func decode(_ value: BFFJSONValue) -> DesktopGoal? {
        guard case .object(let object) = value, case .string(let id) = object["id"], case .string(let title) = object["description"] else { return nil }
        var note = ""; if case .string(let text) = object["note"] { note = text }
        var steps: [Step] = []
        if case .array(let array) = object["milestones"] {
            steps = array.compactMap { value in
                guard case .object(let fields) = value, case .string(let id) = fields["id"], case .string(let title) = fields["title"] else { return nil }
                var scheduled: String?; if case .string(let value) = fields["scheduled_at"] { scheduled = value }; return Step(id: id, title: title, done: fields["status"] == .string("done"), scheduledAt: scheduled)
            }
        }
        var target: String?; if case .string(let value) = object["target_date"] { target = value }; return DesktopGoal(id: id, title: title, note: note, steps: steps, targetDate: target)
    }
}

struct DesktopSearchHit: Decodable, Identifiable {
    let chat_id: String
    let message_id: String
    let snippet: String
    var id: String { message_id }
}
