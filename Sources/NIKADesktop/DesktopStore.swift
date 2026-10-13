import SwiftUI
import UniformTypeIdentifiers
import PDFKit

struct AnswerVariant: Codable, Equatable {
    var content: String
    var sources: [String]
    var media: [DesktopAttachment]?
}
struct DesktopMessage: Identifiable, Codable, Equatable {
    var id = UUID().uuidString
    let role: String
    var content: String
    var sources: [String] = []
    var files: [String] = []
    var media: [DesktopAttachment]?
    var versions: [AnswerVariant]?
    var selectedVersion: Int?
    var taskID: String?
    var localImages: [String]?
}
struct LocalConversation: Identifiable, Codable {
    var id = UUID().uuidString
    var title: String
    var modelID: String
    var messages: [DesktopMessage] = []
    var updated = Date()
    var pinned = false
}
struct StoredLogin: Codable { let baseURL: String; var session: BFFAuthenticatedSession }

@MainActor
final class DesktopStore: ObservableObject {
    nonisolated static var supportDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["NIKA_DESKTOP_DATA"] { return URL(fileURLWithPath: override) }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("NIKA Desktop", isDirectory: true)
    }
    @Published var cloudChats: [BFFRemoteChatInfo] = []
    @Published var localMemories: [DesktopMemory] = []
    private var memoriesReadable = true
    @Published var localChats: [LocalConversation] = []
    @Published var login: StoredLogin?
    @Published var client: BFFClient?
    @Published var error: String?
    @Published var busy = false
    @Published var models: [BFFOnlineModel] = []
    @Published var baseURL = UserDefaults.standard.string(forKey: "backend") ?? "https://nika-agent.ru"
    @Published var settings: InferenceSettings { didSet { if let data = try? JSONEncoder().encode(settings) { UserDefaults.standard.set(data, forKey: "inference") } } }
    let library: ModelLibrary
    let assets: URL
    private let history: URL
    private var historyReadable = true
    private var epoch = UUID()
    private var hasRestored = false
    private var allowsRestore = true
    var suppressedCloudMessages: [String: Set<String>] = [:]
    var cloudAnswerVersions: [String: [String: DesktopMessage]] = [:]
    private var windows = NSHashTable<Workspace>.weakObjects()
    init(root: URL = DesktopStore.supportDirectory, restoreCredentials: Bool = true) {
        allowsRestore = restoreCredentials && ProcessInfo.processInfo.environment["NIKA_DESKTOP_DATA"] == nil
        library = ModelLibrary(root: root)
        assets = root.appendingPathComponent("Attachments", isDirectory: true)
        history = root.appendingPathComponent("local-conversations.json")
        settings = UserDefaults.standard.data(forKey: "inference").flatMap { try? JSONDecoder().decode(InferenceSettings.self, from: $0) } ?? .init()
        let memoryFile = root.appendingPathComponent("local-memories.json")
        if FileManager.default.fileExists(atPath: memoryFile.path) {
            do { localMemories = try JSONDecoder().decode([DesktopMemory].self, from: Data(contentsOf: memoryFile)) }
            catch { memoriesReadable = false; self.error = "Не удалось прочитать локальную память. Исходный файл сохранён." }
        }

        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: history.path) { localChats = try JSONDecoder().decode([LocalConversation].self, from: Data(contentsOf: history)) }

        } catch { self.error = error.localizedDescription; if FileManager.default.fileExists(atPath: history.path), (try? JSONDecoder().decode([LocalConversation].self, from: Data(contentsOf: history))) == nil { historyReadable = false } }
    }
    func restoreSession() async {
        guard allowsRestore, !hasRestored, login == nil else { return }
        hasRestored = true
        let lease = epoch
        do {
            let data = try await Task.detached { try Vault.read() }.value
            guard lease == epoch, let data else { return }
            let stored = try JSONDecoder().decode(StoredLogin.self, from: data)
            login = stored; baseURL = stored.baseURL; client = try makeClient(tokens: stored.session.tokens)
        } catch {
            if lease == epoch { self.error = "Не удалось открыть сохранённый вход. Войдите в аккаунт снова. " + error.localizedDescription }
        }
    }
    func register(_ workspace: Workspace) { windows.add(workspace) }
    private func makeClient(tokens: BFFAuthTokens? = nil) throws -> BFFClient {
        let generation = epoch
        return try BFFClient(baseURL: baseURL, initialTokens: tokens, tokenUpdate: { [weak self] tokens in
            Task { @MainActor in
                guard let self, self.epoch == generation, var stored = self.login else { return }
                guard let tokens else { self.error = "Сессия истекла. Войдите снова."; self.clearCloud(); return }
                stored.session = .init(username: stored.session.username, clientID: stored.session.clientID, tokens: tokens)
                do { try Vault.write(JSONEncoder().encode(stored)); self.login = stored }
                catch { self.error = error.localizedDescription }
            }
        })
    }
    func authenticate(email: String, password: String, signup: Bool = false, invite: String = "") async {
        guard !busy else { return }
        busy = true; error = nil; defer { busy = false }
        do {
            epoch = UUID()
            let client = try makeClient()
            let session: BFFAuthenticatedSession
            if signup { session = try await client.signup(email: email, password: password, inviteCode: invite.isEmpty ? nil : invite) }
            else { session = try await client.login(email: email, password: password) }
            try await finishLogin(session, client: client)
        } catch { self.error = error.localizedDescription }
    }
    func apple(token: String, name: PersonNameComponents?) async {
        guard !busy else { return }; busy = true; error = nil; defer { busy = false }
        do {
            epoch = UUID(); let client = try makeClient()
            try await finishLogin(try await client.loginWithApple(identityToken: token, firstName: name?.givenName, lastName: name?.familyName), client: client)
        } catch { self.error = error.localizedDescription }
    }
    func telegram() async {
        guard !busy else { return }
        busy = true; error = nil; defer { busy = false }
        do {
            epoch = UUID(); let client = try makeClient()
            let start = try await client.startTelegramLogin()
            guard let url = URL(string: start.deepLink), ["https", "tg"].contains(url.scheme ?? "") else { throw DesktopError("Некорректная ссылка входа.") }
            NSWorkspace.shared.open(url)
            for _ in 0..<min(150, start.expiresIn / 2) {
                try Task.checkCancellation()
                let status = try await client.telegramLoginStatus(state: start.state)
                if status == .ready { try await finishLogin(try await client.exchangeTelegramLogin(state: start.state), client: client); return }
                if status == .expired { break }
                try await Task.sleep(for: .seconds(2))
            }
            throw DesktopError("Время входа истекло. Попробуйте снова.")
        } catch { self.error = error.localizedDescription }
    }
    private func finishLogin(_ session: BFFAuthenticatedSession, client: BFFClient) async throws {
        try Task.checkCancellation()
        let stored = StoredLogin(baseURL: client.baseURL.absoluteString, session: session)
        try Vault.write(JSONEncoder().encode(stored))
        login = stored; self.client = client
        await client.enableTokenUpdates()
        UserDefaults.standard.set(baseURL, forKey: "backend")
        await refresh()
    }
    private func clearCloud() {
        epoch = UUID()
        for workspace in windows.allObjects where !workspace.isLocal { workspace.stop(); workspace.newChat() }
        client = nil; login = nil; cloudChats = []; models = []; suppressedCloudMessages = [:]; cloudAnswerVersions = [:]
    }
    func logout() {
        do { try Vault.write(nil); clearCloud() } catch { self.error = error.localizedDescription }
    }
    func deleteAccount() async {
        guard let client else { return }
        do { _ = try await client.deleteMyAccount(); logout() } catch { self.error = error.localizedDescription }
    }
    func refresh() async {
        guard let client else { return }
        let generation = epoch
        do {
            let chats = try await client.listChatsForDisplay()
            guard generation == epoch else { return }
            cloudChats = chats
        } catch { if generation == epoch { self.error = error.localizedDescription } }
    }
    func fetchModels() async {
        guard models.isEmpty, let client else { return }
        do { models = try await client.listOnlineModels() } catch { self.error = error.localizedDescription }
    }
    func save(_ conversation: LocalConversation) {
        if let index = localChats.firstIndex(where: { $0.id == conversation.id }) { localChats[index] = conversation }
        else { localChats.insert(conversation, at: 0) }
        persist()
    }
    func persist() {
        guard historyReadable else { error = "Файл локальной истории повреждён и сохранён без изменений. Скопируйте его перед восстановлением."; return }
        do { try JSONEncoder().encode(localChats).write(to: history, options: .atomic) }
        catch { self.error = "Не удалось сохранить разговор: \(error.localizedDescription)" }
    }
    func saveMemories(_ items: [DesktopMemory]) {
        guard memoriesReadable else { error = "Файл памяти повреждён. Сначала восстановите его копию."; return }
        do { try JSONEncoder().encode(items).write(to: history.deletingLastPathComponent().appendingPathComponent("local-memories.json"), options: .atomic); localMemories = items }
        catch { self.error = error.localizedDescription }
    }
    var localMemoryContext: String {
        guard UserDefaults.standard.object(forKey: "localMemoryEnabled") == nil || UserDefaults.standard.bool(forKey: "localMemoryEnabled") else { return "" }
        return String(localMemories.sorted { $0.isPinned && !$1.isPinned }.map { "\($0.title): \($0.detail)" }.joined(separator: "\n").prefix(5000))
    }
    func deleteLocal(_ id: String) { localChats.removeAll { $0.id == id }; persist() }
}

