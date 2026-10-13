import SwiftUI
import UniformTypeIdentifiers
import AppKit
import Combine

struct DesktopWindow: View {
    @ObservedObject var store: DesktopStore
    @StateObject private var workspace: Workspace
    @SceneStorage("desktop.workspace.v2") private var persistedWorkspace = ""
    @State private var restored = false
    @SceneStorage("desktop.destination") private var destination = "chat"
    @State private var search = ""
    @FocusState private var searchFocused: Bool
    @State private var searchHits: [DesktopSearchHit] = []
    @State private var searchError: String?
    @State private var renameID: String?
    @State private var renameText = ""
    @State private var signIn = false
    @State private var columns = NavigationSplitViewVisibility.all
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    init(store: DesktopStore) { self.store = store; _workspace = StateObject(wrappedValue: Workspace(store: store)) }
    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            sidebar
        } detail: {
            Group {
                if destination == "chat" { ConversationView(workspace: workspace, showModels: { destination = "models" }, signIn: { signIn = true }) }
                else if destination == "bots" { PersonalBotsView(store: store, signIn: { signIn = true }).id(store.login?.session.clientID) }
                else if destination == "memory" { MemoryWorkspace(store: store, workspace: workspace, openChat: { destination = "chat" }, signIn: { signIn = true }) }
                else if destination == "calendar" { CalendarWorkspace() }
                else if destination == "models" { ModelLibraryView(library: store.library, store: store) { model in workspace.newChat(provider: model.id); destination = "chat" } }
                else if destination == "integrations" { IntegrationsView(store: store, signIn: { signIn = true }).id(store.login?.session.clientID) }
                else if destination == "media" { MediaView(store: store, workspace: workspace, openChat: { destination = "chat" }, signIn: { signIn = true }).id(store.login?.session.clientID) }
                else { CloudSurfaceView(kind: destination, store: store, workspace: workspace, openChat: { destination = "chat" }, signIn: { signIn = true }).id("\(destination)-\(store.login?.session.clientID ?? "")") }
            }.background { AuroraCanvas() }
        }
        .navigationTitle(destination == "chat" ? workspace.title : Self.title(destination))
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if destination == "chat" {
                    Button { workspace.newChat() } label: { Image(systemName: "square.and.pencil") }.help("Новый разговор")
                    ShareLink(item: workspace.messages.map { "\($0.role == "user" ? "Вы" : "NIKA"):\n\($0.content)" }.joined(separator: "\n\n")) { Image(systemName: "square.and.arrow.up") }.help("Поделиться разговором").disabled(workspace.messages.isEmpty)
                    Button { workspace.inspector.toggle() } label: { Image(systemName: "sidebar.right") }.help("Контекст разговора")
                }
            }
        }
        .frame(minWidth: 820, minHeight: 600)
        .task(id: search + (store.login?.session.clientID ?? "")) {
            searchHits = []; searchError = nil
            guard search.trimmingCharacters(in: .whitespaces).count >= 2, let client = store.client else { return }
            do {
                try await Task.sleep(for: .milliseconds(300))
                let hits: [DesktopSearchHit] = try await DesktopAPI(client: client).request("chats/search", query: [.init(name: "q", value: search), .init(name: "limit", value: "30")])
                try Task.checkCancellation(); searchHits = hits
            } catch is CancellationError { } catch { searchError = "Поиск по сообщениям недоступен. Показаны совпадения в названиях." }
        }
        .alert("Название разговора", isPresented: Binding(get: { renameID != nil }, set: { if !$0 { renameID = nil } })) {
            TextField("Название", text: $renameText)
            Button("Сохранить") { if let id = renameID { Task { do { _ = try await store.client?.renameChat(id: id, title: renameText); if workspace.selectedID == id { workspace.title = renameText }; await store.refresh() } catch { store.error = error.localizedDescription } } }; renameID = nil }
            Button("Отмена", role: .cancel) { renameID = nil }
        }
        .sheet(isPresented: $signIn) { AuthenticationView(store: store) }
        .alert("NIKA", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("Понятно") { store.error = nil } } message: { Text(store.error ?? "") }
        .focusedSceneValue(\.workspace, workspace)
        .onChange(of: workspace.requestedDestination) { _, value in if let value { destination = value; workspace.requestedDestination = nil } }
        .onChange(of: workspace.focusSearch) { _, _ in columns = .all; searchFocused = true }
        .task {
            guard !restored else { return }
            let saved = persistedWorkspace
            await store.restoreSession(); await store.refresh()
            if let data = saved.data(using: .utf8), let state = try? JSONDecoder().decode(WorkspaceSnapshot.self, from: data) { await workspace.restore(state) }
            restored = true
        }
        .onReceive(workspace.objectWillChange.debounce(for: .milliseconds(250), scheduler: RunLoop.main)) { _ in
            guard restored, !workspace.incognito else { return }
            if let data = try? JSONEncoder().encode(workspace.snapshot()), let text = String(data: data, encoding: .utf8) { persistedWorkspace = text }
        }
        .onOpenURL { url in if url.scheme == "nika-desktop", url.host == "ask" { destination = "chat"; workspace.newChat(); workspace.draft = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "text" })?.value ?? "" } }
    }
    private var sidebar: some View {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    NikaMark(size: 34)
                    Text("NIKA").font(.system(size: 20, weight: .semibold, design: .rounded)).tracking(2)
                    Spacer()
                    Button { workspace.newChat(); destination = "chat" } label: { Image(systemName: "square.and.pencil") }
                        .buttonStyle(.plain).help("Новый разговор ⌘N")
                }.padding(.horizontal, 20).padding(.vertical, 22)
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Найти разговор", text: $search).textFieldStyle(.plain).focused($searchFocused)
                    if !search.isEmpty { Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(.secondary) }
                }.padding(9).nikaGlass(radius: 10).padding(.horizontal, 12).padding(.bottom, 10)
                List {
                    Section {
                        nav("chat", "Разговор", "bubble.left.and.bubble.right")
                        nav("bots", "Ботсы", "person.2")
                        nav("today", "Сегодня", "sun.max")
                        nav("calendar", "Календарь Mac", "calendar")
                        nav("models", "Локальные модели", "desktopcomputer")
                    }
                    Section("Рабочее пространство") {
                        nav("tasks", "Задачи", "checklist")
                        nav("goals", "Цели", "scope")
                        nav("agents", "Агенты", "sparkles")
                        nav("schedules", "Расписания", "calendar.badge.clock")
                        nav("memory", "Память", "brain")
                        nav("skills", "Навыки", "square.stack.3d.up")
                        nav("tools", "Инструменты", "puzzlepiece.extension")
                        nav("integrations", "Подключения", "link")
                        nav("media", "Медиа", "photo.on.rectangle")
                        nav("notifications", "Уведомления", "bell")
                    }
                    if !searchHits.isEmpty {
                        Section("В сообщениях") {
                            ForEach(searchHits) { hit in
                                Button { Task { do { guard let client = store.client else { return }; await workspace.open(try await client.fetchChatInfo(id: hit.chat_id)); destination = "chat" } catch { store.error = error.localizedDescription } } } label: {
                                    Text(hit.snippet).font(.caption).lineLimit(3)
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                    if let searchError { Text(searchError).font(.caption).foregroundStyle(.secondary) }
                    Section("На этом Mac") {
                        ForEach(store.localChats.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.messages.contains(where: { $0.content.localizedCaseInsensitiveContains(search) }) }.sorted { $0.updated > $1.updated }) { chat in
                            Button { workspace.open(chat); destination = "chat" } label: {
                                Label(chat.title, systemImage: "lock").lineLimit(1)
                            }.buttonStyle(.plain).contextMenu {
                                Button("Удалить разговор", role: .destructive) { store.deleteLocal(chat.id); if workspace.selectedID == chat.id { workspace.newChat() } }
                            }
                        }
                    }
                    if store.login != nil {
                        Section("Облачные разговоры") {
                            ForEach(store.cloudChats.filter { search.isEmpty || $0.displayTitle.localizedCaseInsensitiveContains(search) }) { chat in
                                Button { destination = "chat"; Task { await workspace.open(chat) } } label: {
                                    Label(chat.displayTitle, systemImage: chat.isPinned == true ? "pin" : "bubble.left").lineLimit(1)
                                }.buttonStyle(.plain).contextMenu {
                                    Button("Переименовать") { renameID = chat.id; renameText = chat.displayTitle }
                                    Button(chat.isStarred == true ? "Убрать из избранного" : "В избранное") { Task { do { _ = try await store.client?.setChatStarred(id: chat.id, isStarred: chat.isStarred != true); await store.refresh() } catch { store.error = error.localizedDescription } } }
                                    Button(chat.isPinned == true ? "Открепить" : "Закрепить") { Task { do { _ = try await store.client?.setChatPinned(id: chat.id, isPinned: chat.isPinned != true); await store.refresh() } catch { store.error = error.localizedDescription } } }
                                    Button("Удалить разговор", role: .destructive) { Task { do { try await store.client?.deleteChat(id: chat.id); await store.refresh(); if workspace.selectedID == chat.id { workspace.newChat() } } catch { store.error = error.localizedDescription } } }
                                }
                            }
                        }
                    }
                }.listStyle(.sidebar).scrollContentBackground(.hidden)
                Divider()
                HStack {
                    Image(systemName: store.login == nil ? "person.crop.circle" : "person.crop.circle.fill").font(.title2).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(store.login?.session.username ?? "Ваше пространство").font(.subheadline.weight(.medium)).lineLimit(1)
                        Text(store.login == nil ? "Локально · без аккаунта" : "Аккаунт NIKA").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if store.login == nil { Button { signIn = true } label: { Image(systemName: "arrow.right.circle") }.buttonStyle(.plain).help("Войти") }
                    else { SettingsLink { Image(systemName: "gearshape") }.buttonStyle(.plain) }
                }.padding(16)
            }.background { DesktopStyle.canvas.opacity(0.6) }.navigationSplitViewColumnWidth(min: 210, ideal: 245, max: 300)
    }
    private func nav(_ id: String, _ title: String, _ symbol: String) -> some View {
        Button { destination = id } label: {
            Label(title, systemImage: symbol).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
                .foregroundStyle(destination == id ? Color.accentColor : Color.primary)
        }.buttonStyle(.plain).listRowBackground(destination == id ? Color.accentColor.opacity(0.09) : Color.clear)
    }
    static func title(_ id: String) -> String {
        ["bots": "Ботсы", "calendar": "Календарь Mac", "tasks": "Задачи", "goals": "Цели", "integrations": "Подключения", "media": "Медиа", "today": "Сегодня", "models": "Локальные модели", "agents": "Агенты", "schedules": "Расписания", "memory": "Память", "tools": "Инструменты", "skills": "Навыки", "notifications": "Уведомления"][id] ?? "NIKA"
    }
}

