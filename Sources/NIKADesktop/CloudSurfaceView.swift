import SwiftUI

struct CloudSurfaceView: View {
    let kind: String
    @ObservedObject var store: DesktopStore
    @ObservedObject var workspace: Workspace
    let openChat: () -> Void
    let signIn: () -> Void
    @State private var loading = false
    @State private var active: [ActiveDesktopChat] = []
    @State private var goals: [DesktopGoal] = []
    @State private var memories: [DesktopMemory] = []
    @State private var stepGoal: String?
    @State private var failure: String?
    @State private var agents: [BFFAgent] = []
    @State private var agentPresets = false
    @State private var schedules: [BFFSchedule] = []
    @State private var news: [BFFPersonalNewsItem] = []
    @State private var events: [BFFCalendarEvent] = []
    @State private var tools: [BFFToolStatus] = []
    @State private var skills: [BFFTaskScriptBrief] = []
    @State private var notifications: [BFFNotification] = []
    @State private var memory: [String: BFFJSONValue] = [:]
    @State private var editor = false
    @State private var editedAgent: BFFAgent?
    @State private var editedMemory: DesktopMemory?
    @State private var editedGoal: DesktopGoal?
    @State private var editedStep: DesktopGoal.Step?
    @State private var hasDate = false
    @State private var name = ""
    @State private var instructions = ""
    @State private var time = Date()
    @State private var cadence = "daily"
    @State private var weekday = 0
    @State private var search = ""
    @State private var skillShelf = "catalog"
    @State private var publishSkill: BFFTaskScriptBrief?
    @State private var mutation = false
    var body: some View {
        Group {
            if store.client == nil {
                VStack { EmptyWorkspace(symbol: "cloud", title: "Ваше пространство NIKA", detail: "Войдите, чтобы открыть \(DesktopWindow.title(kind).lowercased()) из вашего аккаунта."); Button("Войти", action: signIn).buttonStyle(.borderedProminent).padding(.bottom, 80) }
            } else {
                VStack(spacing: 0) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 8) { Text(DesktopWindow.title(kind)).font(.system(size: 30, weight: .medium, design: .rounded)); Text(subtitle).foregroundStyle(.secondary) }
                        Spacer()
                        if ["agents", "schedules", "goals", "memory"].contains(kind) { Button { name = ""; instructions = ""; editedAgent = nil; editedMemory = nil; editedGoal = nil; editedStep = nil; hasDate = false; stepGoal = nil; editor = true } label: { Label("Создать", systemImage: "plus") }.buttonStyle(.borderedProminent) }
                        Button { Task { await refresh() } } label: { Image(systemName: "arrow.clockwise") }.help("Обновить")
                    }.padding(32)
                    if loading { ProgressView("Загрузка…").frame(maxWidth: .infinity, maxHeight: .infinity) }
                    else if let failure {
                        VStack(spacing: 16) { EmptyWorkspace(symbol: "wifi.exclamationmark", title: "Не удалось обновить", detail: failure); Button("Повторить") { Task { await refresh() } }.buttonStyle(.bordered).padding(.bottom, 60) }
                    } else {
                        ScrollView { VStack(alignment: .leading, spacing: 16) { content }.frame(maxWidth: 880).padding(.horizontal, 32).padding(.bottom, 32).frame(maxWidth: .infinity) }
                    }
                }
            }
        }.task(id: "\(kind)-\(store.login?.session.clientID ?? "")") { await refresh() }
            .sheet(isPresented: $editor) { editorView }
            .onChange(of: agentPresets) { _, _ in Task { await refresh() } }
            .onChange(of: skillShelf) { _, _ in Task { await refresh() } }
            .confirmationDialog("Опубликовать навык для всех пользователей NIKA?", isPresented: Binding(get: { publishSkill != nil }, set: { if !$0 { publishSkill = nil } }), titleVisibility: .visible) {
                Button("Опубликовать") { if let skill = publishSkill { perform { client in let _: EmptyResponse = try await DesktopAPI(client: client).request("skills/\(skill.id)/publish", method: "POST") } }; publishSkill = nil }
            } message: { Text("Проверьте, что описание навыка не содержит личной информации.") }
    }
    private var subtitle: String {
        ["today": "События и новости, к которым стоит вернуться.", "agents": "Сохранённые инструкции для повторяющейся работы.", "schedules": "Поручения NIKA и результаты последних запусков.", "memory": "Контекст, который NIKA хранит в вашем аккаунте.", "skills": "Готовые способы решить задачу.", "tools": "Возможности, доступные облачному агенту.", "notifications": "Результаты и обновления из вашего аккаунта."][kind] ?? ""
    }
    @ViewBuilder private var content: some View {
        switch kind {
        case "tasks":
            if active.isEmpty { empty("Нет активных задач", "Задачи из ваших разговоров появятся здесь.") }
            ForEach(active) { item in card(item.active_task_text ?? item.title, symbol: "checklist") {
                Text(item.status).foregroundStyle(.secondary)
                if item.tray_status != "working" { Button("Убрать из списка") { perform { client in let _: EmptyResponse = try await DesktopAPI(client: client).request("chats/\(item.id)/tray/dismiss", method: "POST") } } }
                if item.tray_status == "working" { Button("Остановить задачу", role: .destructive) { perform { _ = try await $0.cancelChat(id: item.id) } }.disabled(mutation) }
                Button("Открыть разговор") { Task { do { guard let client = store.client else { return }; await workspace.open(try await client.fetchChatInfo(id: item.id)); openChat() } catch { failure = error.localizedDescription } } }
            } }
        case "goals":
            if goals.isEmpty { empty("Что для вас важно?", "Создайте цель и разбейте её на небольшие шаги.") }
            ForEach(goals) { goal in card(goal.title, symbol: "scope") {
                if !goal.note.isEmpty { Text(goal.note).foregroundStyle(.secondary) }; if let date = goal.targetDate, !date.isEmpty { Label(date, systemImage: "calendar").font(.caption).foregroundStyle(.secondary) }
                ForEach(goal.steps) { step in
                    HStack {
                    Button { perform { _ = try await $0.updateMilestone(aspirationID: goal.id, id: step.id, ["status": .string(step.done ? "upcoming" : "done")]) } } label: {
                        Label(step.title, systemImage: step.done ? "checkmark.circle.fill" : "circle").strikethrough(step.done)
                    }.buttonStyle(.plain).disabled(mutation)
                    Spacer()
                    Button { stepGoal = goal.id; editedStep = step; name = step.title; instructions = ""; hasDate = step.scheduledAt?.isEmpty == false; time = step.scheduledAt.flatMap { ISO8601DateFormatter().date(from: $0) } ?? Date(); editor = true } label: { Image(systemName: "pencil") }.buttonStyle(.plain).help("Изменить шаг")
                    Button(role: .destructive) { perform { try await $0.deleteMilestone(aspirationID: goal.id, id: step.id) } } label: { Image(systemName: "trash") }.buttonStyle(.plain).help("Удалить шаг")
                    }
                    if let scheduled = step.scheduledAt, !scheduled.isEmpty { Text(scheduled).font(.caption).foregroundStyle(.secondary) }
                }
                HStack {
                    Button("Изменить цель") { editedGoal = goal; stepGoal = nil; hasDate = goal.targetDate?.isEmpty == false; time = goal.targetDate.flatMap { Self.dayFormatter.date(from: $0) } ?? Date(); name = goal.title; instructions = goal.note; editor = true }
                    Button("Добавить шаг") { stepGoal = goal.id; editedStep = nil; hasDate = false; name = ""; instructions = ""; editor = true }
                    Spacer(); Button("Удалить цель", role: .destructive) { perform { try await $0.deleteAspiration(id: goal.id) } }
                }
            } }
        case "agents":
            Picker("Агенты", selection: $agentPresets) { Text("Мои агенты").tag(false); Text("Каталог NIKA").tag(true) }.pickerStyle(.segmented)
            if agents.isEmpty { empty("Пока нет агентов", "Сохраните инструкции для задачи, к которой возвращаетесь.") }
            ForEach(agents) { agent in card(agent.name, symbol: "sparkles") {
                Text(agent.systemPrompt).foregroundStyle(.secondary).lineLimit(5)
                HStack {
                    Button("Начать разговор") { workspace.newChat(provider: "cloud"); workspace.agentID = agent.id; workspace.agentName = agent.name; workspace.agentPrompt = agent.systemPrompt; openChat() }
                    if !agentPresets {
                    Button("Изменить") { editedAgent = agent; name = agent.name; instructions = agent.systemPrompt; editor = true }
                    Spacer()
                    Button("Удалить", role: .destructive) { perform { try await $0.deleteAgent(id: agent.id) } }
                    } else { Button("В мои агенты") { perform { _ = try await $0.createAgent(name: agent.name, systemPrompt: agent.systemPrompt) } } }
                }.disabled(mutation)
            } }
        case "schedules":
            if schedules.isEmpty { empty("Пока нет расписаний", "Поручите NIKA повторяющуюся задачу. Она появится здесь.") }
            ForEach(schedules) { schedule in card(schedule.text, symbol: schedule.active ? "calendar.badge.clock" : "pause.circle") {
                Text("\(schedule.cronExpression ?? "Однократно") · \(schedule.timeZoneIdentifier)").font(.caption).foregroundStyle(.secondary)
                if let next = schedule.nextFireAt { LabeledContent("Следующий запуск", value: next).font(.callout) }
                if let result = schedule.latestResult { MarkdownView(text: result) }
                if let error = schedule.latestError { Text(error).foregroundStyle(.red) }
                HStack {
                    Button(schedule.active ? "Приостановить" : "Возобновить") { perform { client in if schedule.active { try await client.deactivateSchedule(id: schedule.id) } else { try await client.activateSchedule(id: schedule.id) } } }
                    Spacer(); Button("Удалить", role: .destructive) { perform { try await $0.deleteSchedule(id: schedule.id) } }
                }.disabled(mutation)
            } }
        case "today":
            if events.isEmpty && news.isEmpty { empty("Сегодня спокойно", "Новые события и персональные новости появятся здесь после обновления аккаунта.") }
            ForEach(events) { event in card(event.title, symbol: "calendar") { Text(event.start).foregroundStyle(.secondary); if let location = event.location { Label(location, systemImage: "mappin") } } }
            ForEach(news) { item in card(item.title, symbol: "newspaper") {
                if let body = item.body { Text(body).lineLimit(8).foregroundStyle(.secondary) }
                HStack {
                    if let value = item.url, let url = URL(string: value), ["http", "https"].contains(url.scheme ?? "") { Link("Источник ↗", destination: url) }
                    Spacer()
                    Button("Обсудить с NIKA") { Task { do { guard let client = store.client else { return }; let receipt = try await client.discussNews(id: item.id); let chat = try await client.fetchChatInfo(id: receipt.chatID); await workspace.open(chat); openChat() } catch { failure = error.localizedDescription } } }
                }
            } }
        case "tools":
            TextField("Найти инструмент", text: $search).textFieldStyle(.roundedBorder)
            if tools.isEmpty { empty("Каталог недоступен", "Сервер пока не вернул инструменты. Это не означает, что инструментов нет.") }
            ForEach(tools.filter { search.isEmpty || $0.displayName.localizedCaseInsensitiveContains(search) }, id: \.name) { tool in card(tool.displayName, symbol: "puzzlepiece.extension") {
                Text(tool.description).foregroundStyle(.secondary)
                Label(tool.isAvailable ? "Доступен облачному агенту" : "Недоступен", systemImage: tool.isAvailable ? "checkmark.circle" : "minus.circle").font(.caption).foregroundStyle(tool.isAvailable ? .green : .secondary)
            } }
        case "skills":
            Picker("Навыки", selection: $skillShelf) { Text("Каталог").tag("catalog"); Text("Мои").tag("own"); Text("Общие").tag("public") }.pickerStyle(.segmented)
            if skills.isEmpty { empty("Навыки ещё не появились", "Сохранённые сценарии из NIKA появятся после синхронизации.") }
            ForEach(skills) { skill in card(skill.name, symbol: "square.stack.3d.up") {
                Text(skill.description ?? "").foregroundStyle(.secondary)
                if let prompt = skill.promptTemplate ?? skill.generalizedQuery { Button("Использовать") { workspace.newChat(provider: "cloud"); workspace.draft = prompt; openChat() } }
                if skillShelf == "own" {
                    HStack {
                        if skill.visibility != "public" { Button("Опубликовать…") { publishSkill = skill } }
                        Button("Удалить", role: .destructive) { perform { client in let _: EmptyResponse = try await DesktopAPI(client: client).request("skills/\(skill.id)", method: "DELETE") } }
                    }.disabled(mutation)
                }
            } }
        case "notifications":
            if notifications.isEmpty { empty("Всё прочитано", "Здесь будут результаты поручений и обновления.") }
            ForEach(notifications) { notification in card(notification.text, symbol: notification.read ? "bell" : "bell.badge") {
                Text(notification.createdAt).font(.caption).foregroundStyle(.secondary)
                HStack {
                    if !notification.read { Button("Отметить прочитанным") { perform { try await $0.markNotificationRead(id: notification.id) } } }
                    if let chatID = notification.chatID { Button("Открыть разговор") { Task { do { guard let client = store.client else { return }; await workspace.open(try await client.fetchChatInfo(id: chatID)); openChat() } catch { failure = error.localizedDescription } } } }
            } } }
        case "memory":
            if memories.isEmpty && memory.isEmpty { empty("Начнём знакомиться", "Сохраните то, что NIKA должна учитывать в ответах.") }
            ForEach(memories.sorted { $0.isPinned && !$1.isPinned }) { item in card(item.title, symbol: "brain") {
                Text(item.detail).foregroundStyle(.secondary)
                HStack {
                    Button("Изменить") { editedMemory = item; name = item.title; instructions = item.detail; editor = true }
                    Button(item.isPinned ? "Открепить" : "Закрепить") { perform { client in
                        var updated = memories; if let i = updated.firstIndex(where: { $0.id == item.id }) { updated[i].isPinned.toggle(); updated[i].updatedAt = Date() }
                        _ = try await client.updateUserInfo(["memories": try JSONDecoder().decode(BFFJSONValue.self, from: JSONEncoder().encode(updated))])
                    } }
                }
                Button("Удалить", role: .destructive) { perform { client in
                    let updated = memories.filter { $0.id != item.id }
                    let value = try JSONDecoder().decode(BFFJSONValue.self, from: JSONEncoder().encode(updated))
                    _ = try await client.updateUserInfo(["memories": value])
                } }
            } }
            ForEach(memory.keys.sorted(), id: \.self) { key in card(key.replacingOccurrences(of: "_", with: " ").capitalized, symbol: "brain") { Text(memory[key].map(Self.readable) ?? "").foregroundStyle(.secondary).textSelection(.enabled) } }
        default: EmptyView()
        }
    }
    private func empty(_ title: String, _ detail: String) -> some View { EmptyWorkspace(symbol: "tray", title: title, detail: detail).frame(height: 260) }
    private func card<Content: View>(_ title: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) { Label(title, systemImage: symbol).font(.headline); content() }.frame(maxWidth: .infinity, alignment: .leading).padding(22).nikaGlass(radius: 18)
    }
    private func refresh() async {
        guard let client = store.client else { agents = []; schedules = []; memory = [:]; news = []; return }
        loading = true; failure = nil; defer { loading = false }
        do {
            switch kind {
            case "tasks": active = try await DesktopAPI(client: client).activeChats()
            case "goals":
                let document = try await client.fetchUserInfo()
                if case .array(let values) = document["aspirations"] { goals = values.compactMap(DesktopGoal.decode) } else { goals = [] }
            case "agents":
                if agentPresets { agents = try await DesktopAPI(client: client).request("agents/presets") }
                else { agents = try await client.fetchAgents() }
            case "schedules": schedules = try await client.fetchSchedules(activeOnly: false)
            case "today":
                async let n = client.fetchPersonalNews(); async let e = client.fetchCalendarEvents(from: Calendar.current.startOfDay(for: Date()), to: Date().addingTimeInterval(86_400))
                (news, events) = try await (n, e)
            case "tools": tools = try await client.toolsStatus()
            case "skills":
                if skillShelf == "own" { skills = try await client.fetchOwnSkills() }
                else if skillShelf == "public" { skills = try await client.fetchPublicSkills() }
                else { skills = try await client.fetchCatalogueSkills() }
            case "memory":
                let document = try await client.fetchUserInfo()
                if let value = document["memories"] { memories = try JSONDecoder().decode([DesktopMemory].self, from: JSONEncoder().encode(value)) } else { memories = [] }
                memory = document.filter { ["facts", "insights", "contexts", "motives", "values"].contains($0.key) }
            case "notifications": notifications = try await client.fetchNotifications()
            default: break
            }
        } catch is CancellationError { } catch { failure = error.localizedDescription }
    }
    private func perform(_ action: @escaping (BFFClient) async throws -> Void) {
        guard let client = store.client else { return }
        mutation = true
        Task { defer { mutation = false }; do { try await action(client); await refresh() } catch { failure = error.localizedDescription } }
    }
    private var editorTitle: String {
        if kind == "goals" { return stepGoal == nil ? "Новая цель" : "Новый шаг" }
        if kind == "memory" { return "Запомнить" }
        if kind == "agents" { return editedAgent == nil ? "Новый агент" : "Изменить агента" }
        return "Новое поручение"
    }
    private var editorView: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(editorTitle).font(.title2)
            ScrollView { VStack(alignment: .leading, spacing: 16) {
            if ["agents", "goals", "memory"].contains(kind) { TextField("Название", text: $name).textFieldStyle(.roundedBorder) }
            Text(kind == "agents" ? "Инструкции агенту" : kind == "schedules" ? "Что нужно делать" : "Описание").font(.headline)
            DesktopTextArea(text: $instructions, label: kind == "agents" ? "Инструкции агенту" : "Описание")
            if kind == "goals" {
                Toggle("Указать дату", isOn: $hasDate)
                if hasDate { DatePicker("Когда", selection: $time, displayedComponents: stepGoal == nil ? [.date] : [.date, .hourAndMinute]) }
            }
            if kind == "schedules" {
                Picker("Повторять", selection: $cadence) { Text("Каждый день").tag("daily"); Text("По будням").tag("weekdays"); Text("Еженедельно").tag("weekly") }
                if cadence == "weekly" { Picker("День", selection: $weekday) { ForEach(Array(["Понедельник", "Вторник", "Среда", "Четверг", "Пятница", "Суббота", "Воскресенье"].enumerated()), id: \.offset) { index, title in Text(title).tag(index) } } }
                DatePicker("Время", selection: $time, displayedComponents: .hourAndMinute)
                Text("Часовой пояс берётся из профиля NIKA на сервере").font(.caption).foregroundStyle(.secondary)
            }
            }.padding(.vertical, 4) }.scrollIndicators(.visible)
            Divider()
            HStack {
                Button("Отмена") { editor = false }; Spacer()
                Button("Сохранить") {
                    perform { client in
                        if kind == "agents" {
                            if let editedAgent { _ = try await client.updateAgent(id: editedAgent.id, name: name, systemPrompt: instructions) }
                            else { _ = try await client.createAgent(name: name, systemPrompt: instructions) }
                        } else if kind == "goals" {
                            if let stepGoal {
                                var fields: [String: BFFJSONValue] = ["title": .string(name), "target_date": .string(hasDate ? Self.dayFormatter.string(from: time) : ""), "scheduled_at": .string(hasDate ? ISO8601DateFormatter().string(from: time) : "")]
                                if let editedStep { _ = try await client.updateMilestone(aspirationID: stepGoal, id: editedStep.id, fields) }
                                else { fields["status"] = .string("upcoming"); _ = try await client.createMilestone(aspirationID: stepGoal, fields) }
                            }
                            else if let editedGoal { _ = try await client.updateAspiration(id: editedGoal.id, ["description": .string(name), "note": .string(instructions), "target_date": .string(hasDate ? Self.dayFormatter.string(from: time) : "")]) }
                            else { _ = try await client.createAspiration(["description": .string(name), "note": .string(instructions), "target_date": .string(hasDate ? Self.dayFormatter.string(from: time) : ""), "status": .string("active")]) }
                        } else if kind == "memory" {
                            var updated = memories
                            if var item = editedMemory, let index = updated.firstIndex(where: { $0.id == item.id }) { item.title = name; item.detail = instructions; item.updatedAt = Date(); updated[index] = item }
                            else { updated.append(DesktopMemory(title: name, detail: instructions)) }
                            let value = try JSONDecoder().decode(BFFJSONValue.self, from: JSONEncoder().encode(updated))
                            _ = try await client.updateUserInfo(["memories": value])
                        } else {
                            let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
                            let draft = NIKAErrandDraft(instruction: instructions, cadence: cadence == "daily" ? .daily : cadence == "weekly" ? .weekly(weekday: weekday) : .weekdays,
                                                       localTime: try .init(hour: parts.hour ?? 9, minute: parts.minute ?? 0), creationSource: .managementEntry)
                            _ = try await client.createSchedule(.init(draft: draft))
                        }
                        editor = false
                    }
                }.buttonStyle(.borderedProminent).disabled((kind != "goals" && instructions.isEmpty) || (["agents", "goals", "memory"].contains(kind) && name.isEmpty) || mutation)
            }
        }.padding(28).frame(width: 520, height: DesktopFormLayout.height(570))
    }
    private static var dayFormatter: DateFormatter { let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"; return formatter }
    private static func readable(_ value: BFFJSONValue) -> String {
        switch value {
        case .string(let string): return string
        case .array(let values): return values.map(readable).joined(separator: "\n\n")
        case .object(let object): return object.keys.sorted().filter { !["id", "client_id", "created_at", "updated_at"].contains($0) }.map { key in "\(key.replacingOccurrences(of: "_", with: " ")): \(readable(object[key]!))" }.joined(separator: "\n")
        case .number(let number): return String(number)
        case .bool(let boolean): return boolean ? "Да" : "Нет"
        case .null: return "—"
        }
    }
}
