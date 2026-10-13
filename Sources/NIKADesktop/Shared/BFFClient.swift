import Foundation

// MARK: - Authentication

public struct BFFAuthTokens: Codable, Equatable, Sendable {
    public let accessToken: String
    public let refreshToken: String

    public init(accessToken: String, refreshToken: String) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
    }
}

public struct BFFAuthenticatedSession: Codable, Equatable, Sendable {
    public let username: String
    public let clientID: String
    public let tokens: BFFAuthTokens

    public init(username: String, clientID: String, tokens: BFFAuthTokens) {
        self.username = username
        self.clientID = clientID
        self.tokens = tokens
    }
}

/// `GET /api/auth/telegram-config` — empty strings when the deployment has no
/// bot configured, which is how the backend says "no Telegram sign-in here".
public struct BFFTelegramConfig: Decodable, Equatable, Sendable {
    public let botID: String
    public let botUsername: String

    public var isConfigured: Bool {
        !botUsername.trimmingCharacters(in: .whitespaces).isEmpty
    }

    enum CodingKeys: String, CodingKey {
        case botID = "bot_id"
        case botUsername = "bot_username"
    }
}

public struct BFFTelegramLoginStart: Decodable, Equatable, Sendable {
    public let state: String
    public let deepLink: String
    public let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case state
        case deepLink = "deep_link"
        case expiresIn = "expires_in"
    }
}

public enum BFFTelegramLoginStatus: String, Sendable {
    case pending
    case ready
    case expired
}

struct BFFTelegramLoginStatusResponse: Decodable, Sendable {
    let status: String
}

struct TelegramExchangeBody: Encodable, Sendable {
    let state: String
}

struct AppleAuthBody: Encodable, Sendable {
    let identityToken: String
    let firstName: String?
    let lastName: String?
    let inviteCode: String?

    /// Blank is normalised to absent here rather than at the call site, so no
    /// caller can send `""`. Apple hands the name only on the first consent;
    /// an empty string on a later sign-in would tell the server to replace a
    /// saved name with nothing.
    init(
        identityToken: String,
        firstName: String?,
        lastName: String?,
        inviteCode: String?
    ) {
        self.identityToken = identityToken
        self.firstName = Self.present(firstName)
        self.lastName = Self.present(lastName)
        self.inviteCode = Self.present(inviteCode)
    }

    private static func present(_ value: String?) -> String? {
        guard
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
            !trimmed.isEmpty
        else { return nil }
        return trimmed
    }

    enum CodingKeys: String, CodingKey {
        case identityToken = "identity_token"
        case firstName = "first_name"
        case lastName = "last_name"
        case inviteCode = "invite_code"
    }
}

private struct BFFTokenPair: Decodable, Sendable {
    let accessToken: String
    let refreshToken: String
    let username: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case username
    }
}

private struct BFFUser: Decodable, Sendable {
    let id: String
    let username: String
    let telegramFirstName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case telegramFirstName = "telegram_first_name"
    }
}

/// D-1514: единственное поле `/api/auth/me`, которое читает профиль.
struct BFFDisplayName: Decodable, Sendable {
    let displayName: String?

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
    }
}

public struct BFFHealth: Decodable, Equatable, Sendable {
    public let status: String

    public init(status: String) {
        self.status = status
    }
}

/// `DELETE /api/auth/me` — App Store Review 5.1.1(v): an account created in
/// the app has to be deletable from inside the app.
///
/// The backend frees the identity (login, Telegram and Apple keys) inside the
/// request and finishes the cascading purge of the account's rows in the
/// background, so `purge` may still say `pending` on a large account. Deletion
/// is already irreversible at that point. The call is idempotent: a retry after
/// a client timeout answers `already_deleted` with 200 rather than 404.
public struct BFFAccountDeletion: Decodable, Equatable, Sendable {
    public enum Status: String, Decodable, Sendable {
        case deleted
        case alreadyDeleted = "already_deleted"
    }

    public let status: Status
    public let userID: String
    public let username: String?
    public let purge: String?

    public init(
        status: Status,
        userID: String,
        username: String?,
        purge: String?
    ) {
        self.status = status
        self.userID = userID
        self.username = username
        self.purge = purge
    }

    enum CodingKeys: String, CodingKey {
        case status
        case userID = "user_id"
        case username
        case purge
    }
}

// MARK: - Chat models

public struct BFFRemoteChatInfo: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let createdAt: String
    public let updatedAt: String
    public let lastMessageAt: String?
    public let topic: String?
    public let isIncognito: Bool?
    public let isPinned: Bool?
    public let isStarred: Bool?

    /// The name to show for this chat.
    ///
    /// `title` is what the app itself writes — the first prompt when the chat
    /// is created, or whatever the user renamed it to — while `topic` is the
    /// backend's own classification of the conversation. A list of topics is
    /// not a list anyone can find their chat in, so the name wins and the
    /// topic only stands in when there is no name.
    ///
    /// This is also the field the offline-recovery markers are written into
    /// (`renameChat`), so reading `title` first is what lets them be found.
    public var displayTitle: String {
        for candidate in [title, topic] {
            guard
                let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
                !trimmed.isEmpty
            else { continue }
            return trimmed
        }
        return L("Новый чат")
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case lastMessageAt = "last_message_at"
        case topic
        case isIncognito = "is_incognito"
        case isPinned = "is_pinned"
        case isStarred = "is_starred"
    }
}

public enum BFFMessageRole: String, Codable, Sendable {
    case user
    case assistant
    case system
}

public struct BFFResponseSource: Codable, Equatable, Sendable {
    public let url: String?
    public let title: String?
    public let iconURL: String?
    public let avatarURL: String?

    enum CodingKeys: String, CodingKey {
        case url
        case title
        case iconURL = "icon_url"
        case avatarURL = "avatar_url"
    }
}

public enum BFFResponseFollowUp: Codable, Equatable, Sendable {
    case text(String)
    case item(id: String?, label: String?, text: String?)

    private enum CodingKeys: String, CodingKey {
        case id
        case label
        case text
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self = .text(value)
            return
        }

        let object = try decoder.container(keyedBy: CodingKeys.self)
        self = .item(
            id: try object.decodeIfPresent(String.self, forKey: .id),
            label: try object.decodeIfPresent(String.self, forKey: .label),
            text: try object.decodeIfPresent(String.self, forKey: .text)
        )
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .text(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .item(let id, let label, let text):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(id, forKey: .id)
            try container.encodeIfPresent(label, forKey: .label)
            try container.encodeIfPresent(text, forKey: .text)
        }
    }
}

public struct BFFRemoteAttachment: Codable, Equatable, Sendable {
    public let filename: String?
    public let mimeType: String?
    public let kind: String?
    public let fileID: String?
    public let thumbnailFileID: String?
    public let width: Double?
    public let height: Double?
    public let url: String?
    public let uri: String?
    public let downloadURL: String?
    public let toolName: String?
    public let uiHint: String?
    public let widgetData: BFFJSONValue?

    enum CodingKeys: String, CodingKey {
        case filename
        case mimeType = "mime_type"
        case kind
        case fileID = "file_id"
        case thumbnailFileID = "thumbnail_file_id"
        case width
        case height
        case url
        case uri
        case downloadURL = "download_url"
        case toolName = "tool_name"
        case uiHint = "ui_hint"
        case widgetData = "widget_data"
    }

}

// Кастомный `init(from:)` живёт в расширении, чтобы не потерять
// синтезированный memberwise-инициализатор (его используют тесты).
extension BFFRemoteAttachment {
    /// Поля сохранённой оплаты: она лежит в истории вложением без `ui_hint`
    /// и `widget_data` — `{payment_id, order_number, amount, description,
    /// status, form_url, source:"payment"}`. Раньше такое вложение
    /// декодировалось в пустую структуру, и карточка оплаты в открытом заново
    /// чате не появлялась (D-294).
    private enum PaymentKeys: String, CodingKey {
        case source
        case paymentID = "payment_id"
        case orderNumber = "order_number"
        case amount
        case description
        case status
        case formURL = "form_url"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        filename = try container.decodeIfPresent(String.self, forKey: .filename)
        mimeType = try container.decodeIfPresent(String.self, forKey: .mimeType)
        kind = try container.decodeIfPresent(String.self, forKey: .kind)
        fileID = try container.decodeIfPresent(String.self, forKey: .fileID)
        thumbnailFileID = try container.decodeIfPresent(String.self, forKey: .thumbnailFileID)
        width = try container.decodeIfPresent(Double.self, forKey: .width)
        height = try container.decodeIfPresent(Double.self, forKey: .height)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        uri = try container.decodeIfPresent(String.self, forKey: .uri)
        downloadURL = try container.decodeIfPresent(String.self, forKey: .downloadURL)
        toolName = try container.decodeIfPresent(String.self, forKey: .toolName)
        uiHint = try container.decodeIfPresent(String.self, forKey: .uiHint)
        let decodedWidgetData = try container.decodeIfPresent(BFFJSONValue.self, forKey: .widgetData)

        let payment = try decoder.container(keyedBy: PaymentKeys.self)
        let source = try payment.decodeIfPresent(String.self, forKey: .source)
        let paymentID = try payment.decodeIfPresent(String.self, forKey: .paymentID)
        let formURL = try payment.decodeIfPresent(String.self, forKey: .formURL)
        if decodedWidgetData == nil,
           source == "payment" || paymentID != nil || formURL != nil {
            var object: [String: BFFJSONValue] = ["source": .string(source ?? "payment")]
            if let paymentID { object["payment_id"] = .string(paymentID) }
            if let orderNumber = try payment.decodeIfPresent(String.self, forKey: .orderNumber) {
                object["order_number"] = .string(orderNumber)
            }
            if let amount = try? payment.decodeIfPresent(Double.self, forKey: .amount) {
                object["amount"] = .number(amount)
            } else if let amount = try? payment.decodeIfPresent(String.self, forKey: .amount) {
                object["amount"] = .string(amount)
            }
            if let description = try payment.decodeIfPresent(String.self, forKey: .description) {
                object["description"] = .string(description)
            }
            if let status = try payment.decodeIfPresent(String.self, forKey: .status) {
                object["status"] = .string(status)
            }
            if let formURL { object["form_url"] = .string(formURL) }
            widgetData = .object(object)
        } else {
            widgetData = decodedWidgetData
        }
    }
}

/// One fail-closed policy for image completion and runtime mapping. Backend
/// `file_id` values become authenticated BFF file URLs; explicit URLs must be
/// fetchable HTTP(S) URLs on the configured BFF origin. Only the documented
/// `/api/files/...` route may arrive as a relative URL.
enum BFFAttachmentURLPolicy {
    enum Classification: Equatable, Sendable {
        case image
        case file
    }

    /// Explicit transport kind wins. MIME is only a fallback for legacy
    /// payloads with a missing or unknown kind, so completion and mapping
    /// cannot disagree on a conflicting attachment.
    static func classification(
        for attachment: BFFRemoteAttachment
    ) -> Classification {
        switch attachment.kind {
        case BFFMessageMode.image.rawValue:
            return .image
        case ChatAttachmentKind.file.rawValue,
             ChatAttachmentKind.video.rawValue,
             ChatAttachmentKind.roundVideo.rawValue:
            return .file
        default:
            return attachment.mimeType?.hasPrefix("image/") == true
                ? .image
                : .file
        }
    }

    static func isUsableImageAttachment(
        _ attachment: BFFRemoteAttachment,
        baseURL: URL
    ) -> Bool {
        return classification(for: attachment) == .image
            && normalizedImageURL(for: attachment, baseURL: baseURL) != nil
    }

    static func normalizedImageURL(
        for attachment: BFFRemoteAttachment,
        baseURL: URL
    ) -> URL? {
        if attachment.fileID != nil {
            guard let fileID = normalizedFileID(attachment.fileID) else {
                return nil
            }
            let candidate = originRoot(for: baseURL)
                .appendingPathComponent("api")
                .appendingPathComponent("files")
                .appendingPathComponent(fileID)
            guard isAllowedAbsoluteURL(candidate, baseURL: baseURL) else {
                return nil
            }
            return candidate
        }

        for rawValue in [attachment.downloadURL, attachment.url, attachment.uri] {
            guard let rawValue else { continue }
            let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed == rawValue else { continue }
            guard let components = URLComponents(string: trimmed) else { continue }

            let candidate: URL?
            if components.scheme == nil {
                guard
                    components.host == nil,
                    trimmed.hasPrefix("/api/files/"),
                    !trimmed.hasPrefix("//"),
                    !containsTraversal(components.path)
                else { continue }
                candidate = URL(string: trimmed, relativeTo: originRoot(for: baseURL))?
                    .absoluteURL
            } else {
                candidate = components.url
            }

            guard
                let candidate,
                isAllowedAbsoluteURL(candidate, baseURL: baseURL)
            else { continue }
            return candidate
        }
        return nil
    }

    static func normalizedFileID(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !trimmed.isEmpty,
            trimmed == value,
            trimmed != ".",
            trimmed != "..",
            !trimmed.contains("/"),
            !trimmed.contains("?"),
            !trimmed.contains("#"),
            trimmed.rangeOfCharacter(from: .controlCharacters) == nil
        else { return nil }
        return trimmed
    }

    private static func originRoot(for url: URL) -> URL {
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.port = url.port
        components.path = "/"
        return components.url ?? url
    }

    private static func isAllowedAbsoluteURL(
        _ candidate: URL,
        baseURL: URL
    ) -> Bool {
        guard
            let scheme = candidate.scheme?.lowercased(),
            scheme == "https" || scheme == "http",
            candidate.user == nil,
            candidate.password == nil,
            candidate.fragment == nil,
            !containsTraversal(candidate.path),
            sameOrigin(candidate, baseURL)
        else { return false }
        return true
    }

    private static func sameOrigin(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.scheme?.lowercased() == rhs.scheme?.lowercased()
            && lhs.host?.lowercased() == rhs.host?.lowercased()
            && effectivePort(lhs) == effectivePort(rhs)
    }

    private static func effectivePort(_ url: URL) -> Int? {
        if let port = url.port { return port }
        switch url.scheme?.lowercased() {
        case "https": return 443
        case "http": return 80
        default: return nil
        }
    }

    private static func containsTraversal(_ path: String) -> Bool {
        path.split(separator: "/", omittingEmptySubsequences: true)
            .contains { $0 == "." || $0 == ".." }
    }
}

public struct BFFRemoteMessage: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let chatID: String
    public let role: BFFMessageRole
    public let content: String
    public let attachments: [BFFRemoteAttachment]?
    public let taskID: String?
    public let createdAt: String
    public let sources: [BFFResponseSource]?
    public let citations: [BFFResponseSource]?
    public let followUps: [BFFResponseFollowUp]?
    /// Ход задачи, записанный сервером. Прозрачный для транспорта список:
    /// внутри и текстовые шаги, и запись `{"type": "browser_run", …}` — по
    /// одной на прогон браузерного агента. Разбирает его `BFFChatService`,
    /// потому что состав записей — контракт продукта, а не транспорта.
    public var steps: [BFFJSONValue]? = nil

    enum CodingKeys: String, CodingKey {
        case id
        case chatID = "chat_id"
        case role
        case content
        case attachments
        case taskID = "task_id"
        case createdAt = "created_at"
        case sources
        case citations
        case followUps = "follow_ups"
        case steps
    }
}