struct ConversationView: View {
    @ObservedObject var workspace: Workspace
    @ObservedObject private var library: ModelLibrary
    let personalAgentMode: Bool
    let showModels: () -> Void
    let signIn: () -> Void
    @StateObject private var voice = DesktopVoice()
    @State private var picker = false
    @State private var camera = false
        @State private var dropping = false
    @FocusState private var focused: Bool
    init(workspace: Workspace, showModels: @escaping () -> Void, signIn: @escaping () -> Void, personalAgentMode: Bool = false) {
        self.personalAgentMode = personalAgentMode
        self.workspace = workspace; self.showModels = showModels; self.signIn = signIn
        _library = ObservedObject(wrappedValue: workspace.store.library)
    }
    var body: some View {
        GeometryReader { geometry in
        let inset: CGFloat = geometry.size.width < 600 ? 16 : 28
        let column = max(1, min(DesktopStyle.readingWidth, geometry.size.width - inset * 2))
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: workspace.isLocal ? "lock.shield" : "cloud")
                Text(workspace.isLocal ? "На этом Mac · без отправки в облако" : "NIKA Cloud · обработка на сервере")
                if let name = workspace.agentName { Text("· " + name) }
                Spacer()
                if workspace.sending { ProgressView().controlSize(.small); Text("NIKA отвечает") }
            }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 28).padding(.vertical, 12)
            Divider().opacity(0.5)
            if workspace.loading { ProgressView("Открываем разговор…").frame(maxWidth: .infinity, maxHeight: .infinity) }
            else if workspace.messages.isEmpty { GeometryReader { geometry in ScrollView { welcome(compact: geometry.size.height < 520).frame(minHeight: geometry.size.height) } } }
            else { transcript(width: column) }
            composer(compact: geometry.size.height < 600).frame(width: column).padding(.top, 6).padding(.bottom, 8).frame(maxWidth: .infinity)
        }
        .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background { AuroraCanvas(level: voice.inputLevel, listening: voice.recording) }
        .inspector(isPresented: $workspace.inspector) {
            VStack(alignment: .leading, spacing: 20) {
                Text("Контекст").font(.title2.weight(.semibold))
                Label(workspace.isLocal ? "Только на этом Mac" : "Облачный разговор", systemImage: workspace.isLocal ? "lock.shield" : "cloud")
                Text(workspace.isLocal ? "Текст и файлы этого разговора не синхронизируются и не отправляются в NIKA Cloud." : "Запросы и вложения отправляются в ваш аккаунт NIKA.").font(.callout).foregroundStyle(.secondary)
                Divider()
                Text("Действия NIKA").font(.headline)
                if workspace.activity.isEmpty { Text("Здесь появятся действия во время ответа.").foregroundStyle(.secondary) }
                ScrollView { VStack(alignment: .leading, spacing: 14) { BrowserActivityView(workspace: workspace); ForEach(Array(workspace.activity.enumerated()), id: \.offset) { _, activity in Label(activity, systemImage: "circle.dotted").font(.callout) } } }
                Spacer()
            }.padding(24).inspectorColumnWidth(min: 240, ideal: 280, max: 360)
        }
        .sheet(item: Binding(get: { workspace.voicePanel ? nil : workspace.localProposal }, set: { workspace.localProposal = $0 }), onDismiss: { workspace.resolveLocalAction(false) }) { action in LocalActionConfirmation(action: action, resolve: workspace.resolveLocalAction) }
        .sheet(isPresented: $workspace.modelPicker) { ConversationModelPicker(workspace: workspace, library: library) }
        .sheet(isPresented: $workspace.voicePanel) { VoiceConversationView(workspace: workspace) }
        .sheet(isPresented: $camera) { CameraSheet { workspace.add([$0]) } }
        .fileImporter(isPresented: $picker, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            do { workspace.add(try result.get()) } catch { workspace.error = error.localizedDescription }
        }
        .onDrop(of: [.fileURL], isTargeted: $dropping) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in if let url { Task { @MainActor in workspace.add([url]) } } }
            }; return true
        }
        .overlay { if dropping { RoundedRectangle(cornerRadius: 14).stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [8])).padding(12).allowsHitTesting(false) } }
        .onChange(of: voice.transcript) { _, text in if !text.isEmpty { workspace.draft = text } }
        .onChange(of: voice.error) { _, text in if let text { workspace.error = text } }
        .onDisappear { voice.stop(); voice.stopSpeaking() }
    }
    private func welcome(compact: Bool) -> some View {
        VStack(spacing: compact ? 12 : 22) {
            Spacer()
            NikaMark(size: compact ? 72 : 144)
            VStack(spacing: 10) {
                Text("Освободите место\nдля важного.").font(.system(size: compact ? 28 : 38, weight: .medium, design: .rounded)).multilineTextAlignment(.center)
                Text("Мысли, планы и ответы — в одном разговоре.").font(.system(size: 15)).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 155), spacing: 10)], spacing: 10) {
                starter("Разобраться в теме", "lightbulb", "Помоги мне разобраться в ")
                starter("Составить план", "list.bullet", "Помоги составить план ")
                starter("Поработать с файлом", "doc.text", "")
            }.frame(maxWidth: 620).padding(.top, 10)
            if workspace.store.login == nil && !workspace.isLocal {
                HStack(spacing: 16) { Button("Войти в NIKA", action: signIn).buttonStyle(.borderedProminent); Button("Использовать локально", action: showModels).buttonStyle(.bordered) }.padding(.top, 8)
            }
            Spacer(); Spacer().frame(height: 12)
        }.frame(maxWidth: .infinity).padding(20)
    }
    private func starter(_ title: String, _ symbol: String, _ text: String) -> some View {
        Button { if text.isEmpty { picker = true } else { workspace.draft = text; focused = true } } label: {
            VStack(alignment: .leading, spacing: 14) { Image(systemName: symbol).foregroundStyle(.secondary); Text(title).font(.callout) }
                .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                .nikaGlass(radius: 16)
        }.buttonStyle(.plain)
    }
    private func transcript(width: CGFloat) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    ForEach(workspace.messages) { message in
                        MessageView(message: message, workspace: workspace, availableWidth: width, speak: { voice.speak(message.content, local: workspace.isLocal) })
                    }
                    if workspace.sending { HStack(spacing: 8) { ProgressView().controlSize(.small); Text(workspace.activity.last ?? "Думаю…").font(.caption).foregroundStyle(.secondary).lineLimit(2) } }
                    Color.clear.frame(height: 1).id("bottom")
                }.frame(width: width).padding(.vertical, 24).frame(maxWidth: .infinity)
            }.defaultScrollAnchor(.bottom)
                .onChange(of: workspace.messages.last?.content) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
        }
    }
    private func composer(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if workspace.editingMessageID != nil {
                HStack { Label("Редактирование · последующие ответы будут заменены", systemImage: "pencil").font(.caption); Spacer(); Button("Отмена") { workspace.cancelEdit() } }.padding(10).nikaGlass(radius: 10)
            }
            if let error = workspace.error {
                HStack(alignment: .top) { Image(systemName: "exclamationmark.circle"); ScrollView { Text(error).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: compact ? 48 : 90); Spacer(); Button("Закрыть") { workspace.error = nil } }
                    .font(.callout).foregroundStyle(.red).padding(12).background(.red.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
            }
            if !workspace.attachments.isEmpty {
                ScrollView(.horizontal) { HStack { ForEach(workspace.attachments, id: \.self) { url in
                    HStack { Image(systemName: "doc"); Text(url.lastPathComponent).lineLimit(1); Button { workspace.attachments.removeAll { $0 == url } } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain) }
                        .font(.caption).padding(8).background(DesktopStyle.surface, in: Capsule())
                } } }.frame(height: 34)
            }
            VStack(spacing: 6) {
                // Match native text-container padding; grow only for actual draft lines.
                Text(workspace.draft + "\u{200B}")
                    .font(.system(size: 15))
                    .padding(.horizontal, 5)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: 24, maxHeight: compact ? 72 : 108)
                    .fixedSize(horizontal: false, vertical: true)
                    .hidden()
                    .overlay {
                        TextEditor(text: $workspace.draft)
                            .scrollContentBackground(.hidden)
                            .font(.system(size: 15)).focused($focused)
                            .overlay(alignment: .topLeading) {
                                if workspace.draft.isEmpty { Text("Спросите NIKA или добавьте файл…").font(.system(size: 15)).foregroundStyle(.tertiary).padding(.leading, 5).padding(.top, 1).allowsHitTesting(false) }
                            }
                            .onKeyPress(.return, phases: .down) { press in
                                if press.modifiers.contains(.shift) || (NSApp.keyWindow?.firstResponder as? NSTextView)?.hasMarkedText() == true { return .ignored }
                                workspace.send(); return .handled
                            }
                            .accessibilityLabel("Сообщение NIKA")
                    }
                HStack(spacing: 12) {
                    ScrollView(.horizontal) { HStack(spacing: 12) {
                    Menu {
                        Button("Файл…") { picker = true }
                        Button("Снимок экрана…") { Task { do { if let url = try await NativeAttachments.screenshot() { workspace.add([url]) } } catch { workspace.error = error.localizedDescription } } }
                        Button("Камера…") { camera = true }
                        Button("Из буфера обмена") { NativeAttachments.paste(into: workspace) }
                    } label: { Image(systemName: "plus") }.menuStyle(.borderlessButton).fixedSize().help("Добавить вложение")
                    if personalAgentMode { Label("Личный ботс", systemImage: "cloud").font(.callout) } else { Menu {
                        Button("NIKA Cloud") { workspace.selectProvider("cloud") }
                        ForEach(library.models.filter { library.installed.contains($0.id) && $0.auxiliaryFor == nil }) { model in Button(model.name + " · на Mac") { workspace.selectProvider(model.id) } }
                        Divider(); Button("Выбрать модель…") { workspace.modelPicker = true }; Button("Установить локальную модель", action: showModels)
                        if !workspace.isLocal {
                            Divider()
                            Button("Модель NIKA по умолчанию") { workspace.cloudModel = "" }
                            ForEach(workspace.store.models.prefix(100), id: \.id) { model in Button(model.name) { workspace.cloudModel = model.id } }
                            Button("Загрузить каталог облачных моделей") { Task { await workspace.store.fetchModels() } }
                        }
                    } label: { Label(workspace.isLocal ? (library.models.first { $0.id == workspace.providerID }?.name ?? "На Mac") : "NIKA Cloud", systemImage: workspace.isLocal ? "desktopcomputer" : "cloud") }
                        .menuStyle(.borderlessButton).fixedSize().disabled(workspace.sending) }
                    if workspace.isLocal { Toggle(isOn: $workspace.localToolsEnabled) { Image(systemName: "wrench.and.screwdriver") }.toggleStyle(.button).help("Действия Mac: календарь, напоминания и сохранение файлов. Каждое действие требует подтверждения.").disabled(workspace.sending) }
                    if !workspace.isLocal && !personalAgentMode {
                        Toggle(isOn: $workspace.reasoning) { Image(systemName: "brain") }.toggleStyle(.button).help("Сложная задача")
                        Toggle(isOn: $workspace.imageMode) { Image(systemName: "photo") }.toggleStyle(.button).help("Создать изображение")
                    }
                    } }.scrollIndicators(.hidden).frame(height: 34)
                    Button { Task { await voice.toggle(client: workspace.store.client, local: workspace.isLocal) } } label: {
                        Image(systemName: voice.recording ? "mic.fill" : "mic").foregroundStyle(voice.recording ? Color.red : Color.secondary)
                    }.help("Диктовка").disabled(voice.transcribing)
                    if !personalAgentMode { Button { voice.stop(); workspace.voicePanel = true } label: { Image(systemName: "waveform") }.help("Голосовой разговор") }
                    Button { if workspace.sending { workspace.stop() } else { workspace.send() } } label: {
                        Image(systemName: workspace.sending ? "stop.fill" : "arrow.up").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                            .frame(width: 32, height: 32).background(workspace.draft.isEmpty && !workspace.sending ? Color.gray : Color.accentColor, in: Circle())
                    }.buttonStyle(.plain).disabled(workspace.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !workspace.sending)
                        .keyboardShortcut(.return, modifiers: .command).accessibilityLabel(workspace.sending ? "Остановить ответ" : "Отправить")
                }.buttonStyle(.plain).foregroundStyle(.secondary)
            }.padding(.horizontal, 14).padding(.vertical, 10).nikaGlass(radius: 20, elevated: true)
            Text(workspace.isLocal ? "Локальная модель может ошибаться. Проверяйте важные ответы." : "Проверьте важные ответы. ⌘↩ отправить · Shift↩ новая строка")
                .font(.system(size: 10)).foregroundStyle(.tertiary).frame(maxWidth: .infinity)
        }
    }
}