@MainActor
final class Workspace: NSObject, ObservableObject {
    @Published var messages: [DesktopMessage] = []
    @Published var draft = ""
    @Published var attachments: [URL] = []
    @Published var providerID = "cloud"
    @Published var cloudModel = ""
    @Published var title = "Новый разговор"
    @Published var activity: [String] = []
    @Published var error: String?
    @Published var sending = false
    @Published var loading = false
    @Published var personalBotSyncError: String?
    @Published var inspector = false
    @Published var reasoning = false
    @Published var imageMode = false
    @Published var incognito = false
    @Published var selectedID: String?
    @Published var agentID: String?
    @Published var agentName: String?
    @Published var agentPrompt: String?
    @Published var browserEvents: [BFFWebSocketEvent] = []
    @Published var browserRequest: BrowserQuestion?
    @Published var requestedDestination: String?
    @Published var focusSearch = UUID()
    @Published var modelPicker = false
    @Published var voicePanel = false
    @Published var editingMessageID: String?
    @Published var localToolsEnabled = false
    @Published var localProposal: LocalAction?
    private var localApproval: CheckedContinuation<Bool, Never>?
    private var remote: BFFRemoteChatInfo?
    private var local: LocalConversation?
    private var task: Task<Void, Never>?
    private var acceptedTask: String?
    private var regenerationBaseline: [DesktopMessage]?
    private var generation = UUID()
    let store: DesktopStore
    var isLocal: Bool { providerID != "cloud" }
    init(store: DesktopStore) { self.store = store; super.init(); store.register(self) }
    func navigateConversation(_ direction: Int) {
        let locals = store.localChats.sorted { $0.updated > $1.updated }
        let ids = locals.map(\.id) + store.cloudChats.map(\.id)
        guard !ids.isEmpty else { return }
        let current = ids.firstIndex(of: selectedID ?? "") ?? (direction > 0 ? -1 : ids.count)
        let index = max(0, min(ids.count - 1, current + direction)); let id = ids[index]
        requestedDestination = "chat"
        if let chat = locals.first(where: { $0.id == id }) { open(chat) }
        else if let chat = store.cloudChats.first(where: { $0.id == id }) { Task { await open(chat) } }
    }
    func newChat(provider: String? = nil) {
        stop(); personalBotSyncError = nil; generation = UUID(); messages = []; attachments = []; draft = ""; activity = []
        agentID = nil; agentName = nil; agentPrompt = nil; browserEvents = []; browserRequest = nil; editingMessageID = nil; remote = nil; local = nil; selectedID = nil; title = "Новый разговор"; error = nil
        if let provider { providerID = provider }
    }
    func selectProvider(_ id: String) { if id != providerID { newChat(provider: id) } }
    func open(_ chat: LocalConversation) {
        newChat(provider: chat.modelID); local = chat; messages = chat.messages; title = chat.title; selectedID = chat.id
    }
    func open(_ chat: BFFRemoteChatInfo) async {
        newChat(provider: "cloud"); remote = chat; selectedID = chat.id; title = chat.displayTitle
        let lease = generation; loading = true; defer { if generation == lease { loading = false } }
        do {
            guard let client = store.client else { throw DesktopError("Войдите в NIKA.") }
            let fetched = try await client.fetchChat(chat)
            guard lease == generation else { return }
            messages = Self.project(fetched.messages).filter { !(store.suppressedCloudMessages[chat.id] ?? []).contains($0.id) }; overlayVersions(chatID: chat.id)
            if let pending: PendingBrowserInput = try? await DesktopAPI(client: client).request("chats/\(chat.id)/browser-input"), generation == lease { browserRequest = BrowserQuestion(pending: pending); inspector = true }
            if let document: [String: BFFJSONValue] = try? await DesktopAPI(client: client).request("chats/\(chat.id)"), generation == lease, case .object(let personality) = document["personality"] {
                if case .string(let value) = personality["name"] { agentName = value }
                if case .string(let value) = personality["system_prompt"] { agentPrompt = value }
            }
        } catch { if lease == generation { self.error = error.localizedDescription } }
    }
    /// Refresh unsolicited bot messages without replacing an in-flight response or a newer session.
    func refreshPersonalBot(id: String) async {
        guard selectedID == id, !sending, !loading, let remote, let client = store.client else { return }
        let lease = generation
        let baseline = messages.map { $0.id + $0.content }
        do {
            let fetched = try await client.fetchChat(remote)
            guard !Task.isCancelled, generation == lease, selectedID == id, !sending,
                  baseline == messages.map({ $0.id + $0.content }) else { return }
            messages = Self.project(fetched.messages).filter { !(store.suppressedCloudMessages[id] ?? []).contains($0.id) }
            overlayVersions(chatID: id); personalBotSyncError = nil
        } catch { if generation == lease && !Task.isCancelled { personalBotSyncError = "Обновление приостановлено. Проверьте подключение — повторим автоматически." } }
    }
    nonisolated static func personalityChatBody(title: String, name: String, prompt: String, ephemeral: Bool) -> [String: BFFJSONValue] {
        ["title": .string(title), "is_incognito": .bool(ephemeral), "is_coaching": .bool(false), "personality": .object(["name": .string(name), "system_prompt": .string(prompt)])]
    }
    static func project(_ messages: [BFFRemoteMessage]) -> [DesktopMessage] {
        messages.map { .init(id: $0.id, role: $0.role.rawValue, content: $0.content,
                            sources: ($0.sources ?? $0.citations ?? []).compactMap(\.url),
                            files: [], media: ($0.attachments ?? []).compactMap { item in
                                guard let path = item.fileID.map({ "api/files/\($0)" }) ?? item.url ?? item.downloadURL else { return nil }
                                return DesktopAttachment(path: path, name: item.filename ?? "Вложение", mime: item.mimeType ?? "application/octet-stream")
                            }, taskID: $0.taskID) }
    }
    func add(_ urls: [URL]) {
        for url in urls where !attachments.contains(url) { attachments.append(url) }
    }
    func send(regenerating original: DesktopMessage? = nil) {
        let text = original == nil ? draft.trimmingCharacters(in: .whitespacesAndNewlines) : messages.last(where: { $0.role == "user" })?.content ?? ""
        guard !sending, !text.isEmpty else { return }
        if !isLocal && store.client == nil { error = "Войдите в NIKA или выберите локальную модель."; return }
        let lease = generation; let files = original == nil ? attachments : []; let baseline = messages
        let editIndex = original == nil ? editingMessageID.flatMap { id in messages.firstIndex(where: { $0.id == id && $0.role == "user" }) } : nil
        let edited = editIndex.map { messages[$0] }
        let previous = editIndex.map { Array(messages.prefix($0)) } ?? (original == nil ? messages : Array(messages.dropLast(2)))
        if let editIndex {
            if !isLocal, let selectedID { store.suppressedCloudMessages[selectedID, default: []].formUnion(messages[editIndex...].map(\.id)) }
            messages.removeSubrange(editIndex...); editingMessageID = nil
        }
        if original != nil { regenerationBaseline = baseline }
        let selectedProvider = providerID
        sending = true; error = nil; activity = []
        if original == nil { draft = ""; attachments = [] }
        if original == nil {
            var user = DesktopMessage(role: "user", content: text, files: files.map(\.lastPathComponent))
            if files.isEmpty { user.localImages = edited?.localImages; user.media = edited?.media }
            messages.append(user)
        }
        else { messages.removeLast() }
        let answerID = UUID().uuidString
        messages.append(.init(id: answerID, role: "assistant", content: ""))
        if title == "Новый разговор" { title = String(text.prefix(65)) }
        task = Task { [weak self] in
            guard let self else { return }
            defer { if self.generation == lease { self.sending = false; self.acceptedTask = nil; self.task = nil; self.saveLocal() } }
            do {
                if selectedProvider != "cloud" {
                    guard let model = self.store.library.models.first(where: { $0.id == selectedProvider }), self.store.library.installed.contains(model.id) else {
                        throw DesktopError("Сначала установите выбранную модель в разделе «Локальные модели».")
                    }
                    self.activity.append("Загрузка модели на этом Mac")
                    let settings = self.store.settings
                    let imageFiles = Self.imageFiles(files)
                    let hasImages = !imageFiles.isEmpty || self.messages.contains { !($0.localImages ?? []).isEmpty }
                    try await self.store.library.load(model, settings: settings, vision: hasImages)
                    try Task.checkCancellation()
                    let context = try await Self.localAttachmentText(files.filter { !imageFiles.contains($0) })
                    let savedImages = try await Self.preserveImages(imageFiles, directory: self.store.assets)
                    if !savedImages.isEmpty, let i = self.messages.lastIndex(where: { $0.role == "user" }) { self.messages[i].localImages = savedImages }
                    self.local = self.local ?? LocalConversation(title: self.title, modelID: selectedProvider)
                    if !context.isEmpty, let userIndex = self.messages.lastIndex(where: { $0.role == "user" }) { self.messages[userIndex].content = text + context }
                    var latest = self.messages.last(where: { $0.role == "user" }) ?? DesktopMessage(role: "user", content: text + context)
                    latest.content = text + context
                    var turns = try await Self.inferenceTurns(previous + [latest], directory: self.store.assets)
                    let memory = self.store.localMemoryContext
                    if !memory.isEmpty { turns.insert(.init(role: "system", content: "User-saved preferences and context. Use only when relevant:\n" + memory), at: 0) }
                    self.activity.append("Ответ обрабатывается локально")
                    if self.localToolsEnabled {
                        var toolTurns = [InferenceMessage(role: "system", content: LocalAction.instruction + "\nCurrent date: " + ISO8601DateFormatter().string(from: Date()))] + turns
                        for step in 0..<4 {
                            var answer = ""
                            for try await token in try await self.store.library.runtime.generate(messages: toolTurns, settings: settings) { try Task.checkCancellation(); answer += token }
                            guard self.generation == lease else { throw CancellationError() }
                            guard let action = LocalAction.parse(answer) else { self.replace(answer, at: answerID); break }
                            guard step < 3 else { throw DesktopError("Выполнено три действия. Продолжите отдельным сообщением.") }
                            self.localProposal = action
                            let approved = await withCheckedContinuation { self.localApproval = $0 }
                            try Task.checkCancellation()
                            guard self.generation == lease else { throw CancellationError() }
                            let result: String
                            if approved { self.activity.append(action.title); do { result = try await LocalActionExecutor.execute(action) } catch { result = "Действие не выполнено: " + error.localizedDescription } }
                            else { result = "Пользователь отклонил действие. Ничего не выполнено. Не повторяй запрос разрешения." }
                            self.activity.append(result)
                            toolTurns += [.init(role: "assistant", content: answer), .init(role: "user", content: "Результат действия на Mac: " + result)]
                        }
                    } else {
                        let stream = try await self.store.library.runtime.generate(messages: turns, settings: settings)
                        for try await token in stream {
                            try Task.checkCancellation()
                            guard self.generation == lease else { throw CancellationError() }
                            self.append(token, to: answerID)
                        }
                    }
                    if self.messages.last?.content.isEmpty == true { throw DesktopError("Модель завершила ответ без текста.") }
                } else {
                    guard let client = self.store.client else { throw DesktopError("Войдите в NIKA.") }
                    var uploaded = try await self.upload(files, client: client)
                    if uploaded.isEmpty, let edited {
                        uploaded = (edited.media ?? []).compactMap { item in
                            guard item.path.hasPrefix("api/files/") else { return nil }
                            return BFFUploadedAttachment(filename: item.name, mimeType: item.mime, kind: item.mime.hasPrefix("image/") ? "image" : "file", fileID: String(item.path.dropFirst(10)))
                        }
                    }
                    try Task.checkCancellation()
                    let chat: BFFRemoteChatInfo
                    if let existing = self.remote { chat = existing }
                    else if let prompt = self.agentPrompt, !prompt.isEmpty {
                        chat = try await DesktopAPI(client: client).request("chats", method: "POST", body: Self.personalityChatBody(title: self.title, name: self.agentName ?? "", prompt: prompt, ephemeral: self.incognito))
                    } else { chat = try await client.createChat(title: self.title, ephemeral: self.incognito) }
                    try Task.checkCancellation()
                    guard self.generation == lease else { throw CancellationError() }
                    self.remote = chat; self.selectedID = chat.id
                    try await client.ensureFreshAccessToken()
                    var subscription = try await client.openEventStream(chatID: chat.id)
                    defer { subscription.close() }
                    var lastEventAt = Date()
                    let timeout = Task {
                        while !Task.isCancelled {
                            try? await Task.sleep(for: .seconds(10))
                            if !Task.isCancelled, Date().timeIntervalSince(lastEventAt) > 90, self.browserRequest == nil { subscription.close(); lastEventAt = Date() }
                        }
                    }
                    defer { timeout.cancel() }
                    let receipt: BFFSentMessage
                    if let original {
                        receipt = try await DesktopAPI(client: client).request("chats/\(chat.id)/messages/\(original.id)/regenerate", method: "POST")
                    } else { receipt = try await client.sendMessage(content: text, chatID: chat.id,
                        options: .init(mode: self.imageMode ? .image : .chat, ephemeral: self.incognito, reasoning: self.reasoning,
                                       modelID: self.cloudModel.isEmpty ? nil : self.cloudModel, attachments: uploaded,
                                       executionMode: self.reasoning ? .complex : .light)) }
                    if Task.isCancelled || self.generation != lease { _ = try? await client.cancelTask(id: receipt.id); throw CancellationError() }
                    self.acceptedTask = receipt.id
                    var ended = false
                    for attempt in 0..<3 {
                        do {
                    for try await event in subscription.events {
                        try Task.checkCancellation()
                        guard self.generation == lease else { throw CancellationError() }
                        lastEventAt = Date()
                        if event.type == .browserStep, event.replay != true || event.taskID == receipt.id { self.browserEvents.append(event) }
                        if let question = BrowserQuestion(event: event, chatID: chat.id), question.taskID == receipt.id || question.rootTaskID == receipt.id { self.browserRequest = question; self.inspector = true }
                        guard event.taskID == receipt.id else { continue }
                        switch event.type {
                        case .token:
                            if event.replay == true { self.replace(event.data ?? "", at: answerID) }
                            else { self.append(event.data ?? "", to: answerID) }
                        case .status, .subtaskStatus, .toolStart, .toolResult, .browserStep:
                            if let value = event.statusText ?? event.toolName ?? event.nextGoal, self.activity.last != value { self.activity.append(value) }
                        case .error: throw CloudTurnFailure(message: event.data ?? "Сервис не смог завершить ответ.")
                        case .cancelled: throw CancellationError()
                        case .done: ended = true
                        default: break
                        }
                        if ended { break }
                    }
                        } catch is CancellationError { throw CancellationError() }
                          catch let error as CloudTurnFailure { throw error }
                          catch { if attempt == 2 { self.activity.append("Восстанавливаю ответ из истории") } }
                        if ended || attempt == 2 { break }
                        subscription.close()
                        try Task.checkCancellation()
                        self.activity.append("Восстанавливаю соединение…")
                        try await Task.sleep(for: .seconds(1))
                        try await client.ensureFreshAccessToken()
                        subscription = try await client.openEventStream(chatID: chat.id); lastEventAt = Date()
                    }
                    let snapshot = try await client.reconcileChat(chat, userContent: text, taskID: receipt.id, mode: self.imageMode ? .image : .chat,
                                                                  policy: .init(timeout: ended ? 20 : 45, pollInterval: 2))
                    guard self.generation == lease else { return }
                    self.messages = Self.project(snapshot.messages).filter { !(self.store.suppressedCloudMessages[chat.id] ?? []).contains($0.id) }; self.overlayVersions(chatID: chat.id, excluding: original == nil ? nil : self.messages.last(where: { $0.role == "user" })?.id)
                    await self.store.refresh()
                }
                if self.generation == lease {
                    if let original, let index = self.messages.lastIndex(where: { $0.role == "assistant" }) {
                        var variants = original.versions ?? [AnswerVariant(content: original.content, sources: original.sources, media: original.media)]
                        let answer = self.messages[index]
                        variants.append(AnswerVariant(content: answer.content, sources: answer.sources, media: answer.media))
                        variants = Array(variants.suffix(3)); self.messages[index].versions = variants; self.messages[index].selectedVersion = variants.count - 1
                        if !self.isLocal, let chatID = self.selectedID, let user = self.messages.last(where: { $0.role == "user" }) { self.store.cloudAnswerVersions[chatID, default: [:]][user.id] = self.messages[index] }
                    }
                    self.regenerationBaseline = nil
                    CompletionNotifications.finished()
                }
            } catch is CancellationError {
                if self.generation == lease { if let baseline = self.regenerationBaseline { self.messages = baseline; self.regenerationBaseline = nil }; self.activity.append("Ответ остановлен") }
            } catch {
                if self.generation == lease { if let baseline = self.regenerationBaseline { self.messages = baseline; self.regenerationBaseline = nil }; self.error = error.localizedDescription; if original == nil && self.draft.isEmpty { self.draft = text; self.attachments = files }; if self.messages.last?.content.isEmpty == true { self.messages.removeLast() } }
            }
        }
    }
    private func append(_ text: String, to id: String) { if let index = messages.firstIndex(where: { $0.id == id }) { messages[index].content += text } }
    private func replace(_ text: String, at id: String) { if let index = messages.firstIndex(where: { $0.id == id }) { messages[index].content = text } }
    func resolveLocalAction(_ approved: Bool) { localApproval?.resume(returning: approved); localApproval = nil; localProposal = nil }
    func stop() {
        resolveLocalAction(false)
        generation = UUID()
        if let baseline = regenerationBaseline { messages = baseline; regenerationBaseline = nil }
        saveLocal()
        loading = false
        task?.cancel(); task = nil
        if sending, isLocal { Task { await store.library.runtime.cancel() } }
        if let acceptedTask, let client = store.client { Task { do { _ = try await client.cancelTask(id: acceptedTask) } catch { store.error = error.localizedDescription } } }
        acceptedTask = nil; sending = false
    }
    func saveSkill(from message: DesktopMessage) async {
        guard let client = store.client, let taskID = message.taskID else { return }
        do {
            let _: EmptyResponse = try await DesktopAPI(client: client).request("skills", method: "POST", body: ["task_id": .string(taskID)])
            activity.append("Навык сохранён в разделе «Навыки → Мои»")
        } catch { self.error = error.localizedDescription }
    }
    nonisolated static func browserAnswerBody(requestID: String, answer: String) -> [String: BFFJSONValue] { ["request_id": .string(requestID), "answer": .string(answer)] }
    func answerBrowser(_ answer: String) async {
        guard let request = browserRequest, let client = store.client else { return }
        do {
            let _: EmptyResponse = try await DesktopAPI(client: client).request("chats/\(request.chatID)/tasks/\(request.taskID)/browser-input", method: "POST", body: Self.browserAnswerBody(requestID: request.id, answer: answer))
            if browserRequest?.id == request.id { browserRequest = nil }
            if !sending, let remote {
                let lease = generation; sending = true; acceptedTask = request.rootTaskID ?? request.taskID
                task = Task {
                    defer { if generation == lease { sending = false; acceptedTask = nil; task = nil } }
                    do {
                        let snapshot = try await client.reconcileChat(remote, userContent: answer, taskID: request.rootTaskID ?? request.taskID, policy: .init(timeout: 180, pollInterval: 2))
                        guard generation == lease else { return }; messages = Self.project(snapshot.messages)
                    } catch { if generation == lease { self.error = error.localizedDescription } }
                }
            }
        } catch { self.error = error.localizedDescription }
    }
    func beginEdit(_ message: DesktopMessage) {
        guard !sending, message.role == "user" else { return }
        editingMessageID = message.id; draft = message.content; attachments = []
    }
    func cancelEdit() { editingMessageID = nil; draft = "" }
    private func overlayVersions(chatID: String, excluding: String? = nil) {
        guard let groups = store.cloudAnswerVersions[chatID] else { return }
        for i in messages.indices where i > 0 && messages[i].role == "assistant" && messages[i - 1].role == "user" {
            if messages[i - 1].id != excluding, let saved = groups[messages[i - 1].id] {
                messages[i].versions = saved.versions; messages[i].selectedVersion = saved.selectedVersion
                messages[i].content = saved.content; messages[i].sources = saved.sources; messages[i].media = saved.media
            }
        }
    }
    func retry() {
        guard !sending else { return }
        if let last = messages.last, last.role == "assistant", messages.count >= 2 { send(regenerating: last) }
        else if let last = messages.last(where: { $0.role == "user" }) { draft = last.content; send() }
    }
    func selectVersion(messageID: String, index: Int) {
        guard !sending, let i = messages.firstIndex(where: { $0.id == messageID }), let versions = messages[i].versions, versions.indices.contains(index) else { return }
        let version = versions[index]; messages[i].content = version.content; messages[i].sources = version.sources; messages[i].media = version.media; messages[i].selectedVersion = index
        if !isLocal, let selectedID, i > 0, messages[i - 1].role == "user" { store.cloudAnswerVersions[selectedID, default: [:]][messages[i - 1].id] = messages[i] }
        saveLocal()
    }
    private func saveLocal() {
        guard isLocal, !messages.isEmpty else { return }
        var conversation = local ?? LocalConversation(title: title, modelID: providerID)
        conversation.messages = messages; conversation.updated = Date(); conversation.title = title
        local = conversation; selectedID = conversation.id; store.save(conversation)
    }
    private func upload(_ urls: [URL], client: BFFClient) async throws -> [BFFUploadedAttachment] {
        var uploaded: [BFFUploadedAttachment] = []
        for url in urls {
            let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
            guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 25_000_000 else { throw DesktopError("Файл больше 25 МБ. Выберите меньший файл.") }
            activity.append("Загрузка \(url.lastPathComponent)")
            let data = try await Task.detached { try Data(contentsOf: url) }.value
            uploaded.append(try await client.uploadAttachment(data: data, filename: url.lastPathComponent,
                                                              mimeType: UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"))
        }
        return uploaded
    }
    nonisolated static func localAttachmentText(_ urls: [URL]) async throws -> String {
        try await Task.detached {
            var text = ""
            for url in urls {
                let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 10_000_000 else { throw DesktopError("Для локального чтения выберите документ до 10 МБ.") }
                let content: String
                if url.pathExtension.lowercased() == "pdf" {
                    guard let value = PDFDocument(url: url)?.string, !value.isEmpty else { throw DesktopError("PDF не содержит доступного текста.") }; content = value
                } else {
                    guard let value = String(data: try Data(contentsOf: url), encoding: .utf8) else { throw DesktopError("Локальный чат принимает текстовые файлы и PDF с текстом. Изображения требуют облачной модели.") }; content = value
                }
                guard text.count + content.count < 40_000 else { throw DesktopError("Документ слишком длинный. Выберите фрагмент до 40 000 символов.") }
                text += "\n\n--- \(url.lastPathComponent) ---\n" + content
            }
            return text
        }.value
    }
}

private struct CloudTurnFailure: LocalizedError { let message: String; var errorDescription: String? { message } }