public struct BFFRemoteChat: Equatable, Sendable {
    public let info: BFFRemoteChatInfo
    public let messages: [BFFRemoteMessage]

    public init(info: BFFRemoteChatInfo, messages: [BFFRemoteMessage]) {
        self.info = info
        self.messages = messages
    }
}

public struct BFFRemoteMediaFrame: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let chatID: String
    public let messageID: String
    public let taskID: String?
    public let prompt: String
    public let filename: String
    public let mimeType: String
    public let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case chatID = "chat_id"
        case messageID = "message_id"
        case taskID = "task_id"
        case prompt
        case filename
        case mimeType = "mime_type"
        case createdAt = "created_at"
    }
}

/// `AttachmentMeta` as exchanged with the backend.
///
/// `POST /api/uploads` answers with S3 keys, extracted document text and — for
/// video — thumbnail and frame keys, then `POST /api/messages` expects that same
/// object back so it can promote every key to a `File` row. The raw payload is
/// therefore kept verbatim rather than narrowed to the handful of fields the UI
/// itself reads.
public struct BFFUploadedAttachment: Codable, Equatable, Sendable {
    public let filename: String
    public let mimeType: String?
    public let kind: String
    public let s3Key: String?
    public let fileID: String?
    private let meta: [String: BFFJSONValue]

    /// Identifier for client-side bookkeeping. Freshly uploaded files only have
    /// an S3 key; `file_id` appears once the message round trip creates the row.
    public var reference: String {
        s3Key ?? fileID ?? filename
    }

    public init(
        filename: String,
        mimeType: String? = nil,
        kind: String,
        s3Key: String? = nil,
        fileID: String? = nil,
        meta: [String: BFFJSONValue] = [:]
    ) {
        self.filename = filename
        self.mimeType = mimeType
        self.kind = kind
        self.s3Key = s3Key
        self.fileID = fileID

        var payload = meta
        payload["filename"] = .string(filename)
        payload["kind"] = .string(kind)
        payload["mime_type"] = .string(mimeType ?? "application/octet-stream")
        if let s3Key {
            payload["s3_key"] = .string(s3Key)
        }
        if let fileID {
            payload["file_id"] = .string(fileID)
        }
        self.meta = payload
    }

    public init(from decoder: Decoder) throws {
        let payload = try [String: BFFJSONValue](from: decoder)
        guard let filename = Self.string(payload["filename"]) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Attachment payload without filename"
                )
            )
        }
        self.init(
            filename: filename,
            mimeType: Self.string(payload["mime_type"]),
            kind: Self.string(payload["kind"]) ?? "text",
            s3Key: Self.string(payload["s3_key"]),
            fileID: Self.string(payload["file_id"]),
            meta: payload
        )
    }

    public func encode(to encoder: Encoder) throws {
        try meta.encode(to: encoder)
    }

    private static func string(_ value: BFFJSONValue?) -> String? {
        guard case .string(let text) = value, !text.isEmpty else { return nil }
        return text
    }
}

public enum BFFMessageMode: String, Codable, Sendable {
    case chat
    case image
}

/// Effort level for a turn, as understood by `client-api`.
///
/// `light` also implies `no_decomposition` server-side; the client only has to
/// name the mode. Omitting the field leaves the backend on its own default.
public enum BFFExecutionMode: String, Codable, Sendable {
    case light
    case complex
}

public struct BFFSendMessageOptions: Equatable, Sendable {
    public var mode: BFFMessageMode
    public var ephemeral: Bool
    public var reasoning: Bool
    public var modelID: String?
    public var attachments: [BFFUploadedAttachment]
    public var executionMode: BFFExecutionMode?
    public var deviceCapabilities: [String]

    public init(
        mode: BFFMessageMode = .chat,
        ephemeral: Bool = false,
        reasoning: Bool = false,
        modelID: String? = nil,
        attachments: [BFFUploadedAttachment] = [],
        executionMode: BFFExecutionMode? = nil,
        deviceCapabilities: [String] = []
    ) {
        self.mode = mode
        self.ephemeral = ephemeral
        self.reasoning = reasoning
        self.modelID = modelID
        self.attachments = attachments
        self.executionMode = executionMode
        self.deviceCapabilities = deviceCapabilities
    }
}

public struct BFFOnlineModel: Equatable, Sendable {
    public let id: String
    public let name: String
    public let details: String?
    public let contextLength: Int?
    public let promptPrice: Double?
    public let completionPrice: Double?
}

public struct BFFQuota: Decodable, Equatable, Sendable {
    public let enabled: Bool
    public let requestsUsed: Int
    public let requestsLimit: Int
    public let tokensUsed: Int
    public let tokensLimit: Int
    public let hasOpenRouterKey: Bool
    /// D-1523: когда обнулится израсходованное (`QuotaResponse.period_ends_at`,
    /// client-api `routes/quota.py:44`). Строка ISO 8601; `nil` — расчётный
    /// период отключён или сервер старый.
    public let periodEndsAtRaw: String?

    /// Момент обновления лимита, если сервер его назвал.
    public var periodEndsAt: Date? {
        guard let value = periodEndsAtRaw else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        if let date = ISO8601DateFormatter().date(from: value) { return date }
        // Pydantic отдаёт наивный datetime без зоны — это UTC на сервере.
        let naive = ISO8601DateFormatter()
        naive.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime, .withDashSeparatorInDate]
        naive.timeZone = TimeZone(identifier: "UTC")
        return naive.date(from: String(value.prefix(19)))
    }

    enum CodingKeys: String, CodingKey {
        case enabled
        case requestsUsed = "requests_used"
        case requestsLimit = "requests_limit"
        case tokensUsed = "tokens_used"
        case tokensLimit = "tokens_limit"
        case hasOpenRouterKey = "has_openrouter_key"
        case periodEndsAtRaw = "period_ends_at"
    }
}

public struct BFFOpenRouterKeyValidation: Decodable, Equatable, Sendable {
    public let valid: Bool
    public let error: String?
}

public struct BFFSentMessage: Decodable, Equatable, Sendable {
    public let id: String
    public let chatID: String
    public let status: String

    enum CodingKeys: String, CodingKey {
        case id
        case chatID = "chat_id"
        case status
    }
}

public struct BFFCancellationResponse: Decodable, Equatable, Sendable {
    public let status: String
}

/// One task's status from `POST /api/tasks/status` (phase 89-01).
///
/// `BFFClient.decode` uses a bare `JSONDecoder()` with no key-decoding
/// strategy, so every snake_case wire name is mapped explicitly here. Implicit
/// conversion would silently fail to populate these fields.
public struct BFFTaskStatusItem: Decodable, Equatable, Sendable {
    public let taskID: String
    public let status: String
    public let isTerminal: Bool
    public let updatedAt: String?
    public let resultPreview: String?

    private enum CodingKeys: String, CodingKey {
        case taskID = "task_id"
        case status
        case isTerminal = "is_terminal"
        case updatedAt = "updated_at"
        case resultPreview = "result_preview"
    }
}

/// Only tasks that exist and belong to the caller. Anything else is absent.
public struct BFFTaskStatusBatch: Decodable, Equatable, Sendable {
    public let tasks: [BFFTaskStatusItem]

    public init(tasks: [BFFTaskStatusItem]) {
        self.tasks = tasks
    }
}

/// Result of `POST /api/tasks/{task_id}/cancel`.
public struct BFFTaskCancellation: Decodable, Equatable, Sendable {
    public let status: String
    public let taskID: String
    public let taskStatus: String

    private enum CodingKeys: String, CodingKey {
        case status
        case taskID = "task_id"
        case taskStatus = "task_status"
    }
}

/// Response of `POST /api/stt`.
public struct BFFTranscription: Decodable, Equatable, Sendable {
    public let text: String
}

/// Body of `POST /api/voice/live/session`: the phone's WebRTC offer.
public struct BFFLiveVoiceSessionRequest: Encodable, Equatable, Sendable {
    public let sdp: String
    public let language: String?
}

/// Response of `POST /api/voice/live/session`. The backend has already spent
/// the OpenAI key; what comes back is the answer to install and the session's
/// identity. Wire names are snake_case and mapped explicitly (see
/// `BFFTaskStatus`).
public struct BFFLiveVoiceSession: Decodable, Equatable, Sendable {
    public let sessionID: String
    public let sdp: String
    public let model: String
    public let voice: String

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case sdp
        case model
        case voice
    }
}

// MARK: - Agents, notifications, schedules

public struct BFFAgentSpec: Encodable, Sendable {
    public let name: String
    public let systemPrompt: String

    enum CodingKeys: String, CodingKey {
        case name
        case systemPrompt = "system_prompt"
    }
}

public struct BFFAgent: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let systemPrompt: String
    public let description: String
    public let emoji: String

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case systemPrompt = "system_prompt"
        case description
        case emoji
    }
}

public struct BFFNotification: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    public let chatID: String?
    public let type: String
    public let text: String
    public let read: Bool
    public let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case chatID = "chat_id"
        case type
        case text
        case read
        case createdAt = "created_at"
    }
}

struct BFFUnreadCount: Decodable, Sendable {
    let count: Int
}

/// `{"status": "ok"}` acknowledgement used by the user-info delete routes.
struct BFFStatusResponse: Decodable, Sendable {
    let status: String
}

/// Event in the account's own NIKA calendar, which the agent also writes to.
public struct BFFCalendarEvent: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let description: String?
    public let start: String
    public let end: String?
    public let location: String?
    public let allDay: Bool
    public let categoryID: String?
    public let sourceChatID: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case description
        case start
        case end
        case location
        case allDay = "all_day"
        case categoryID = "category_id"
        case sourceChatID = "source_chat_id"
    }
}

public struct BFFCalendarCategory: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let color: String
    public let emoji: String?
    public let builtin: Bool
}

/// A reminder or scheduled task created through the agent.
public struct BFFSchedule: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    public let chatID: String
    public let source: String
    public let kind: String
    public let text: String
    public let cronExpression: String?
    public let timeZoneIdentifier: String
    public let nextFireAt: String?
    public let lastFiredAt: String?
    public let active: Bool
    public let fireCount: Int
    public let metadata: [String: BFFJSONValue]
    public let createdAt: String?
    public let latestRunState: String
    public let latestRunAt: String?
    public let latestResult: String?
    public let latestError: String?

    enum CodingKeys: String, CodingKey {
        case id
        case chatID = "chat_id"
        case source
        case kind
        case text
        case cronExpression = "cron_expr"
        case timeZoneIdentifier = "timezone"
        case nextFireAt = "next_fire_at"
        case lastFiredAt = "last_fired_at"
        case active
        case fireCount = "fire_count"
        case metadata
        case createdAt = "created_at"
        case latestRunState = "latest_run_state"
        case latestRunAt = "latest_run_at"
        case latestResult = "latest_result"
        case latestError = "latest_error"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        chatID = try container.decode(String.self, forKey: .chatID)
        source = try container.decodeIfPresent(String.self, forKey: .source) ?? "schedule"
        if let decodedKind = try container.decodeIfPresent(String.self, forKey: .kind) {
            kind = decodedKind
        } else if source == "task" {
            // Older one-time reminder payloads predate the explicit kind field.
            // Recurring schedules do not get this fallback: losing their kind
            // would turn an errand into a reminder in Today and management.
            kind = "reminder"
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.kind,
                DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "Recurring schedules require a semantic kind."
                )
            )
        }
        text = try container.decode(String.self, forKey: .text)
        cronExpression = try container.decodeIfPresent(String.self, forKey: .cronExpression)
        timeZoneIdentifier = try container.decodeIfPresent(
            String.self,
            forKey: .timeZoneIdentifier
        ) ?? "UTC"
        nextFireAt = try container.decodeIfPresent(String.self, forKey: .nextFireAt)
        lastFiredAt = try container.decodeIfPresent(String.self, forKey: .lastFiredAt)
        active = try container.decodeIfPresent(Bool.self, forKey: .active) ?? true
        fireCount = try container.decodeIfPresent(Int.self, forKey: .fireCount) ?? 0
        metadata = try container.decodeIfPresent(
            [String: BFFJSONValue].self,
            forKey: .metadata
        ) ?? [:]
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        latestRunState = try container.decodeIfPresent(
            String.self,
            forKey: .latestRunState
        ) ?? (active ? "never_run" : "paused")
        latestRunAt = try container.decodeIfPresent(String.self, forKey: .latestRunAt)
        latestResult = try container.decodeIfPresent(String.self, forKey: .latestResult)
        latestError = try container.decodeIfPresent(String.self, forKey: .latestError)
    }
}

/// The direct schedule write deliberately contains no server-owned identity,
/// timezone, kind, chat id, or cron expression.
public struct BFFCreateScheduleRequest: Encodable, Equatable, Sendable {
    public let instruction: String
    public let cadence: String
    public let localTime: String
    public let weekday: Int?
    public let creationSource: String

    public init(draft: NIKAErrandDraft) throws {
        let validated = try draft.validated()
        instruction = validated.instruction
        cadence = validated.cadence.wireValue
        localTime = validated.localTime.wireValue
        weekday = validated.cadence.weekday
        creationSource = validated.creationSource.rawValue
    }

    enum CodingKeys: String, CodingKey {
        case instruction
        case cadence
        case localTime = "local_time"
        case weekday
        case creationSource = "creation_source"
    }
}

// MARK: - Skills catalogue

/// The deployed lightweight shape returned by the three read-only skills
/// collections. Extra execution and authoring fields deliberately stay out of
/// the phone's catalogue contract.
public struct BFFTaskScriptBrief: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    public let ownerID: String?
    public let visibility: String
    public let name: String
    public let description: String?
    public let generalizedQuery: String?
    /// D-1513: текст запроса у навыков системного каталога. `/api/skills/catalog`
    /// отдаёт `generalized_query = null` и кладёт запрос сюда (сид V179); веб
    /// читает его первым (`front-client/src/lib/agents.ts:1513`).
    public let promptTemplate: String?
    public let category: String?
    public let emoji: String?
    public let isSystem: Bool

    public init(
        id: String,
        ownerID: String?,
        visibility: String,
        name: String,
        description: String?,
        generalizedQuery: String?,
        promptTemplate: String? = nil,
        category: String?,
        emoji: String?,
        isSystem: Bool
    ) {
        self.id = id
        self.ownerID = ownerID
        self.visibility = visibility
        self.name = name
        self.description = description
        self.generalizedQuery = generalizedQuery
        self.promptTemplate = promptTemplate
        self.category = category
        self.emoji = emoji
        self.isSystem = isSystem
    }

    enum CodingKeys: String, CodingKey {
        case id
        case ownerID = "owner_id"
        case visibility
        case name
        case description
        case generalizedQuery = "generalized_query"
        case promptTemplate = "prompt_template"
        case category
        case emoji
        case isSystem = "is_system"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        ownerID = try container.decodeIfPresent(String.self, forKey: .ownerID)
        visibility = try container.decodeIfPresent(String.self, forKey: .visibility) ?? "private"
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        generalizedQuery = try container.decodeIfPresent(String.self, forKey: .generalizedQuery)
        promptTemplate = try? container.decodeIfPresent(String.self, forKey: .promptTemplate)
        category = try container.decodeIfPresent(String.self, forKey: .category)
        emoji = try container.decodeIfPresent(String.self, forKey: .emoji)
        isSystem = try container.decodeIfPresent(Bool.self, forKey: .isSystem) ?? false
    }
}

// MARK: - Personal news