struct MessageView: View {
    let message: DesktopMessage
    @ObservedObject var workspace: Workspace
    var availableWidth: CGFloat = DesktopStyle.readingWidth
    let speak: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if message.role != "user" { Text(workspace.agentName ?? "NIKA").font(.caption.weight(.semibold)).foregroundStyle(.secondary) }
            if !message.content.isEmpty {
                if message.role == "user" { Text(message.content).font(.system(size: 15)).lineSpacing(4).fixedSize(horizontal: false, vertical: true) }
                else { MarkdownView(text: message.content) }
            }
            if let versions = message.versions, versions.count > 1 {
                HStack(spacing: 12) {
                    let selected = message.selectedVersion ?? versions.count - 1
                    Button { workspace.selectVersion(messageID: message.id, index: selected - 1) } label: { Image(systemName: "chevron.left") }.disabled(selected == 0 || workspace.sending)
                    Text("Вариант \(selected + 1) из \(versions.count)").font(.caption).foregroundStyle(.secondary)
                    Button { workspace.selectVersion(messageID: message.id, index: selected + 1) } label: { Image(systemName: "chevron.right") }.disabled(selected == versions.count - 1 || workspace.sending)
                }.buttonStyle(.plain)
            }
            ForEach(message.localImages ?? [], id: \.self) { name in
                if let image = NSImage(contentsOf: workspace.store.assets.appendingPathComponent(name)) { Image(nsImage: image).resizable().scaledToFit().frame(maxHeight: 320).clipShape(RoundedRectangle(cornerRadius: 12)) }
            }
            if let client = workspace.store.client { ForEach(message.media ?? []) { InlineAttachment(attachment: $0, client: client) } }
            if !message.sources.isEmpty { ForEach(message.sources, id: \.self) { source in if let url = URL(string: source), ["http", "https"].contains(url.scheme ?? "") { Link(destination: url) { Label(url.host ?? source, systemImage: "link").font(.caption) } } } }
            ForEach(message.files, id: \.self) { file in
                if file.hasPrefix("api/files/") {
                    Button { Task { await download(file) } } label: { Label("Сохранить вложение", systemImage: "arrow.down.doc") }.font(.caption)
                } else { Label(file, systemImage: "paperclip").font(.caption).foregroundStyle(.secondary) }
            }
        }.padding(message.role == "user" ? 16 : 0)
            .background(message.role == "user" ? Color.primary.opacity(0.075) : Color.clear, in: RoundedRectangle(cornerRadius: 20))
            .frame(maxWidth: message.role == "user" ? availableWidth * 0.82 : availableWidth, alignment: message.role == "user" ? .trailing : .leading)
            .frame(width: availableWidth, alignment: message.role == "user" ? .trailing : .leading)
            .textSelection(.enabled)
            .contextMenu {
                Button("Скопировать") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(message.content, forType: .string) }
                if message.role == "user" { Button("Изменить и отправить снова") { workspace.beginEdit(message) }.disabled(workspace.sending) }
                else { Button("Новый вариант ответа") { workspace.retry() }.disabled(workspace.sending || message.id != workspace.messages.last?.id); Button("Прочитать вслух", action: speak); if message.taskID != nil { Button("Сохранить как навык") { Task { await workspace.saveSkill(from: message) } } } }
            }
    }
    private func download(_ path: String) async {
        guard let client = workspace.store.client else { return }
        do {
            try await client.ensureFreshAccessToken()
            guard let tokens = await client.currentTokens() else { throw DesktopError("Войдите снова.") }
            var request = URLRequest(url: client.baseURL.appendingPathComponent(path))
            request.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw DesktopError("Не удалось скачать файл.") }
            let panel = NSSavePanel(); panel.nameFieldStringValue = response.suggestedFilename ?? "NIKA-file"
            if await panel.begin() == .OK, let url = panel.url { try data.write(to: url, options: .atomic) }
        } catch { workspace.error = error.localizedDescription }
    }
}

struct WorkspaceFocus: FocusedValueKey { typealias Value = Workspace }
extension FocusedValues { var workspace: Workspace? { get { self[WorkspaceFocus.self] } set { self[WorkspaceFocus.self] = newValue } } }