public struct BFFPersonalNewsItem: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    public let source: String
    public let url: String?
    public let title: String
    public let body: String?
    public let publishedAt: String?
    public let fetchedAt: String
    public let tags: [String]
    public let score: Double?
    public let rationale: String?
    public let toastedAt: String?
    public let discussedChatID: String?

    public init(
        id: String,
        source: String,
        url: String?,
        title: String,
        body: String?,
        publishedAt: String?,
        fetchedAt: String,
        tags: [String],
        score: Double?,
        rationale: String?,
        toastedAt: String?,
        discussedChatID: String?
    ) {
        self.id = id
        self.source = source
        self.url = url
        self.title = title
        self.body = body
        self.publishedAt = publishedAt
        self.fetchedAt = fetchedAt
        self.tags = tags
        self.score = score
        self.rationale = rationale
        self.toastedAt = toastedAt
        self.discussedChatID = discussedChatID
    }

    enum CodingKeys: String, CodingKey {
        case id
        case source
        case url
        case title
        case body
        case publishedAt = "published_at"
        case fetchedAt = "fetched_at"
        case tags
        case score
        case rationale
        case toastedAt = "toasted_at"
        case discussedChatID = "discussed_chat_id"
    }
}

public struct BFFNewsDiscussResponse: Decodable, Equatable, Sendable {
    public let chatID: String
    public let messageID: String
    public let taskID: String

    enum CodingKeys: String, CodingKey {
        case chatID = "chat_id"
        case messageID = "message_id"
        case taskID = "task_id"
    }
}

// MARK: - Tool registry

/// One entry of `GET /api/tools/status`.
///
/// The live route (`client-api/app/routes/tools.py`) flattens the registry into
/// one object per *action*, keyed `name`/`source`/`available`/`description`/
/// `group`/`group_label`. Older deployments returned the raw registry object
/// instead (`slug`/`enabled`/`status`/`category`/`transport_type`), so both
/// shapes decode.
public struct BFFToolStatus: Decodable, Equatable, Sendable {
    public let name: String
    public let displayName: String
    public let description: String
    public let category: String
    public let transport: String
    public let isAvailable: Bool

    private enum CodingKeys: String, CodingKey {
        case name
        case slug
        case source
        case available
        case enabled
        case status
        case description
        case group
        case category
        case groupLabel = "group_label"
        case transportType = "transport_type"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let slug = try container.decodeIfPresent(String.self, forKey: .slug)
        let name = try container.decodeIfPresent(String.self, forKey: .name)
        guard let resolvedName = name ?? slug, !resolvedName.isEmpty else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Tool status without name or slug"
                )
            )
        }
        self.name = resolvedName
        self.description = try container
            .decodeIfPresent(String.self, forKey: .description) ?? ""
        self.category = try container.decodeIfPresent(String.self, forKey: .group)
            ?? container.decodeIfPresent(String.self, forKey: .category)
            ?? "other"
        self.transport = try container.decodeIfPresent(String.self, forKey: .source)
            ?? container.decodeIfPresent(String.self, forKey: .transportType)
            ?? "registry"

        // The flattened shape carries `group_label`; the raw registry object
        // carries the tool's own `name` while `slug` identifies it.
        let label = try container.decodeIfPresent(String.self, forKey: .groupLabel)
        if let label, !label.isEmpty {
            self.displayName = label
        } else if slug != nil, let name, !name.isEmpty {
            self.displayName = name
        } else {
            self.displayName = resolvedName
        }

        if let available = try container.decodeIfPresent(Bool.self, forKey: .available) {
            self.isAvailable = available
        } else {
            let enabled = try container
                .decodeIfPresent(Bool.self, forKey: .enabled) ?? false
            let status = try container
                .decodeIfPresent(String.self, forKey: .status) ?? "disabled"
            self.isAvailable = enabled && status != "disabled"
        }
    }

    public init(
        name: String,
        displayName: String,
        description: String,
        category: String,
        transport: String,
        isAvailable: Bool
    ) {
        self.name = name
        self.displayName = displayName
        self.description = description
        self.category = category
        self.transport = transport
        self.isAvailable = isAvailable
    }
}

// MARK: - Activity models

public struct BFFActivity: Decodable, Equatable, Sendable {
    public struct Day: Decodable, Equatable, Sendable {
        /// `yyyy-MM-dd` in the timezone offset the request asked for.
        public let date: String
        public let requests: Int
        public let tokens: Int

        enum CodingKeys: String, CodingKey {
            case date
            case requests
            case tokens
        }
    }

    public struct Hour: Decodable, Equatable, Sendable {
        public let hour: Int
        public let requests: Int
    }

    public struct Model: Decodable, Equatable, Sendable {
        public let modelName: String
        public let requests: Int
        public let tokens: Int

        enum CodingKeys: String, CodingKey {
            case modelName = "model_name"
            case requests
            case tokens
        }
    }

    public let days: [Day]
    public let hours: [Hour]
    public let models: [Model]
    public let totalRequests: Int
    public let totalTokens: Int

    enum CodingKeys: String, CodingKey {
        case days
        case hours
        case models
        case totalRequests = "total_requests"
        case totalTokens = "total_tokens"
    }
}

// MARK: - Browser agent

/// Шаг рана в снапшоте client-api. Список действий здесь — массив объектов
/// вида `{"click_element": {...}}`; наружу интересно только имя действия.
public struct BFFBrowserRunStep: Decodable, Equatable, Sendable {
    public let stepNumber: Int?
    public let thinking: String?
    public let evaluationPreviousGoal: String?
    public let memory: String?
    public let nextGoal: String?
    public let actions: [BFFJSONValue]?
    public let url: String?
    public let title: String?
    public let durationSeconds: Double?
    public let screenshotURL: String?

    private enum CodingKeys: String, CodingKey {
        case stepNumber = "step_number"
        case thinking
        case evaluationPreviousGoal = "evaluation_previous_goal"
        case memory
        case nextGoal = "next_goal"
        case actions
        case url
        case title
        case durationSeconds = "duration_seconds"
        case screenshotURL = "screenshot_url"
    }
}

public struct BFFBrowserRunSnapshot: Decodable, Equatable, Sendable {
    public let runID: String
    public let taskID: String?
    public let chatID: String?
    public let status: String?
    public let isAlive: Bool?
    public let finalResult: String?
    public let error: String?
    public let steps: [BFFBrowserRunStep]?

    private enum CodingKeys: String, CodingKey {
        case runID = "run_id"
        case taskID = "task_id"
        case chatID = "chat_id"
        case status
        case isAlive = "is_alive"
        case finalResult = "final_result"
        case error
        case steps
    }
}

// MARK: - WebSocket models

public enum BFFJSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: BFFJSONValue])
    case array([BFFJSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: BFFJSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([BFFJSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

public enum BFFWebSocketEventType: Equatable, Sendable {
    case token
    case status
    case done
    case error
    case cancelled
    case subtaskStatus
    case titleUpdated
    case topicUpdated
    case widget
    case toolStart
    case toolResult
    case file
    case payment
    /// Живой шаг браузерного агента: цель, адрес и ссылка на снимок экрана.
    case browserStep
    case deviceToolCall
    case unknown(String)

    fileprivate init(rawValue: String) {
        switch rawValue {
        case "token": self = .token
        case "status": self = .status
        case "done": self = .done
        case "error": self = .error
        case "cancelled": self = .cancelled
        case "subtask_status": self = .subtaskStatus
        case "title_updated": self = .titleUpdated
        case "topic_updated": self = .topicUpdated
        case "widget": self = .widget
        case "tool_start": self = .toolStart
        case "tool_result": self = .toolResult
        case "file": self = .file
        case "payment": self = .payment
        case "browser_step": self = .browserStep
        case "device_tool_call": self = .deviceToolCall
        default: self = .unknown(rawValue)
        }
    }
}

public struct BFFWebSocketEvent: Decodable, Equatable, Sendable {
    public let type: BFFWebSocketEventType
    public let data: String?
    public let taskID: String?
    public let currentStep: String?
    public let status: String?
    public let sources: [BFFResponseSource]?
    public let citations: [BFFResponseSource]?
    public let followUps: [BFFResponseFollowUp]?
    public let toolName: String?
    public let payload: BFFJSONValue?
    public let result: BFFJSONValue?
    public let uiHint: String?
    public let widgetData: BFFJSONValue?
    // browser_step. Шумные поля шага (thinking, memory) сюда намеренно не
    // едут — их отдаёт снапшот рана, см. `browserRun(runID:)`.
    public let runID: String?
    public let stepNumber: Int?
    public let nextGoal: String?
    public let stepAction: String?
    public let stepURL: String?
    public let stepTitle: String?
    public let evaluationPreviousGoal: String?
    public let durationSeconds: Double?
    /// Путь ручки client-api, а не адрес browser-agent. `nil` — снимка нет.
    public let screenshotURL: String?
    public let callID: String?
    public let arguments: [String: BFFJSONValue]?
    /// `true` на кадрах, которые сервер отдал из буфера при (пере)подключении.
    /// Подряд идущие `token` в буфере склеены в один кадр со всем текстом хода,
    /// поэтому по нему считают дельту, а не дописывают как есть.
    public let replay: Bool?
    // payment: client-api отдаёт платёж отдельным кадром без `ui_hint`.
    public let paymentID: String?
    public let orderNumber: String?
    public let amount: Double?
    public let paymentDescription: String?
    public let formURL: String?
    /// Весь кадр как есть — заполняется только у `.unknown` типов, которым
    /// объявленных полей не хватает. `nil` у всех известных кадров.
    public let rawFields: [String: BFFJSONValue]?

    public var statusText: String? {
        currentStep ?? data ?? status
    }

    public var isTerminal: Bool {
        type == .done || type == .error || type == .cancelled
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case data
        case taskID = "task_id"
        case currentStep = "current_step"
        case status
        case sources
        case citations
        case followUps = "follow_ups"
        case toolName = "tool_name"
        case payload
        case result
        case uiHint = "ui_hint"
        case widgetData = "widget_data"
        case runID = "run_id"
        case stepNumber = "step_number"
        case nextGoal = "next_goal"
        case stepAction = "action"
        case stepURL = "url"
        case stepTitle = "title"
        case evaluationPreviousGoal = "evaluation_previous_goal"
        case durationSeconds = "duration_seconds"
        case screenshotURL = "screenshot_url"
        case callID = "call_id"
        case arguments
        case replay
        case paymentID = "payment_id"
        case orderNumber = "order_number"
        case amount
        case paymentDescription = "description"
        case formURL = "form_url"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = BFFWebSocketEventType(
            rawValue: try container.decode(String.self, forKey: .type)
        )
        data = try container.decodeIfPresent(String.self, forKey: .data)
        taskID = try container.decodeIfPresent(String.self, forKey: .taskID)
        currentStep = try container.decodeIfPresent(String.self, forKey: .currentStep)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        sources = try container.decodeIfPresent([BFFResponseSource].self, forKey: .sources)
        citations = try container.decodeIfPresent([BFFResponseSource].self, forKey: .citations)
        followUps = try container.decodeIfPresent([BFFResponseFollowUp].self, forKey: .followUps)
        toolName = try container.decodeIfPresent(String.self, forKey: .toolName)
        payload = try container.decodeIfPresent(BFFJSONValue.self, forKey: .payload)
        result = try container.decodeIfPresent(BFFJSONValue.self, forKey: .result)
        uiHint = try container.decodeIfPresent(String.self, forKey: .uiHint)
        widgetData = try container.decodeIfPresent(BFFJSONValue.self, forKey: .widgetData)
        runID = try container.decodeIfPresent(String.self, forKey: .runID)
        stepNumber = try container.decodeIfPresent(Int.self, forKey: .stepNumber)
        nextGoal = try container.decodeIfPresent(String.self, forKey: .nextGoal)
        stepAction = try container.decodeIfPresent(String.self, forKey: .stepAction)
        stepURL = try container.decodeIfPresent(String.self, forKey: .stepURL)
        stepTitle = try container.decodeIfPresent(String.self, forKey: .stepTitle)
        evaluationPreviousGoal = try container.decodeIfPresent(
            String.self,
            forKey: .evaluationPreviousGoal
        )
        durationSeconds = try container.decodeIfPresent(Double.self, forKey: .durationSeconds)
        screenshotURL = try container.decodeIfPresent(String.self, forKey: .screenshotURL)
        callID = try container.decodeIfPresent(String.self, forKey: .callID)
        arguments = try container.decodeIfPresent(
            [String: BFFJSONValue].self,
            forKey: .arguments
        )
        replay = try container.decodeIfPresent(Bool.self, forKey: .replay)
        paymentID = try container.decodeIfPresent(String.self, forKey: .paymentID)
        orderNumber = try container.decodeIfPresent(String.self, forKey: .orderNumber)
        if let number = try? container.decodeIfPresent(Double.self, forKey: .amount) {
            amount = number
        } else if let text = try? container.decodeIfPresent(String.self, forKey: .amount) {
            amount = Double(text)
        } else {
            amount = nil
        }
        paymentDescription = try container.decodeIfPresent(String.self, forKey: .paymentDescription)
        formURL = try container.decodeIfPresent(String.self, forKey: .formURL)
        // Кадр, которого этот тип ещё не знает (например `browser_input_requested`,
        // BACKEND §1.7), сохраняется целиком: его поля не описаны `CodingKeys`, и
        // без этого они молча терялись бы. Разбор — у того, кто кадр понимает.
        // Только для `.unknown`: `token` идёт сотнями за ход, и лишний словарь на
        // каждый его кадр не нужен никому.
        if case .unknown = type {
            rawFields = try? [String: BFFJSONValue](from: decoder)
        } else {
            rawFields = nil
        }
    }
}

/// Открытый сокет чата: поток кадров и способ закрыть его явно.
///
/// Раньше `streamEvents` отдавал только поток, и если `POST /messages` после
/// него падал, сокет с читателем висели до закрытия сервером (D-290).
public struct BFFEventSubscription: Sendable {
    public let events: AsyncThrowingStream<BFFWebSocketEvent, Error>
    private let closeHandler: @Sendable () -> Void

    public init(
        events: AsyncThrowingStream<BFFWebSocketEvent, Error>,
        close: @escaping @Sendable () -> Void
    ) {
        self.events = events
        self.closeHandler = close
    }

    public func close() { closeHandler() }
}

public struct BFFDeviceToolCall: Decodable, Equatable, Sendable {
    public let id: String
    public let taskID: String
    public let chatID: String
    public let toolName: String
    public let arguments: [String: BFFJSONValue]

    private enum CodingKeys: String, CodingKey {
        case id
        case taskID = "task_id"
        case chatID = "chat_id"
        case toolName = "tool_name"
        case arguments
    }
}

public protocol BFFWebSocketTask: AnyObject, Sendable {
    func resume()
    func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?)
    func receive() async throws -> URLSessionWebSocketTask.Message
    /// Протокольный ping и ожидание pong (D-1958). Бросает, когда сокет мёртв.
    func keepAlivePing() async throws
}

extension BFFWebSocketTask {
    /// Тестовым и вспомогательным сокетам пинг не нужен.
    public func keepAlivePing() async throws {}
}

extension URLSessionWebSocketTask: BFFWebSocketTask {
    public func keepAlivePing() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sendPing { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}

/// Как часто клиент пингует сокет чата и сколько ждёт pong (D-1958).
///
/// Сессия сокета режет тишину по `timeoutIntervalForRequest` (60 с), а ход с
/// долгим рассуждением законно молчит дольше; пинг каждые 20 с держит сокет
/// живым и за один интервал ловит полуоткрытый после смены сети: без него
/// об этом узнавал только сторож тишины, спустя ≥15 с и REST-пробу.
public struct BFFSocketKeepAlive: Equatable, Sendable {
    public var interval: Duration
    public var pongTimeout: Duration

    public init(interval: Duration, pongTimeout: Duration) {
        self.interval = interval
        self.pongTimeout = pongTimeout
    }

    public static let standard = BFFSocketKeepAlive(
        interval: .seconds(20),
        pongTimeout: .seconds(10)
    )
}

// MARK: - Errors and reconciliation

public enum BFFClientError: Error, Sendable {
    case invalidBaseURL(String)
    case invalidResponse
    case encoding(String)
    case decoding(String)
    case timedOut
    case transport(String)
    case http(statusCode: Int, message: String)
    case invalidCredentials
    case userAlreadyExists
    case invalidSignupDetails
    case sessionExpired
    case chatHasPendingReminders
    case tooManyPinnedChats(String)
    case providerUnavailable(String)
    case reconciliationTimedOut(lastError: String?)
    /// The deployed collection only exposes mutable offset pagination. Once a
    /// scan needs more than one request it cannot prove absence or uniqueness
    /// without a backend snapshot/cursor, so ownership-changing callers stop.
    case chatCollectionSnapshotUnavailable
}

extension BFFClientError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return L("Некорректный адрес сервера.")
        case .invalidResponse:
            return L("Сервер вернул некорректный ответ.")
        case .encoding(let message):
            // Текст уже написан человеком (см. `encode`, `transcribe`): сырой
            // `localizedDescription` Foundation на экран не попадает (D-1961).
            return message
        case .decoding:
            // Подробности разбора (`keyNotFound…`, «The data couldn't be read…»)
            // остаются в журнале; человеку — одна строка (D-1961).
            return L("Сервер ответил в неожиданном формате. Попробуйте ещё раз.")
        case .timedOut:
            return L("Превышено время ожидания запроса.")
        case .transport:
            return L("Не удалось подключиться к серверу. Проверьте интернет и адрес backend.")
        case .http(let statusCode, let message):
            // Diagnostic, not prose: the status code and the server's own message.
            // Deliberately not localized so a support screenshot reads the same
            // whatever interface language the user picked.
            return "API \(statusCode): \(message)"
        case .invalidCredentials:
            return L("Неверный логин или пароль.")
        case .userAlreadyExists:
            return L("Пользователь с таким логином уже существует.")
        case .invalidSignupDetails:
            return L("Проверьте логин, пароль и инвайт-код.")
        case .sessionExpired:
            return L("Сессия истекла. Войдите снова.")
        case .chatHasPendingReminders:
            return L("В чате есть неотработавшие напоминания — удаление удалит и их. Отмените напоминания и попробуйте снова.")
        case .tooManyPinnedChats:
            return L("Закреплённых чатов уже максимум — открепите один и попробуйте снова.")
        case .providerUnavailable(let provider):
            return L("Вход через %@ сейчас недоступен. Попробуйте позже.", provider)
        case .reconciliationTimedOut:
            return L("Сервер не успел сохранить ответ в историю.")
        case .chatCollectionSnapshotUnavailable:
            return L("Не удалось безопасно проверить все разговоры. Повторите позже.")
        }
    }

    fileprivate var isTransientForReconciliation: Bool {
        switch self {
        case .timedOut, .transport:
            return true
        case .http(let statusCode, _):
            return statusCode >= 500
        default:
            return false
        }
    }
}

public struct BFFReconciliationPolicy: Equatable, Sendable {
    public var timeout: TimeInterval
    public var pollInterval: TimeInterval

    public init(timeout: TimeInterval = 120, pollInterval: TimeInterval = 2.5) {
        self.timeout = max(0, timeout)
        self.pollInterval = max(0.05, pollInterval)
    }
}

// MARK: - Client

public actor BFFClient {
    public typealias WebSocketTaskFactory =
        @Sendable (URLSession, URLRequest) -> any BFFWebSocketTask
    public typealias Sleep =
        @Sendable (_ seconds: TimeInterval) async throws -> Void
    public typealias Now = @Sendable () -> Date
    public typealias TokenUpdate = @Sendable (BFFAuthTokens?) -> Void

    public let baseURL: URL

    /// The owner-scoped batch status read refuses a longer list with 422, so the
    /// same bound is enforced here before a request is ever built.
    public static let maximumTaskStatusIDs = 50

    private let urlSession: URLSession
    /// Сокет живёт в своей сессии: в сессии REST лимит ресурса 120 с убивал
    /// любой сокет на второй минуте (D-1950).
    private let socketSession: URLSession
    /// Загрузка вложений: свой лимит ресурса, а не 120 с REST (D-1956).
    private let uploadSession: URLSession
    private let socketKeepAlive: BFFSocketKeepAlive
    private let requestTimeout: TimeInterval
    private let webSocketTaskFactory: WebSocketTaskFactory
    private let sleep: Sleep
    private let now: Now
    private let tokenUpdate: TokenUpdate
    private var tokens: BFFAuthTokens?
    /// A client created for an unauthenticated exchange stages credentials
    /// locally until AppSessionStore has durably committed their owner.
    private var tokenUpdatesEnabled: Bool
    private var refreshTask: Task<BFFTokenPair, Error>?

    public init(
        baseURL: String,
        urlSession: URLSession = .shared,
        requestTimeout: TimeInterval = 30,
        initialTokens: BFFAuthTokens? = nil,
        webSocketTaskFactory: @escaping WebSocketTaskFactory = {
            session,
            request in session.webSocketTask(with: request)
        },
        sleep: @escaping Sleep = { seconds in
            let nanoseconds = UInt64(min(max(seconds, 0), 86_400) * 1_000_000_000)
            try await Task.sleep(nanoseconds: nanoseconds)
        },
        now: @escaping Now = { Date() },
        tokenUpdate: @escaping TokenUpdate = { _ in },
        socketSession: URLSession? = nil,
        uploadSession: URLSession? = nil,
        socketKeepAlive: BFFSocketKeepAlive = .standard
    ) throws {
        self.baseURL = try Self.normalizedBaseURL(baseURL)
        self.urlSession = urlSession
        self.socketSession = socketSession ?? urlSession
        self.uploadSession = uploadSession ?? urlSession
        self.socketKeepAlive = socketKeepAlive
        self.requestTimeout = requestTimeout
        self.tokens = initialTokens
        self.tokenUpdatesEnabled = initialTokens != nil
        self.webSocketTaskFactory = webSocketTaskFactory
        self.sleep = sleep
        self.now = now
        self.tokenUpdate = tokenUpdate
    }

    public static func normalizedBaseURL(_ value: String) throws -> URL {
        var trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        if trimmed.hasSuffix("/api") {
            trimmed.removeLast(4)
        }
        if !trimmed.contains("://") {
            let host = trimmed
                .split(separator: "/", maxSplits: 1)
                .first?
                .lowercased() ?? ""
            let localHost = Self.isLocalHost(host)
            trimmed = "\(localHost ? "http" : "https")://\(trimmed)"
        }

        guard
            let url = URL(string: trimmed),
            let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https",
            let host = url.host,
            scheme == "https" || Self.isLocalHost(host)
        else {
            throw BFFClientError.invalidBaseURL(value)
        }
        return url
    }

    private static func isLocalHost(_ host: String) -> Bool {
        let normalized = host.lowercased()
        return normalized == "localhost"
            || normalized == "127.0.0.1"
            || normalized == "::1"
            || normalized.hasPrefix("10.")
            || normalized.hasPrefix("192.168.")
            || isPrivate172Host(normalized)
    }

    private static func isPrivate172Host(_ host: String) -> Bool {
        let components = host.split(separator: ".")
        guard
            components.count == 4,
            components[0] == "172",
            let secondOctet = Int(components[1])
        else {
            return false
        }
        return (16...31).contains(secondOctet)
    }

    public func configureTokens(_ newTokens: BFFAuthTokens?) {
        setTokens(newTokens)
    }

    public func currentTokens() -> BFFAuthTokens? {
        tokens
    }

    /// Called only after the authenticated session identity and its token pair
    /// have been committed together. Refresh/invalidation callbacks before
    /// this boundary remain staged inside the actor.
    func enableTokenUpdates() {
        tokenUpdatesEnabled = true
    }

    /// `client-api` exposes liveness at the root as `/healthz`; `/api/health`
    /// is kept as a fallback for deployments that front the service differently.
    public func health() async throws -> BFFHealth {
        do {
            return try await request(
                path: "/healthz",
                authentication: false,
                apiPrefix: false
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            do {
                return try await request(
                    path: "/health",
                    authentication: false
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Stands where the web app and the API share a host — the
                // production ones — answer `/healthz` with the SPA's HTML and
                // have no `/api/health` at all. Neither probe says anything
                // about the API there, so the last resort is a public API route
                // that must work for signing in to be possible at all.
                _ = try await telegramConfig()
                return BFFHealth(status: "ok")
            }
        }
    }

    public func login(email: String, password: String) async throws -> BFFAuthenticatedSession {
        let body = LoginBody(username: email, password: password)
        let pair: BFFTokenPair
        do {
            pair = try await request(
                path: "/auth/login",
                method: "POST",
                body: try encode(body),
                authentication: false
            )
        } catch BFFClientError.http(let statusCode, _) where statusCode == 401 {
            throw BFFClientError.invalidCredentials
        }

        return try await authenticatedSession(from: pair, fallbackUsername: email)
    }

    public func signup(
        email: String,
        password: String,
        inviteCode: String? = nil
    ) async throws -> BFFAuthenticatedSession {
        do {
            let _: BFFUser = try await request(
                path: "/auth/signup",
                method: "POST",
                body: try encode(
                    SignupBody(
                        username: email,
                        password: password,
                        inviteCode: inviteCode?
                            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    )
                ),
                authentication: false
            )
        } catch BFFClientError.http(let statusCode, _) where statusCode == 409 {
            throw BFFClientError.userAlreadyExists
        } catch BFFClientError.http(let statusCode, _) where statusCode == 422 {
            throw BFFClientError.invalidSignupDetails
        }

        return try await login(email: email, password: password)
    }

    /// Which Telegram bot this backend logs in through, if any.
    ///
    /// The web client asks the same question before it draws its Telegram
    /// button (`front-client/src/routes/login/+page.svelte`): the bot is a
    /// per-deployment setting, so the dev stand answers `oasis_dev_bot` and
    /// production answers its own. Nothing about it belongs in the app.
    public func telegramConfig() async throws -> BFFTelegramConfig {
        try await request(
            path: "/auth/telegram-config",
            authentication: false
        )
    }

    /// Starts the Telegram login handshake: the returned deep link opens the
    /// bot, and `state` is polled until the bot reports the resolved account.
    public func startTelegramLogin() async throws -> BFFTelegramLoginStart {
        do {
            return try await request(
                path: "/auth/telegram/login-state/start",
                method: "POST",
                authentication: false
            )
        } catch BFFClientError.http(let statusCode, _) where statusCode == 503 {
            throw BFFClientError.providerUnavailable("Telegram")
        }
    }

    public func telegramLoginStatus(
        state: String
    ) async throws -> BFFTelegramLoginStatus {
        let response: BFFTelegramLoginStatusResponse = try await request(
            path: "/auth/telegram/login-state",
            authentication: false,
            queryItems: [URLQueryItem(name: "state", value: state)]
        )
        return BFFTelegramLoginStatus(rawValue: response.status) ?? .expired
    }

    public func exchangeTelegramLogin(
        state: String
    ) async throws -> BFFAuthenticatedSession {
        let pair: BFFTokenPair = try await request(
            path: "/auth/telegram/login-state/exchange",
            method: "POST",
            body: try encode(TelegramExchangeBody(state: state)),
            authentication: false
        )
        return try await authenticatedSession(from: pair, fallbackUsername: "telegram")
    }

    /// Sign in with Apple — `POST /api/auth/apple` (App Store Review 4.8).
    ///
    /// Only the identity token travels: it is a JWT Apple signed, and the
    /// backend verifies it against Apple's published keys. `firstName` and
    /// `lastName` arrive from Apple **once**, on the first consent, and are
    /// forwarded exactly then — on later sign-ins they are legitimately nil,
    /// and the server must not overwrite a saved name with nothing.
    public func loginWithApple(
        identityToken: String,
        firstName: String?,
        lastName: String?,
        inviteCode: String? = nil
    ) async throws -> BFFAuthenticatedSession {
        let pair: BFFTokenPair
        do {
            pair = try await request(
                path: "/auth/apple",
                method: "POST",
                body: try encode(
                    AppleAuthBody(
                        identityToken: identityToken,
                        firstName: firstName,
                        lastName: lastName,
                        inviteCode: inviteCode
                    )
                ),
                authentication: false
            )
        } catch BFFClientError.http(let statusCode, _) where statusCode == 401 {
            throw BFFClientError.invalidCredentials
        } catch BFFClientError.http(let statusCode, _)
            where statusCode == 404 || statusCode == 500
            || statusCode == 502 || statusCode == 503 {
            // The deployment has the channel off or misconfigured. Neither is
            // «wrong password», and neither is the person's fault.
            throw BFFClientError.providerUnavailable("Apple")
        }

        return try await authenticatedSession(from: pair, fallbackUsername: "apple")
    }

    /// Delete this account and every row attached to it (5.1.1(v)).
    ///
    /// The purge is cascading and can outlive the request on a large account,
    /// so the timeout is deliberately far above the client's ordinary 30 s: a
    /// client-side abort does not stop the server, and a person who saw an
    /// error for a deletion that actually happened has no way back. The 401
    /// retry path is the ordinary one — the token is only destroyed after the
    /// server has answered.
    public func deleteMyAccount() async throws -> BFFAccountDeletion {
        try await request(
            path: "/auth/me",
            method: "DELETE",
            timeout: Self.accountDeletionTimeout
        )
    }

    /// Mirrors the web client's own budget for the same endpoint.
    static let accountDeletionTimeout: TimeInterval = 120

    /// Open a support ticket — `POST /api/feedback`.
    ///
    /// The deployed route is `multipart/form-data` with optional file parts.
    /// Reports from the app carry text only, so the body is assembled here
    /// rather than through the attachment writer used by uploads.
    public func submitFeedback(
        subject: String,
        body: String,
        contactEmail: String = "",
        isAnonymous: Bool = false
    ) async throws {
        let boundary = "nika-feedback-\(UUID().uuidString.lowercased())"
        var payload = Data()
        for (field, value) in [
            ("subject", subject),
            ("body", body),
            ("contact_email", contactEmail),
            ("is_anonymous", isAnonymous ? "true" : "false"),
        ] {
            payload.append(Self.multipartTextField(
                name: field,
                value: value,
                boundary: boundary
            ))
        }
        payload.append(Self.multipartFooterAfterField(boundary: boundary))

        let currentTokens = tokens
        var request = try makeRequest(
            path: "/feedback",
            method: "POST",
            body: payload,
            accessToken: currentTokens?.accessToken
        )
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )

        let response = try await Self.execute(request, using: urlSession)
        guard response.statusCode == 401, currentTokens?.refreshToken != nil else {
            try Self.validateSuccess(response)
            return
        }

        try await refreshIfStillCurrent(currentTokens)
        var retry = try makeRequest(
            path: "/feedback",
            method: "POST",
            body: payload,
            accessToken: tokens?.accessToken
        )
        retry.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )
        let retried = try await Self.execute(retry, using: urlSession)
        if retried.statusCode == 401 {
            setTokens(nil)
            throw BFFClientError.sessionExpired
        }
        try Self.validateSuccess(retried)
    }

    /// One `multipart/form-data` text field, closed with CRLF like every other
    /// part this client writes.
    static func multipartTextField(
        name: String,
        value: String,
        boundary: String
    ) -> Data {
        let safeName = name
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
        let lines = [
            "--\(boundary)",
            "Content-Disposition: form-data; name=\"\(safeName)\"",
            "",
            value,
        ]
        return Data(lines.map { $0 + "\r\n" }.joined().utf8)
    }

    /// The close-delimiter used when the last part already ended in CRLF.
    static func multipartFooterAfterField(boundary: String) -> Data {
        Data("--\(boundary)--\r\n".utf8)
    }

    /// One owner-scoped page from the deployed `/chats` collection.
    ///
    /// The backend silently caps `limit` at 200. Callers that need to make an
    /// absence/ownership decision must use `listAllChats()` instead of treating
    /// one page as the account's complete chat set.
    public func listChats(
        limit: Int = 200,
        offset: Int = 0
    ) async throws -> [BFFRemoteChatInfo] {
        try await request(
            path: "/chats",
            queryItems: [
                URLQueryItem(name: "incognito", value: "false"),
                URLQueryItem(name: "limit", value: String(min(max(limit, 1), 200))),
                URLQueryItem(name: "offset", value: String(max(offset, 0))),
            ]
        )
    }

    /// Reads the owner-scoped chat collection but authorizes a complete result
    /// only when it fits in one backend response.
    ///
    /// `/chats` is ordered by mutable timestamps and exposes only numeric
    /// offsets. Even if every HTTP request succeeds, a deletion/reorder between
    /// pages can skip a row. We still finish the bounded scan so diagnostics
    /// and deterministic transport tests exercise that schedule, but any scan
    /// that crossed an offset boundary fails closed instead of proving absence,
    /// uniqueness, creation permission, or terminal alias retirement.
    public func listAllChats(pageSize: Int = 200) async throws -> [BFFRemoteChatInfo] {
        let resolvedPageSize = min(max(pageSize, 1), 200)
        var offset = 0
        var result: [BFFRemoteChatInfo] = []
        var crossedMutableOffsetBoundary = false

        while true {
            let page = try await listChats(limit: resolvedPageSize, offset: offset)
            result.append(contentsOf: page)
            guard page.count == resolvedPageSize else {
                guard !crossedMutableOffsetBoundary else {
                    throw BFFClientError.chatCollectionSnapshotUnavailable
                }
                return result
            }
            crossedMutableOffsetBoundary = true
            offset += page.count
        }
    }

    /// Best-effort enumeration for the ordinary history surface.
    ///
    /// Unlike `listAllChats`, this result never authorizes absence, uniqueness,
    /// recovery creation, migration, or retirement. Mutable offset pagination
    /// can skip or repeat a row between requests, but that limitation must not
    /// make the entire drawer unavailable at the exact 200-row boundary. IDs
    /// are de-duplicated while preserving first-seen order.
    public func listChatsForDisplay(pageSize: Int = 200) async throws -> [BFFRemoteChatInfo] {
        let resolvedPageSize = min(max(pageSize, 1), 200)
        var offset = 0
        var orderedIDs: [String] = []
        var chatByID: [String: BFFRemoteChatInfo] = [:]

        while true {
            let page = try await listChats(limit: resolvedPageSize, offset: offset)
            for chat in page {
                if chatByID[chat.id] == nil {
                    orderedIDs.append(chat.id)
                }
                chatByID[chat.id] = chat
            }
            guard page.count == resolvedPageSize else {
                return orderedIDs.compactMap { chatByID[$0] }
            }
            offset += page.count
        }
    }

    /// Owner-scoped direct lookup used for hidden non-standard chats. Unlike
    /// the standard-history collection, this endpoint can resolve a scheduled
    /// errand conversation by its persisted id. Authentication, 404 and
    /// foreign-owner failures remain transport errors for the caller to show.
    public func fetchChatInfo(id chatID: String) async throws -> BFFRemoteChatInfo {
        try await request(path: "/chats/\(Self.pathComponent(chatID))")
    }

    public func listMediaFrames(
        limit: Int = 200,
        offset: Int = 0
    ) async throws -> [BFFRemoteMediaFrame] {
        try await request(
            path: "/media/frames",
            queryItems: [
                URLQueryItem(name: "limit", value: String(min(max(limit, 1), 200))),
                URLQueryItem(name: "offset", value: String(max(offset, 0))),
            ]
        )
    }

    /// Exact conversation-presence probe. Unlike `/chats`, this resource is
    /// keyed by one chat id and therefore gives reconciliation an authoritative
    /// 200 (exists) / 404 (deleted) boundary without pagination assumptions.
    public func chatExists(id chatID: String) async throws -> Bool {
        // `GET /chats/{id}` (client-api `get_chat` → `_get_user_chat`) отдаёт
        // 404 на чужой и мягко удалённый чат так же, как `/messages`, но весит
        // одну строку, а не всю переписку (D-1953). Тело не разбирается:
        // для «жив/удалён» важен только код.
        do {
            try await requestNoContent(
                path: "/chats/\(Self.pathComponent(chatID))",
                method: "GET"
            )
            return true
        } catch BFFClientError.http(let statusCode, _) where statusCode == 404 {
            return false
        }
    }

    public func createChat(
        title: String,
        ephemeral: Bool = false
    ) async throws -> BFFRemoteChatInfo {
        try await request(
            path: "/chats",
            method: "POST",
            body: try encode(
                CreateChatBody(
                    title: title,
                    isIncognito: ephemeral,
                    isCoaching: false,
                    noStore: ephemeral
                )
            )
        )
    }

    public func sendMessage(
        content: String,
        chatID: String,
        options: BFFSendMessageOptions = .init()
    ) async throws -> BFFSentMessage {
        try await request(
            path: "/messages",
            method: "POST",
            body: try encode(
                Self.sendMessageBody(
                    content: content,
                    chatID: chatID,
                    options: options
                )
            )
        )
    }

    public func pendingDeviceToolCalls(
        chatID: String,
        taskID: String
    ) async throws -> [BFFDeviceToolCall] {
        try await request(
            path: "/device-tool-calls/pending",
            queryItems: [
                URLQueryItem(name: "chat_id", value: chatID),
                URLQueryItem(name: "task_id", value: taskID),
            ]
        )
    }

    @discardableResult
    public func acknowledgeDeviceToolCall(_ callID: String) async throws -> BFFDeviceToolCall {
        try await request(
            path: "/device-tool-calls/\(Self.pathComponent(callID))/ack",
            method: "POST"
        )
    }

    @discardableResult
    public func completeDeviceToolCall(
        _ callID: String,
        result: [String: BFFJSONValue],
        isError: Bool
    ) async throws -> BFFDeviceToolCall {
        try await request(
            path: "/device-tool-calls/\(Self.pathComponent(callID))/result",
            method: "POST",
            body: try encode(DeviceToolResultBody(
                status: isError ? "failed" : "completed",
                result: result,
                error: isError ? Self.stringValue(result["error"]) : nil
            ))
        )
    }

    /// Request body for `POST /api/messages`, split out so the wire shape can be
    /// asserted without a live backend.
    static func sendMessageBody(
        content: String,
        chatID: String,
        options: BFFSendMessageOptions
    ) -> SendMessageBody {
        var value: [String: BFFJSONValue] = [:]
        if options.mode == .image || options.reasoning {
            if options.mode == .image {
                value["client_surface"] = .string("images")
                value["requested_output"] = .string("image")
                value["response_mode"] = .string("image_generation")
            }
            if options.reasoning {
                value["reasoning"] = .bool(true)
                value["think_harder"] = .bool(true)
            }
        }
        if !options.deviceCapabilities.isEmpty {
            value["device_capabilities"] = .array(
                options.deviceCapabilities.map(BFFJSONValue.string)
            )
        }
        let metadata = value.isEmpty ? nil : value

        return SendMessageBody(
            content: content,
            chatID: chatID,
            llmModel: options.modelID,
            attachments: options.attachments.isEmpty ? nil : options.attachments,
            reasoning: options.reasoning ? true : nil,
            noStore: options.ephemeral ? true : nil,
            isIncognito: options.ephemeral ? true : nil,
            executionMode: options.executionMode,
            extraTaskMetadata: metadata
        )
    }

    private static func stringValue(_ value: BFFJSONValue?) -> String? {
        guard case .string(let text) = value else { return nil }
        return text
    }

    public func listOnlineModels() async throws -> [BFFOnlineModel] {
        guard let url = URL(string: "https://openrouter.ai/api/v1/models") else {
            throw BFFClientError.invalidResponse
        }
        var request = URLRequest(url: url, timeoutInterval: requestTimeout)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("NIKA iOS", forHTTPHeaderField: "X-Title")

        let response = try await Self.execute(request, using: urlSession)
        let catalog = try Self.decode(OpenRouterModelsResponse.self, from: response)
        return catalog.data.map { model in
            BFFOnlineModel(
                id: model.id,
                name: model.name,
                details: model.description,
                contextLength: model.contextLength,
                promptPrice: model.pricing?.prompt.flatMap(Double.init),
                completionPrice: model.pricing?.completion.flatMap(Double.init)
            )
        }
    }

    public func quota() async throws -> BFFQuota {
        try await request(path: "/quota")
    }

    /// Снапшот браузерного рана.
    ///
    /// Живой поток даёт только шаги, случившиеся при подключённом сокете, и
    /// без разбора (`thinking`/`memory`). Панель наблюдения, открытая после
    /// возврата в чат, берёт остальное отсюда. 404 — ран уже не известен
    /// серверу; это не отказ, лента остаётся на том, что пришло потоком.
    public func browserRun(runID: String) async throws -> BFFBrowserRunSnapshot? {
        do {
            return try await request(
                path: "/browser-runs/\(Self.pathComponent(runID))"
            )
        } catch BFFClientError.http(let statusCode, _) where statusCode == 404 {
            return nil
        }
    }

    public func setOpenRouterKey(
        _ key: String
    ) async throws -> BFFOpenRouterKeyValidation {
        try await request(
            path: "/quota/openrouter-key",
            method: "POST",
            body: try encode(OpenRouterKeyBody(apiKey: key))
        )
    }

    public func deleteOpenRouterKey() async throws {
        try await requestNoContent(
            path: "/quota/openrouter-key",
            method: "DELETE"
        )
    }

    // MARK: - Agents

    public func fetchAgents() async throws -> [BFFAgent] {
        try await request(path: "/agents")
    }

    public func createAgent(
        name: String,
        systemPrompt: String
    ) async throws -> BFFAgent {
        try await request(
            path: "/agents",
            method: "POST",
            body: try encode(
                BFFAgentSpec(name: name, systemPrompt: systemPrompt)
            )
        )
    }

    @discardableResult
    public func updateAgent(
        id agentID: String,
        name: String,
        systemPrompt: String
    ) async throws -> BFFAgent {
        try await request(
            path: "/agents/\(Self.pathComponent(agentID))",
            method: "PUT",
            body: try encode(
                BFFAgentSpec(name: name, systemPrompt: systemPrompt)
            )
        )
    }

    public func deleteAgent(id agentID: String) async throws {
        try await requestNoContent(
            path: "/agents/\(Self.pathComponent(agentID))",
            method: "DELETE"
        )
    }

    // MARK: - Tool registry

    /// Cloud tool catalog proxied from the external Tool Registry.
    ///
    /// Caller beware: the backend answers `200 []` both when
    /// `_TOOL_REGISTRY_URL` is unset and when the registry call failed — the
    /// error is swallowed into a log line. An empty result therefore means
    /// "no answer", not "no tools".
    public func toolsStatus() async throws -> [BFFToolStatus] {
        try await request(path: "/tools/status")
    }

    // MARK: - Notifications

    public func fetchNotifications(limit: Int = 50) async throws -> [BFFNotification] {
        try await request(
            path: "/notifications",
            queryItems: [URLQueryItem(name: "limit", value: String(limit))]
        )
    }

    public func fetchOwnSkills(limit: Int = 100, offset: Int = 0) async throws
        -> [BFFTaskScriptBrief]
    {
        try await request(
            path: "/skills",
            queryItems: Self.skillsPageQuery(limit: min(max(limit, 1), 100), offset: offset)
        )
    }

    public func fetchCatalogueSkills(limit: Int = 500, offset: Int = 0) async throws
        -> [BFFTaskScriptBrief]
    {
        try await request(
            path: "/skills/catalog",
            queryItems: Self.skillsPageQuery(limit: min(max(limit, 1), 500), offset: offset)
        )
    }

    public func fetchPublicSkills(limit: Int = 100, offset: Int = 0) async throws
        -> [BFFTaskScriptBrief]
    {
        try await request(
            path: "/skills/public",
            queryItems: Self.skillsPageQuery(limit: min(max(limit, 1), 100), offset: offset)
        )
    }

    private nonisolated static func skillsPageQuery(limit: Int, offset: Int) -> [URLQueryItem] {
        [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(max(offset, 0))),
        ]
    }

    // MARK: - Personal news

    public func fetchPersonalNews(
        limit: Int = 50,
        offset: Int = 0,
        minimumScore: Double = 0.7
    ) async throws -> [BFFPersonalNewsItem] {
        try await request(
            path: "/news",
            queryItems: [
                URLQueryItem(name: "limit", value: String(min(max(limit, 1), 200))),
                URLQueryItem(name: "offset", value: String(max(offset, 0))),
                URLQueryItem(name: "min_score", value: String(minimumScore)),
                URLQueryItem(name: "sort", value: "relevance"),
                URLQueryItem(name: "period", value: "day"),
            ]
        )
    }

    public func markNewsSurfaced(id newsID: String) async throws {
        try await requestNoContent(
            path: "/news/\(Self.pathComponent(newsID))/mark-toasted",
            method: "POST"
        )
    }

    public func discussNews(id newsID: String) async throws -> BFFNewsDiscussResponse {
        try await request(
            path: "/news/\(Self.pathComponent(newsID))/discuss",
            method: "POST"
        )
    }

    public func unreadNotificationCount() async throws -> Int {
        let response: BFFUnreadCount = try await request(
            path: "/notifications/unread-count"
        )
        return response.count
    }

    public func markNotificationRead(id notificationID: String) async throws {
        try await requestNoContent(
            path: "/notifications/\(Self.pathComponent(notificationID))/read",
            method: "PATCH"
        )
    }

    // MARK: - Schedules

    /// Reminders and scheduled tasks the agent created for the user.
    public func fetchSchedules(activeOnly: Bool = true) async throws -> [BFFSchedule] {
        try await request(
            path: "/schedules",
            queryItems: [
                URLQueryItem(
                    name: "active_only",
                    value: activeOnly ? "true" : "false"
                )
            ]
        )
    }

    /// Creates a recurring NIKA errand through the narrow authenticated API.
    /// Stable validation details become field-aware domain errors; every
    /// other BFF error keeps its existing identity for session/network UI.
    public func createSchedule(
        _ createRequest: BFFCreateScheduleRequest
    ) async throws -> BFFSchedule {
        do {
            return try await request(
                path: "/schedules",
                method: "POST",
                body: try encode(createRequest)
            )
        } catch BFFClientError.http(let statusCode, let message) where statusCode == 422 {
            guard let validation = NIKAErrandValidationError(serverMessage: message) else {
                throw BFFClientError.http(statusCode: statusCode, message: message)
            }
            throw validation
        }
    }

    public func deactivateSchedule(id scheduleID: String) async throws {
        try await requestNoContent(
            path: "/schedules/\(Self.pathComponent(scheduleID))/deactivate",
            method: "PATCH"
        )
    }

    public func activateSchedule(id scheduleID: String) async throws {
        try await requestNoContent(
            path: "/schedules/\(Self.pathComponent(scheduleID))/activate",
            method: "PATCH"
        )
    }

    public func deleteSchedule(id scheduleID: String) async throws {
        try await requestNoContent(
            path: "/schedules/\(Self.pathComponent(scheduleID))",
            method: "DELETE"
        )
    }

    /// Usage history aggregated server-side from `request_metrics`. Covers only
    /// requests that reached the backend — on-device model runs are counted
    /// locally.
    public func fetchActivity(
        days: Int = 90,
        tzOffsetMinutes: Int
    ) async throws -> BFFActivity {
        try await request(
            path: "/metrics/activity",
            queryItems: [
                URLQueryItem(name: "days", value: String(days)),
                URLQueryItem(
                    name: "tz_offset_minutes",
                    value: String(tzOffsetMinutes)
                ),
            ]
        )
    }

    // MARK: - User info

    /// The whole `user_info` document: the buckets the agent maintains itself
    /// (`new_facts`, `insights`, …) alongside the `memories` and `goals` the app
    /// owns.
    /// D-1514: имя человека словом сервера — `display_name` из `GET /api/auth/me`.
    /// Сервер собирает его сам (`client-api/app/user_name.py:compute_display_name`:
    /// имя из памяти разговора, потом имя провайдера входа, потом логин) — тем
    /// же правилом, что веб. Пустое имя — `nil`.
    public func fetchDisplayName() async throws -> String? {
        let me: BFFDisplayName = try await request(path: "/auth/me")
        let trimmed = me.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    public func fetchUserInfo() async throws -> [String: BFFJSONValue] {
        try await request(path: "/user-info")
    }

    /// Writes only the buckets present in `payload` — the backend leaves every
    /// omitted key untouched, so the app never clobbers agent-authored memory.
    @discardableResult
    public func updateUserInfo(
        _ payload: [String: BFFJSONValue]
    ) async throws -> [String: BFFJSONValue] {
        try await request(
            path: "/user-info",
            method: "PUT",
            body: try encode(payload)
        )
    }

    // MARK: Goals (aspirations)

    /// The backend assigns the aspiration id, so the created object is returned
    /// for the caller to adopt.
    public func createAspiration(
        _ payload: [String: BFFJSONValue]
    ) async throws -> [String: BFFJSONValue] {
        try await request(
            path: "/user-info/aspiration",
            method: "POST",
            body: try encode(payload)
        )
    }

    @discardableResult
    public func updateAspiration(
        id: String,
        _ payload: [String: BFFJSONValue]
    ) async throws -> [String: BFFJSONValue] {
        try await request(
            path: "/user-info/aspiration/\(id)",
            method: "PATCH",
            body: try encode(payload)
        )
    }

    public func deleteAspiration(id: String) async throws {
        let _: BFFStatusResponse = try await request(
            path: "/user-info/aspiration/\(id)",
            method: "DELETE"
        )
    }

    public func createMilestone(
        aspirationID: String,
        _ payload: [String: BFFJSONValue]
    ) async throws -> [String: BFFJSONValue] {
        try await request(
            path: "/user-info/aspiration/\(aspirationID)/milestone",
            method: "POST",
            body: try encode(payload)
        )
    }

    @discardableResult
    public func updateMilestone(
        aspirationID: String,
        id: String,
        _ payload: [String: BFFJSONValue]
    ) async throws -> [String: BFFJSONValue] {
        try await request(
            path: "/user-info/aspiration/\(aspirationID)/milestone/\(id)",
            method: "PATCH",
            body: try encode(payload)
        )
    }

    public func deleteMilestone(aspirationID: String, id: String) async throws {
        let _: BFFStatusResponse = try await request(
            path: "/user-info/aspiration/\(aspirationID)/milestone/\(id)",
            method: "DELETE"
        )
    }

    // MARK: Calendar

    /// `from`/`to` filter on the event start, matching the backend.
    public func fetchCalendarEvents(
        from: Date,
        to: Date,
        limit: Int = 200
    ) async throws -> [BFFCalendarEvent] {
        let formatter = ISO8601DateFormatter()
        return try await request(
            path: "/calendar/events",
            queryItems: [
                URLQueryItem(name: "from", value: formatter.string(from: from)),
                URLQueryItem(name: "to", value: formatter.string(from: to)),
                URLQueryItem(name: "limit", value: String(limit)),
            ]
        )
    }

    public func fetchCalendarCategories() async throws -> [BFFCalendarCategory] {
        try await request(path: "/calendar/categories")
    }

    public func createCalendarEvent(
        title: String,
        start: Date,
        end: Date?,
        allDay: Bool,
        notes: String?,
        categoryID: String?
    ) async throws -> BFFCalendarEvent {
        let formatter = ISO8601DateFormatter()
        var payload: [String: BFFJSONValue] = [
            "title": .string(title),
            "start": .string(formatter.string(from: start)),
            "all_day": .bool(allDay),
        ]
        if let end {
            payload["end"] = .string(formatter.string(from: end))
        }
        if let notes, !notes.isEmpty {
            payload["description"] = .string(notes)
        }
        if let categoryID {
            payload["category_id"] = .string(categoryID)
        }
        return try await request(
            path: "/calendar/events",
            method: "POST",
            body: try encode(payload)
        )
    }

    public func deleteCalendarEvent(id: String) async throws {
        try await requestNoContent(
            path: "/calendar/events/\(id)",
            method: "DELETE"
        )
    }

    /// Uploads a single file to `POST /api/uploads`. The backend derives the
    /// attachment kind from the extension, so it is not part of the request.
    public func uploadAttachment(
        data: Data,
        filename: String,
        mimeType: String
    ) async throws -> BFFUploadedAttachment {
        let boundary = "nika-\(UUID().uuidString.lowercased())"
        let bodyFileURL = try Self.multipartFile(
            data: data,
            filename: filename,
            mimeType: mimeType,
            boundary: boundary
        )
        defer {
            try? FileManager.default.removeItem(at: bodyFileURL)
        }

        var request = try makeUploadRequest(
            boundary: boundary,
            accessToken: tokens?.accessToken
        )
        var response = try await Self.executeUpload(
            request,
            fromFile: bodyFileURL,
            using: uploadSession,
            retryDelay: sleep
        )
        if response.statusCode == 401 {
            try await refreshOrExpire()
            request = try makeUploadRequest(
                boundary: boundary,
                accessToken: tokens?.accessToken
            )
            response = try await Self.executeUpload(
                request,
                fromFile: bodyFileURL,
                using: uploadSession,
                retryDelay: sleep
            )
        }

        let uploaded = try Self.decode([BFFUploadedAttachment].self, from: response)
        guard let first = uploaded.first else {
            throw BFFClientError.decoding("upload: сервер не вернул метаданные вложения")
        }
        return first
    }

    /// Server-side speech recognition — `POST /api/stt` (Whisper).
    ///
    /// Optional path for voice mode: the phone always recognizes locally for
    /// endpointing and as a fallback, and only uploads the recording when the
    /// user opted into server recognition.
    public func transcribe(
        audio: Data,
        filename: String = "recording.wav",
        mimeType: String = "audio/wav",
        language: String = "ru"
    ) async throws -> String {
        guard !audio.isEmpty else {
            throw BFFClientError.encoding(L("Пустая аудиозапись."))
        }
        let boundary = "nika-\(UUID().uuidString.lowercased())"
        let body = Self.multipartBody(
            data: audio,
            fieldName: "file",
            filename: filename,
            mimeType: mimeType,
            boundary: boundary
        )

        var request = try makeMultipartRequest(
            path: "/stt",
            boundary: boundary,
            queryItems: [URLQueryItem(name: "language", value: language)],
            accessToken: tokens?.accessToken
        )
        request.httpBody = body
        var response = try await Self.execute(request, using: urlSession)
        if response.statusCode == 401, tokens?.refreshToken != nil {
            try await refreshOrExpire()
            request = try makeMultipartRequest(
                path: "/stt",
                boundary: boundary,
                queryItems: [URLQueryItem(name: "language", value: language)],
                accessToken: tokens?.accessToken
            )
            request.httpBody = body
            response = try await Self.execute(request, using: urlSession)
        }

        let decoded = try Self.decode(BFFTranscription.self, from: response)
        return decoded.text
    }

    /// `POST /api/voice/live/session` — exchanges a WebRTC offer for OpenAI's
    /// answer. One round-trip; audio and events then bypass the backend.
    ///
    /// Generous timeout: the backend itself waits on OpenAI, and a slow answer
    /// beats a retry that opens a second billable session.
    public func createLiveVoiceSession(
        sdp: String,
        language: String? = nil
    ) async throws -> BFFLiveVoiceSession {
        guard !sdp.isEmpty else {
            throw BFFClientError.encoding(L("Пустое голосовое предложение."))
        }
        let body = try encode(BFFLiveVoiceSessionRequest(sdp: sdp, language: language))
        return try await request(
            path: "/voice/live/session",
            method: "POST",
            body: body,
            timeout: 45
        )
    }

    public func cancelChat(id chatID: String) async throws -> BFFCancellationResponse {
        try await request(
            path: "/chats/\(Self.pathComponent(chatID))/cancel",
            method: "POST"
        )
    }

    /// Owner-scoped batch read of task status.
    ///
    /// Only the first `maximumTaskStatusIDs` ids are sent: an over-long list is
    /// refused wholesale by the backend, and denying the owner the forty-nine
    /// ids that would have answered is worse than truncating the ask.
    public func taskStatuses(ids: [String]) async throws -> BFFTaskStatusBatch {
        let bounded = Array(ids.prefix(Self.maximumTaskStatusIDs))
        guard !bounded.isEmpty else { return BFFTaskStatusBatch(tasks: []) }
        return try await request(
            path: "/tasks/status",
            method: "POST",
            body: try encode(["task_ids": bounded])
        )
    }

    /// Stops exactly one task tree. The chat-level cancel is deliberately not
    /// reused: it selects the newest alive tree and would kill a newer request
    /// the owner is still watching.
    public func cancelTask(id taskID: String) async throws -> BFFTaskCancellation {
        try await request(
            path: "/tasks/\(Self.pathComponent(taskID))/cancel",
            method: "POST"
        )
    }

    /// Deletes the conversation server-side.
    ///
    /// The backend answers 409 while the chat still owns reminders that have not
    /// fired, since `tasks.chat_id` cascades and the deletion would take them
    /// down with it.
    public func deleteChat(id chatID: String) async throws {
        do {
            try await requestNoContent(
                path: "/chats/\(Self.pathComponent(chatID))",
                method: "DELETE"
            )
        } catch BFFClientError.http(let statusCode, _) where statusCode == 404 {
            // DELETE is idempotent for the privacy control. A retry after a
            // response was lost must converge to "deleted", not get stuck in
            // a false failure state because the first request already won.
            return
        } catch BFFClientError.http(let statusCode, _) where statusCode == 409 {
            throw BFFClientError.chatHasPendingReminders
        }
    }

    /// The backend caps pinned chats, answering 422 once the limit is reached.
    @discardableResult
    public func setChatPinned(
        id chatID: String,
        isPinned: Bool
    ) async throws -> BFFRemoteChatInfo {
        do {
            return try await request(
                path: "/chats/\(Self.pathComponent(chatID))/pin",
                method: "PATCH",
                body: try encode(["is_pinned": BFFJSONValue.bool(isPinned)])
            )
        } catch BFFClientError.http(let statusCode, let message) where statusCode == 422 {
            throw BFFClientError.tooManyPinnedChats(message)
        }
    }

    @discardableResult
    public func setChatStarred(
        id chatID: String,
        isStarred: Bool
    ) async throws -> BFFRemoteChatInfo {
        try await request(
            path: "/chats/\(Self.pathComponent(chatID))/star",
            method: "PATCH",
            body: try encode(["is_starred": BFFJSONValue.bool(isStarred)])
        )
    }

    @discardableResult
    public func renameChat(
        id chatID: String,
        title: String
    ) async throws -> BFFRemoteChatInfo {
        try await request(
            path: "/chats/\(Self.pathComponent(chatID))",
            method: "PATCH",
            body: try encode(
                CreateChatBody(
                    title: title,
                    isIncognito: false,
                    isCoaching: false,
                    noStore: false
                )
            )
        )
    }

    /// Empties the conversation without deleting it.
    public func clearChatMessages(id chatID: String) async throws {
        try await requestNoContent(
            path: "/chats/\(Self.pathComponent(chatID))/messages",
            method: "DELETE"
        )
    }

    /// Deletes one message. `keepChatIfEmpty: false` lets the backend drop a
    /// conversation that just lost its last message.
    public func deleteMessage(
        id messageID: String,
        keepChatIfEmpty: Bool = true
    ) async throws {
        try await requestNoContent(
            path: "/messages/\(Self.pathComponent(messageID))",
            method: "DELETE",
            queryItems: [
                URLQueryItem(
                    name: "keep_chat_if_empty",
                    value: keepChatIfEmpty ? "true" : "false"
                )
            ]
        )
    }

    public func fetchChat(_ info: BFFRemoteChatInfo) async throws -> BFFRemoteChat {
        let messages: [BFFRemoteMessage] = try await request(
            path: "/chats/\(Self.pathComponent(info.id))/messages"
        )
        return BFFRemoteChat(info: info, messages: Self.orderByTurn(messages))
    }

    /// Polls REST history after a missed/closed WebSocket until the last matching
    /// user turn has a non-empty assistant response, mirroring the v2 client.
    public func reconcileChat(
        _ info: BFFRemoteChatInfo,
        userContent: String,
        serverContent: String? = nil,
        taskID: String? = nil,
        mode: BFFMessageMode = .chat,
        policy: BFFReconciliationPolicy = .init()
    ) async throws -> BFFRemoteChat {
        let acceptedUserContent = Set(
            [userContent, serverContent]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        )
        let deadline = now().addingTimeInterval(policy.timeout)
        var lastTransientError: BFFClientError?

        var attempt = 0
        repeat {
            do {
                let candidate = try await fetchChat(info)
                attempt += 1
                ChatDiagnostics.reconcile(
                    attempt: attempt,
                    tail: candidate.messages.suffix(3).map {
                        (
                            role: $0.role.rawValue,
                            taskID: $0.taskID,
                            chars: $0.content.trimmingCharacters(in: .whitespacesAndNewlines).count,
                            files: $0.attachments?.count ?? 0
                        )
                    }
                )
                if Self.hasCompletedAnswer(
                    in: candidate.messages,
                    acceptedUserContent: acceptedUserContent,
                    taskID: taskID,
                    mode: mode,
                    baseURL: baseURL
                ) {
                    return candidate
                }
                lastTransientError = nil
            } catch let error as BFFClientError where error.isTransientForReconciliation {
                lastTransientError = error
            }

            if now() >= deadline {
                break
            }
            try await sleep(policy.pollInterval)
        } while !Task.isCancelled

        try Task.checkCancellation()
        throw BFFClientError.reconciliationTimedOut(
            lastError: lastTransientError?.localizedDescription
        )
    }

    /// Open this stream before `sendMessage`; then filter frames by the returned
    /// `BFFSentMessage.id`, because a chat socket can carry concurrent tasks.
    public func streamEvents(
        chatID: String
    ) throws -> AsyncThrowingStream<BFFWebSocketEvent, Error> {
        try openEventStream(chatID: chatID).events
    }

    public func openEventStream(chatID: String) throws -> BFFEventSubscription {
        guard let url = webSocketURL(chatID: chatID) else {
            throw BFFClientError.invalidBaseURL(baseURL.absoluteString)
        }

        let task = webSocketTaskFactory(socketSession, URLRequest(url: url))
        let keepAlive = socketKeepAlive
        let closeBox = ReceiverBox()
        let events = AsyncThrowingStream<BFFWebSocketEvent, Error> { continuation in
            task.resume()
            let receiver = Task {
                // Один декодер на сокет, а не на кадр: поток токенов — десятки
                // кадров в секунду (D-1960).
                let decoder = JSONDecoder()
                let pinger = Task { await Self.keepSocketAlive(task, keepAlive) }
                defer { pinger.cancel() }
                do {
                    while !Task.isCancelled {
                        let message = try await task.receive()
                        let data: Data
                        switch message {
                        case .data(let value):
                            data = value
                        case .string(let value):
                            data = Data(value.utf8)
                        @unknown default:
                            continue
                        }
                        let event: BFFWebSocketEvent
                        do {
                            event = try decoder.decode(BFFWebSocketEvent.self, from: data)
                        } catch {
                            // A single malformed/non-chat frame must not tear
                            // down an otherwise healthy stream. v2 skips it
                            // and still reconciles the final REST snapshot.
                            continue
                        }
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            closeBox.store(receiver)
            continuation.onTermination = { @Sendable _ in
                receiver.cancel()
                task.cancel(with: .goingAway, reason: nil)
            }
        }
        return BFFEventSubscription(events: events) {
            closeBox.cancel()
            task.cancel(with: .goingAway, reason: nil)
        }
    }

    /// Держит читателя сокета, чтобы `close()` мог снять его до того, как
    /// кто-то начал читать поток.
    /// Пинг раз в `interval`; нет pong за `pongTimeout` или ping упал — сокет
    /// закрывается, читатель получает ошибку, и `BFFChatService` переходит в
    /// обычное переподключение (D-1958). Завершается вместе с читателем.
    static func keepSocketAlive(
        _ task: any BFFWebSocketTask,
        _ keepAlive: BFFSocketKeepAlive
    ) async {
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: keepAlive.interval)
            } catch {
                return
            }
            let deadline = Task {
                do {
                    try await Task.sleep(for: keepAlive.pongTimeout)
                } catch {
                    return
                }
                task.cancel(with: .goingAway, reason: nil)
            }
            do {
                try await task.keepAlivePing()
                deadline.cancel()
            } catch {
                deadline.cancel()
                if !Task.isCancelled {
                    task.cancel(with: .goingAway, reason: nil)
                }
                return
            }
        }
    }

    private final class ReceiverBox: @unchecked Sendable {
        private let lock = NSLock()
        private var receiver: Task<Void, Never>?

        func store(_ task: Task<Void, Never>) {
            lock.lock(); receiver = task; lock.unlock()
        }

        func cancel() {
            lock.lock(); let task = receiver; lock.unlock()
            task?.cancel()
        }
    }

    // MARK: Request internals

    private func authenticatedSession(
        from pair: BFFTokenPair,
        fallbackUsername: String
    ) async throws -> BFFAuthenticatedSession {
        let newTokens = BFFAuthTokens(
            accessToken: pair.accessToken,
            refreshToken: pair.refreshToken
        )
        // Initial credentials are needed for `/auth/me`, but publishing the
        // generic callback here would let persistence bind them to whichever
        // older owner is still durable. The client is enabled only after the
        // returned clientID/backend are committed by AppSessionStore.
        setTokens(newTokens)

        let me: BFFUser?
        do {
            me = try await request(path: "/auth/me")
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            me = nil
        }

        guard let authenticatedTokens = tokens else {
            throw BFFClientError.sessionExpired
        }

        return BFFAuthenticatedSession(
            username: Self.preferredDisplayName(
                telegramFirstName: me?.telegramFirstName,
                tokenUsername: pair.username,
                accountUsername: me?.username,
                fallback: fallbackUsername
            ),
            // `/auth/me` is authoritative. If it is temporarily unavailable,
            // a signed token subject is still a backend identity. A malformed
            // or opaque token gets a fresh quarantine namespace instead of
            // keying private local data by mutable username/email.
            clientID: me?.id
                ?? Self.jwtSubject(from: pair.accessToken)
                ?? "unresolved-\(UUID().uuidString.lowercased())",
            tokens: authenticatedTokens
        )
    }

    /// Which of the names the backend returns is the one to show the person.
    ///
    /// The token response carries the login handle — for a Telegram sign-in
    /// that is `victoria_dochkina`, how machines address the account rather
    /// than what the person is called. `/auth/me` carries the Telegram first
    /// name, so that wins whenever there is one, and the handle stays as the
    /// fallback for accounts the backend has no name for.
    ///
    /// Blank counts as absent: the backend sends an empty string for a missing
    /// name as readily as it omits the field, and "Привет, " is worse than
    /// falling through to the handle.
    nonisolated static func preferredDisplayName(
        telegramFirstName: String?,
        tokenUsername: String?,
        accountUsername: String?,
        fallback: String
    ) -> String {
        for candidate in [telegramFirstName, tokenUsername, accountUsername] {
            guard
                let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
                !trimmed.isEmpty
            else { continue }
            return trimmed
        }
        return fallback
    }

    nonisolated static func jwtSubject(from token: String) -> String? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = payload.count % 4
        if remainder != 0 { payload += String(repeating: "=", count: 4 - remainder) }
        guard let data = Data(base64Encoded: payload) else { return nil }
        guard
            let decoded = try? JSONSerialization.jsonObject(with: data),
            let object = decoded as? [String: Any],
            let subject = object["sub"] as? String
        else { return nil }
        let trimmed = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func request<Response: Decodable>(
        path: String,
        method: String = "GET",
        body: Data? = nil,
        authentication: Bool = true,
        apiPrefix: Bool = true,
        queryItems: [URLQueryItem] = [],
        headers: [String: String] = [:],
        timeout: TimeInterval? = nil
    ) async throws -> Response {
        let currentTokens = authentication ? tokens : nil
        let urlRequest = try makeRequest(
            path: path,
            method: method,
            body: body,
            accessToken: currentTokens?.accessToken,
            apiPrefix: apiPrefix,
            queryItems: queryItems,
            headers: headers,
            timeout: timeout
        )
        let retryDelay = idempotentRetryDelay(for: method)
        let firstResponse = try await Self.execute(
            urlRequest,
            using: urlSession,
            retryDelay: retryDelay
        )

        guard
            firstResponse.statusCode == 401,
            authentication,
            currentTokens?.refreshToken != nil
        else {
            return try Self.decode(Response.self, from: firstResponse)
        }

        try await refreshIfStillCurrent(currentTokens)

        let retryRequest = try makeRequest(
            path: path,
            method: method,
            body: body,
            accessToken: tokens?.accessToken,
            apiPrefix: apiPrefix,
            queryItems: queryItems,
            headers: headers,
            timeout: timeout
        )
        let retryResponse = try await Self.execute(
            retryRequest,
            using: urlSession,
            retryDelay: retryDelay
        )
        if retryResponse.statusCode == 401 {
            setTokens(nil)
            throw BFFClientError.sessionExpired
        }
        return try Self.decode(Response.self, from: retryResponse)
    }

    /// Повтор после сбоя сети — только у GET: остальные методы могут
    /// выполниться дважды (D-1957). Пауза идёт через внедрённый `sleep`.
    private func idempotentRetryDelay(
        for method: String
    ) -> (@Sendable (TimeInterval) async throws -> Void)? {
        method.uppercased() == "GET" ? sleep : nil
    }

    private func requestNoContent(
        path: String,
        method: String,
        authentication: Bool = true,
        queryItems: [URLQueryItem] = []
    ) async throws {
        let currentTokens = authentication ? tokens : nil
        let urlRequest = try makeRequest(
            path: path,
            method: method,
            body: nil,
            accessToken: currentTokens?.accessToken,
            queryItems: queryItems
        )
        let retryDelay = idempotentRetryDelay(for: method)
        let firstResponse = try await Self.execute(
            urlRequest,
            using: urlSession,
            retryDelay: retryDelay
        )

        guard
            firstResponse.statusCode == 401,
            authentication,
            currentTokens?.refreshToken != nil
        else {
            try Self.validateSuccess(firstResponse)
            return
        }

        try await refreshIfStillCurrent(currentTokens)

        let retryRequest = try makeRequest(
            path: path,
            method: method,
            body: nil,
            accessToken: tokens?.accessToken,
            queryItems: queryItems
        )
        let retryResponse = try await Self.execute(
            retryRequest,
            using: urlSession,
            retryDelay: retryDelay
        )
        if retryResponse.statusCode == 401 {
            setTokens(nil)
            throw BFFClientError.sessionExpired
        }
        try Self.validateSuccess(retryResponse)
    }

    /// Один refresh на все пути, которые получили 401.
    ///
    /// Сессия истекает только когда сервер **отверг** refresh-токен. Обрыв
    /// сети, таймаут и 5xx во время `/auth/refresh` — не доказательство, что
    /// сессии нет: раньше любой такой сбой стирал токены и выбрасывал на экран
    /// входа (D-282).
    private func refreshOrExpire() async throws {
        do {
            try await refreshTokens()
        } catch BFFClientError.http(let statusCode, _)
            where statusCode == 400 || statusCode == 401 || statusCode == 403 {
            setTokens(nil)
            throw BFFClientError.sessionExpired
        } catch BFFClientError.sessionExpired {
            setTokens(nil)
            throw BFFClientError.sessionExpired
        }
    }

    /// Параллельный запрос мог уже обновить пару, пока этот ждал свой 401.
    /// Повторный refresh ротировал бы свежий refresh-токен второй раз и
    /// вслед за ним обесценил бы тот, что уже ушёл в Keychain (D-283).
    private func refreshIfStillCurrent(_ used: BFFAuthTokens?) async throws {
        if let current = tokens, let used, current.accessToken != used.accessToken {
            return
        }
        try await refreshOrExpire()
    }

    /// Секунды до истечения access-токена по его `exp`; `nil`, если токен
    /// непрозрачен.
    nonisolated static func jwtSecondsToExpiry(_ token: String, now: Date) -> TimeInterval? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = payload.count % 4
        if remainder != 0 { payload += String(repeating: "=", count: 4 - remainder) }
        guard
            let data = Data(base64Encoded: payload),
            let decoded = try? JSONSerialization.jsonObject(with: data),
            let object = decoded as? [String: Any],
            let exp = object["exp"] as? Double
        else { return nil }
        return exp - now.timeIntervalSince1970
    }

    /// Обновляет пару заранее, если access-токен истекает в ближайшие
    /// `margin` секунд. Нужно перед открытием сокета: `/ws/{chat}` берёт токен
    /// из строки запроса и не умеет ни 401, ни повторить — он просто
    /// закрывается кодом 4401, и ход идёт без стрима (D-284).
    public func ensureFreshAccessToken(margin: TimeInterval = 60) async throws {
        guard
            let tokens,
            !tokens.refreshToken.isEmpty,
            let secondsLeft = Self.jwtSecondsToExpiry(tokens.accessToken, now: now()),
            secondsLeft < margin
        else { return }
        try await refreshOrExpire()
    }

    private func refreshTokens() async throws {
        if let refreshTask {
            let pair = try await refreshTask.value
            setTokens(BFFAuthTokens(
                accessToken: pair.accessToken,
                refreshToken: pair.refreshToken
            ))
            return
        }

        guard let refreshToken = tokens?.refreshToken else {
            throw BFFClientError.sessionExpired
        }
        let body = try encode(RefreshBody(refreshToken: refreshToken))
        let refreshRequest = try makeRequest(
            path: "/auth/refresh",
            method: "POST",
            body: body,
            accessToken: nil
        )
        let session = urlSession
        let task = Task {
            let response = try await Self.execute(refreshRequest, using: session)
            return try Self.decode(BFFTokenPair.self, from: response)
        }
        refreshTask = task
        defer { refreshTask = nil }

        let pair = try await task.value
        setTokens(BFFAuthTokens(
            accessToken: pair.accessToken,
            refreshToken: pair.refreshToken
        ))
    }

    private func setTokens(_ newTokens: BFFAuthTokens?) {
        tokens = newTokens
        if tokenUpdatesEnabled {
            tokenUpdate(newTokens)
        }
    }

    private func makeRequest(
        path: String,
        method: String,
        body: Data?,
        accessToken: String?,
        apiPrefix: Bool = true,
        queryItems: [URLQueryItem] = [],
        headers: [String: String] = [:],
        timeout: TimeInterval? = nil
    ) throws -> URLRequest {
        guard let url = endpointURL(
            path: path,
            apiPrefix: apiPrefix,
            queryItems: queryItems
        ) else {
            throw BFFClientError.invalidBaseURL(baseURL.absoluteString)
        }

        var request = URLRequest(
            url: url,
            timeoutInterval: timeout ?? requestTimeout
        )
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("oasis-mobile", forHTTPHeaderField: "X-Client-App")
        request.setValue("ios", forHTTPHeaderField: "X-Client-Platform")
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        if let accessToken {
            // URLCache is process-wide, not account-aware. Authenticated REST
            // responses must always come from the server for this token.
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func makeUploadRequest(
        boundary: String,
        accessToken: String?
    ) throws -> URLRequest {
        guard let url = endpointURL(
            path: "/uploads",
            apiPrefix: true,
            queryItems: []
        ) else {
            throw BFFClientError.invalidBaseURL(baseURL.absoluteString)
        }

        var request = URLRequest(url: url, timeoutInterval: 120)
        request.httpMethod = "POST"
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )
        request.setValue("oasis-mobile", forHTTPHeaderField: "X-Client-App")
        request.setValue("ios", forHTTPHeaderField: "X-Client-Platform")
        if let accessToken {
            request.setValue(
                "Bearer \(accessToken)",
                forHTTPHeaderField: "Authorization"
            )
        }
        return request
    }

    /// Multipart request against an arbitrary API path (upload has its own
    /// helper because it streams from a file instead of memory).
    private func makeMultipartRequest(
        path: String,
        boundary: String,
        queryItems: [URLQueryItem],
        accessToken: String?
    ) throws -> URLRequest {
        guard let url = endpointURL(
            path: path,
            apiPrefix: true,
            queryItems: queryItems
        ) else {
            throw BFFClientError.invalidBaseURL(baseURL.absoluteString)
        }

        var request = URLRequest(url: url, timeoutInterval: 120)
        request.httpMethod = "POST"
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )
        request.setValue("oasis-mobile", forHTTPHeaderField: "X-Client-App")
        request.setValue("ios", forHTTPHeaderField: "X-Client-Platform")
        if let accessToken {
            request.setValue(
                "Bearer \(accessToken)",
                forHTTPHeaderField: "Authorization"
            )
        }
        return request
    }

    private static func multipartBody(
        data: Data,
        fieldName: String,
        filename: String,
        mimeType: String,
        boundary: String
    ) -> Data {
        // Same part shape as the upload path, same reason it must be built
        // explicitly: `POST /api/stt` refused a part whose headers ended in a
        // bare CR, so server recognition failed for every recording.
        var body = Self.multipartHeader(
            fieldName: fieldName,
            filename: filename,
            mimeType: mimeType,
            boundary: boundary
        )
        body.append(data)
        body.append(Self.multipartFooter(boundary: boundary))
        return body
    }

    private func endpointURL(
        path: String,
        apiPrefix: Bool,
        queryItems: [URLQueryItem]
    ) -> URL? {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        let rootPath = baseURL.path == "/" ? "" : baseURL.path
        components?.percentEncodedPath =
            rootPath + (apiPrefix ? "/api" : "") + path
        components?.queryItems = queryItems.isEmpty ? nil : queryItems
        components?.fragment = nil
        return components?.url
    }

    private func webSocketURL(chatID: String) -> URL? {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        switch components?.scheme?.lowercased() {
        case "http": components?.scheme = "ws"
        case "https": components?.scheme = "wss"
        default: return nil
        }
        let rootPath = baseURL.path == "/" ? "" : baseURL.path
        components?.percentEncodedPath =
            rootPath + "/ws/" + Self.pathComponent(chatID)
        components?.queryItems = [
            URLQueryItem(name: "token", value: tokens?.accessToken ?? "")
        ]
        components?.fragment = nil
        return components?.url
    }

    private func encode<Value: Encodable>(_ value: Value) throws -> Data {
        do {
            return try JSONEncoder().encode(value)
        } catch {
            ChatDiagnostics.note("запрос не собран: \(error)")
            throw BFFClientError.encoding(L("Не удалось отправить запрос. Попробуйте ещё раз."))
        }
    }

    /// The bytes before the file in a `multipart/form-data` part.
    ///
    /// Every line has to end in CRLF, including the empty line that separates
    /// the part's headers from its content. Building this with a Swift
    /// multiline literal dropped exactly that final newline — the literal does
    /// not include the break before its closing quotes — so the part ended in a
    /// lone CR and a strict parser answered `400 There was an error parsing the
    /// body`. Every upload with an attachment failed on it, which is why the
    /// bytes are assembled explicitly here and asserted in tests.
    static func multipartHeader(
        fieldName: String = "files",
        filename: String,
        mimeType: String,
        boundary: String
    ) -> Data {
        let safeFilename = filename
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
        let lines = [
            "--\(boundary)",
            "Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(safeFilename)\"",
            "Content-Type: \(mimeType)",
            "",
        ]
        return Data(lines.map { $0 + "\r\n" }.joined().utf8)
    }

    /// The close-delimiter: CRLF, then the boundary marked closed, then CRLF.
    static func multipartFooter(boundary: String) -> Data {
        Data("\r\n--\(boundary)--\r\n".utf8)
    }

    private static func multipartFile(
        data: Data,
        filename: String,
        mimeType: String,
        boundary: String
    ) throws -> URL {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "nika-upload-\(UUID().uuidString.lowercased()).multipart"
            )
        let header = Self.multipartHeader(
            filename: filename,
            mimeType: mimeType,
            boundary: boundary
        )
        let footer = Self.multipartFooter(boundary: boundary)

        do {
            try header.write(
                to: fileURL,
                options: [.atomic, .completeFileProtection]
            )
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.write(contentsOf: footer)
            return fileURL
        } catch {
            try? FileManager.default.removeItem(at: fileURL)
            throw BFFClientError.transport(error.localizedDescription)
        }
    }

    /// Кратковременные сбои сети, после которых повтор имеет смысл: обрыв
    /// соединения посреди запроса, таймаут, сервер на миг не принял сокет.
    /// «Нет сети» сюда не входит — офлайн должен падать сразу, а не через
    /// лишние 0,4 с (D-1957).
    static func isTransientTransportFailure(_ code: URLError.Code) -> Bool {
        switch code {
        case .networkConnectionLost, .timedOut, .cannotConnectToHost:
            return true
        default:
            return false
        }
    }

    /// Пауза перед единственным повтором идемпотентного запроса (D-1957).
    static let transientRetryDelay: TimeInterval = 0.4

    private static func perform(
        _ request: URLRequest,
        using session: URLSession
    ) async throws -> HTTPResponse {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BFFClientError.invalidResponse
        }
        return HTTPResponse(
            data: data,
            statusCode: httpResponse.statusCode,
            fallbackMessage: HTTPURLResponse.localizedString(
                forStatusCode: httpResponse.statusCode
            )
        )
    }

    /// `retryDelay != nil` — запрос идемпотентен (GET): при кратковременном
    /// сбое сети он уходит ещё раз после паузы. 4xx/5xx — не сбой сети.
    private static func execute(
        _ request: URLRequest,
        using session: URLSession,
        retryDelay: (@Sendable (TimeInterval) async throws -> Void)? = nil
    ) async throws -> HTTPResponse {
        do {
            do {
                return try await perform(request, using: session)
            } catch let error as URLError where retryDelay != nil
                && isTransientTransportFailure(error.code) {
                try await retryDelay?(transientRetryDelay)
                return try await perform(request, using: session)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as BFFClientError {
            throw error
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as URLError where error.code == .timedOut {
            throw BFFClientError.timedOut
        } catch {
            throw BFFClientError.transport(error.localizedDescription)
        }
    }

    private static func performUpload(
        _ request: URLRequest,
        fromFile fileURL: URL,
        using session: URLSession
    ) async throws -> HTTPResponse {
        let (data, response) = try await session.upload(
            for: request,
            fromFile: fileURL
        )
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BFFClientError.invalidResponse
        }
        return HTTPResponse(
            data: data,
            statusCode: httpResponse.statusCode,
            fallbackMessage: HTTPURLResponse.localizedString(
                forStatusCode: httpResponse.statusCode
            )
        )
    }

    /// Загрузка повторяется один раз при обрыве соединения или таймауте
    /// (D-1956). Сервер кладёт каждый загруженный файл под новым ключом, так
    /// что повтор после «обрыва на последнем байте» оставляет сиротский файл,
    /// но не портит ответ: клиент получает `file_id` от успешной попытки.
    private static func executeUpload(
        _ request: URLRequest,
        fromFile fileURL: URL,
        using session: URLSession,
        retryDelay: @escaping @Sendable (TimeInterval) async throws -> Void = { _ in }
    ) async throws -> HTTPResponse {
        do {
            do {
                return try await performUpload(request, fromFile: fileURL, using: session)
            } catch let error as URLError
                where error.code == .networkConnectionLost || error.code == .timedOut {
                try await retryDelay(transientRetryDelay)
                return try await performUpload(request, fromFile: fileURL, using: session)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as BFFClientError {
            throw error
        } catch let error as URLError where error.code == .timedOut {
            throw BFFClientError.timedOut
        } catch {
            throw BFFClientError.transport(error.localizedDescription)
        }
    }

    private static func decode<Response: Decodable>(
        _ type: Response.Type,
        from response: HTTPResponse
    ) throws -> Response {
        guard (200..<300).contains(response.statusCode) else {
            throw BFFClientError.http(
                statusCode: response.statusCode,
                message: errorMessage(
                    from: response.data,
                    fallback: response.fallbackMessage
                )
            )
        }
        do {
            return try JSONDecoder().decode(type, from: response.data)
        } catch {
            ChatDiagnostics.note("ответ сервера не разобран: \(error)")
            throw BFFClientError.decoding(error.localizedDescription)
        }
    }

    private static func validateSuccess(_ response: HTTPResponse) throws {
        guard (200..<300).contains(response.statusCode) else {
            throw BFFClientError.http(
                statusCode: response.statusCode,
                message: errorMessage(
                    from: response.data,
                    fallback: response.fallbackMessage
                )
            )
        }
    }

    private static func errorMessage(from data: Data, fallback: String) -> String {
        guard !data.isEmpty else { return fallback }
        if
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let detail = object["detail"] ?? object["message"]
        {
            if let detail = detail as? String {
                return detail
            }
            if
                JSONSerialization.isValidJSONObject(detail),
                let serialized = try? JSONSerialization.data(withJSONObject: detail),
                let value = String(data: serialized, encoding: .utf8)
            {
                return value
            }
            return String(describing: detail)
        }
        return String(data: data, encoding: .utf8) ?? fallback
    }

    private static func pathComponent(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static func orderByTurn(
        _ messages: [BFFRemoteMessage]
    ) -> [BFFRemoteMessage] {
        var anchors: [String: String] = [:]
        for message in messages {
            let key = message.taskID ?? message.id
            anchors[key] = min(anchors[key] ?? message.createdAt, message.createdAt)
        }
        return messages.enumerated().sorted { left, right in
            let leftAnchor = anchors[left.element.taskID ?? left.element.id] ?? ""
            let rightAnchor = anchors[right.element.taskID ?? right.element.id] ?? ""
            if leftAnchor != rightAnchor {
                return leftAnchor < rightAnchor
            }
            if left.element.createdAt != right.element.createdAt {
                return left.element.createdAt < right.element.createdAt
            }
            return left.offset < right.offset
        }.map(\.element)
    }

    private static func hasCompletedAnswer(
        in messages: [BFFRemoteMessage],
        acceptedUserContent: Set<String>,
        taskID: String?,
        mode: BFFMessageMode,
        baseURL: URL
    ) -> Bool {
        if mode == .image {
            guard
                let taskID,
                !taskID.isEmpty,
                let user = messages.last(where: {
                    $0.role == .user && $0.taskID == taskID
                }),
                acceptedUserContent.contains(
                    user.content.trimmingCharacters(in: .whitespacesAndNewlines)
                ),
                let assistant = messages.last(where: {
                    $0.role == .assistant && $0.taskID == taskID
                }),
                assistant.attachments?.contains(where: {
                    BFFAttachmentURLPolicy.isUsableImageAttachment(
                        $0,
                        baseURL: baseURL
                    )
                }) == true
            else {
                return false
            }
            return true
        }

        guard
            let lastUser = messages.last(where: { $0.role == .user }),
            acceptedUserContent.contains(
                lastUser.content.trimmingCharacters(in: .whitespacesAndNewlines)
            ),
            let lastMessage = messages.last,
            lastMessage.role == .assistant,
            !lastMessage.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return false
        }

        guard let taskID else { return true }
        // Older BFF history may omit task_id. When present, use it to avoid
        // reconciling another concurrent turn from the same chat.
        return lastMessage.taskID.map { $0 == taskID } ?? true
    }

}

struct PersonalNewsItem: Equatable, Identifiable, Sendable {
    let id: String
    let source: String
    let title: String
    let publishedAt: Date?
    let fetchedAt: Date?
    let tags: [String]

    init(brief: BFFPersonalNewsItem) {
        id = brief.id
        source = brief.source
        title = brief.title
        publishedAt = Self.parseDate(brief.publishedAt)
        fetchedAt = Self.parseDate(brief.fetchedAt)
        tags = Array(brief.tags.prefix(2))
    }

    var displayDate: Date? { publishedAt ?? fetchedAt }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

struct NewsDiscussionReceipt: Equatable, Sendable {
    let chatID: String
    let messageID: String
    let taskID: String
}

protocol PersonalNewsFetching: Sendable {
    func fetchNewItems() async throws -> [PersonalNewsItem]
    func markVisible(_ items: [PersonalNewsItem]) async throws
    func discuss(itemID: String) async throws -> NewsDiscussionReceipt
}

actor BFFNewsService: PersonalNewsFetching {
    nonisolated static let minimumScore = 0.7
    nonisolated static let maximumVisibleItems = 3
    nonisolated static let readPath = "/api/news"
    nonisolated static let mutationSuffixes = ["/mark-toasted", "/discuss"]

    private let client: BFFClient
    private var surfacedIDs: Set<String> = []

    init(client: BFFClient) {
        self.client = client
    }

    func fetchNewItems() async throws -> [PersonalNewsItem] {
        let rows = try await client.fetchPersonalNews(
            limit: 50,
            offset: 0,
            minimumScore: Self.minimumScore
        )
        return Self.selectNewItems(from: rows)
    }

    nonisolated static func selectNewItems(
        from rows: [BFFPersonalNewsItem]
    ) -> [PersonalNewsItem] {
        rows.lazy
            .filter { row in
                guard let score = row.score else { return false }
                return score >= minimumScore
                    && row.toastedAt == nil
                    && row.discussedChatID == nil
                    && !row.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            .prefix(maximumVisibleItems)
            .map(PersonalNewsItem.init)
    }

    func markVisible(_ items: [PersonalNewsItem]) async throws {
        for item in items where !surfacedIDs.contains(item.id) {
            try await client.markNewsSurfaced(id: item.id)
            surfacedIDs.insert(item.id)
        }
    }

    func discuss(itemID: String) async throws -> NewsDiscussionReceipt {
        let response = try await client.discussNews(id: itemID)
        return NewsDiscussionReceipt(
            chatID: response.chatID,
            messageID: response.messageID,
            taskID: response.taskID
        )
    }
}

private struct HTTPResponse: Sendable {
    let data: Data
    let statusCode: Int
    let fallbackMessage: String
}

private struct LoginBody: Encodable {
    let username: String
    let password: String
}

private struct SignupBody: Encodable {
    let username: String
    let password: String
    let inviteCode: String

    enum CodingKeys: String, CodingKey {
        case username
        case password
        case inviteCode = "invite_code"
    }
}

private struct RefreshBody: Encodable {
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case refreshToken = "refresh_token"
    }
}

private struct CreateChatBody: Encodable {
    let title: String
    let isIncognito: Bool
    let isCoaching: Bool
    let noStore: Bool

    enum CodingKeys: String, CodingKey {
        case title
        case isIncognito = "is_incognito"
        case isCoaching = "is_coaching"
        case noStore = "no_store"
    }
}

struct SendMessageBody: Encodable {
    let content: String
    let chatID: String
    let llmModel: String?
    let attachments: [BFFUploadedAttachment]?
    let reasoning: Bool?
    let noStore: Bool?
    let isIncognito: Bool?
    let executionMode: BFFExecutionMode?
    let extraTaskMetadata: [String: BFFJSONValue]?

    enum CodingKeys: String, CodingKey {
        case content
        case chatID = "chat_id"
        case llmModel = "llm_model"
        case attachments
        case reasoning
        case noStore = "no_store"
        case isIncognito = "is_incognito"
        case executionMode = "execution_mode"
        case extraTaskMetadata = "extra_task_metadata"
    }
}

private struct DeviceToolResultBody: Encodable {
    let status: String
    let result: [String: BFFJSONValue]
    let error: String?
}

private struct OpenRouterKeyBody: Encodable {
    let apiKey: String

    enum CodingKeys: String, CodingKey {
        case apiKey = "api_key"
    }
}

private struct OpenRouterModelsResponse: Decodable {
    let data: [OpenRouterModel]
}

private struct OpenRouterModel: Decodable {
    let id: String
    let name: String
    let description: String?
    let contextLength: Int?
    let pricing: OpenRouterPricing?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case contextLength = "context_length"
        case pricing
    }
}

private struct OpenRouterPricing: Decodable {
    let prompt: String?
    let completion: String?
}
