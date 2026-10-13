import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct PersonalBot: Decodable, Identifiable {
    let chat: BFFRemoteChatInfo
    let personality: Personality?
    var id: String { chat.id }
    var name: String { personality?.name ?? chat.displayTitle }
    struct Reference: Decodable { let id: String; let name: String? }
    struct Personality: Decodable {
        let name: String?
        let avatar: String?
        let avatar_image: String?
        let instructions: String?
        let instructions_label: String?
        let preset: Reference?
        let role: Reference?
    }
    enum CodingKeys: String, CodingKey { case personality }
    init(from decoder: Decoder) throws {
        chat = try BFFRemoteChatInfo(from: decoder)
        personality = try decoder.container(keyedBy: CodingKeys.self).decodeIfPresent(Personality.self, forKey: .personality)
    }
}
struct BotPreset: Decodable, Identifiable {
    let id: String; let name: String; let avatar: String; let tagline: String; let instructions: String
}
struct BotDraft {
    var name = "Ника"
    var avatar = "nika"
    var image = ""
    var instructions = ""
    var label = ""
    var presetID = ""
    var roleID = ""
    var valid: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.count <= 80 && instructions.count <= 8000 && image.utf8.count <= 200_000 }
    var body: [String: BFFJSONValue] {
        var value: [String: BFFJSONValue] = ["name": .string(name.trimmingCharacters(in: .whitespacesAndNewlines)), "avatar": .string(avatar), "instructions": .string(instructions), "instructions_label": .string(label), "preset_id": presetID.isEmpty ? .null : .string(presetID), "role_id": roleID.isEmpty ? .null : .string(roleID)]
        if avatar == "custom", !image.isEmpty { value["avatar_image"] = .string(image) }
        return value
    }
    init() {}
    init(_ bot: PersonalBot) {
        name = bot.name; avatar = bot.personality?.avatar ?? "nika"; image = bot.personality?.avatar_image ?? ""
        instructions = bot.personality?.instructions ?? ""; label = bot.personality?.instructions_label ?? ""
        presetID = bot.personality?.preset?.id ?? ""; roleID = bot.personality?.role?.id ?? ""
    }
    mutating func apply(_ preset: BotPreset) {
        name = preset.name; avatar = preset.avatar; image = ""; instructions = preset.instructions
        label = preset.name; presetID = preset.id; roleID = ""
    }
}
struct BotAvatar: View {
    var slug: String = "nika"
    var dataURL: String = ""
    var size: CGFloat = 56
    static let looks = [("nika", "Ника"), ("kruglaya", "Кругляш"), ("shustraya", "Шустрая"), ("iskorka", "Искорка"), ("luchik", "Лучик")]
    var body: some View {
        Group {
            if slug == "nika" { DesktopMascot(size: size) }
            else if let image { Image(nsImage: image).resizable().scaledToFit().frame(width: size, height: size) }
            else { DesktopMascot(size: size) }
        }.accessibilityHidden(true)
    }
    private var image: NSImage? {
        if slug == "custom", let encoded = dataURL.split(separator: ",", maxSplits: 1).last, let bytes = Data(base64Encoded: String(encoded)) { return NSImage(data: bytes) }
        let known = Self.looks.contains { $0.0 == slug } ? slug : "kruglaya"
        let url = Bundle.main.url(forResource: known, withExtension: "webp", subdirectory: "Mascot") ?? Bundle.module.url(forResource: known, withExtension: "webp", subdirectory: "Mascot")
        return url.flatMap(NSImage.init(contentsOf:))
    }
}

struct PersonalBotsView: View {
    @ObservedObject var store: DesktopStore
    @StateObject private var workspace: Workspace
    let signIn: () -> Void
    @State private var bots: [PersonalBot] = []
    @State private var presets: [BotPreset] = []
    @State private var selected: String?
    @State private var loaded = false
    @State private var busy = false
    @State private var error: String?
    @State private var editing = false
    @State private var editID: String?
    @State private var draft = BotDraft()
    @State private var deleting = false
    @State private var materials = false
    @Environment(\.scenePhase) private var scenePhase
    init(store: DesktopStore, signIn: @escaping () -> Void) {
        self.store = store; self.signIn = signIn; _workspace = StateObject(wrappedValue: Workspace(store: store))
    }
    private var bot: PersonalBot? { bots.first { $0.id == selected } }
    var body: some View {
        VStack(spacing: 0) {
            if store.client == nil {
                ContentUnavailableView { Label("Ваши личные ботсы", systemImage: "person.crop.circle.badge.checkmark") } description: { Text("Войдите, чтобы открыть своих помощников, их память и разговоры.") } actions: { Button("Войти в NIKA", action: signIn).buttonStyle(.borderedProminent) }
            } else {
                header
                if let error { HStack { Text(error).foregroundStyle(.red); Button("Повторить") { Task { await load() } } }.font(.callout).padding() }
                if busy && !loaded { ProgressView("Загружаем ботсов…").frame(maxWidth: .infinity, maxHeight: .infinity) }
                else if let bot {
                    HStack {
                        BotAvatar(slug: bot.personality?.avatar ?? "nika", dataURL: bot.personality?.avatar_image ?? "", size: 42)
                        VStack(alignment: .leading) { Text(bot.name).font(.headline); Text(bot.personality?.instructions_label ?? "Личный помощник").font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        Button("Материалы и дела") { materials = true }
                        Button("Настроить") { draft = BotDraft(bot); editID = bot.id; editing = true }.disabled(workspace.sending || workspace.loading)
                        Button(role: .destructive) { deleting = true } label: { Image(systemName: "trash") }.help("Удалить ботса").disabled(busy || workspace.sending)
                    }.padding(.horizontal, 24).padding(.vertical, 10)
                    if let syncError = workspace.personalBotSyncError { Label(syncError, systemImage: "wifi.exclamationmark").font(.caption).foregroundStyle(.secondary).padding(.horizontal) }
                    ConversationView(workspace: workspace, showModels: {}, signIn: signIn, personalAgentMode: true)
                } else { gallery }
            }
        }
        .background { AuroraCanvas() }
        .task { await load() }
        .task(id: selected) {
            guard let id = selected else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
                guard !Task.isCancelled else { return }
                if scenePhase == .active { await workspace.refreshPersonalBot(id: id) }
            }
        }
        .onDisappear { workspace.stop() }
        .sheet(isPresented: $editing) { BotEditor(draft: draft, presets: presets, client: store.client, editID: editID) { result in
            if let index = bots.firstIndex(where: { $0.id == result.id }) { bots[index] = result } else { bots.append(result) }
            editing = false; Task { await open(result) }
        } }
        .sheet(isPresented: $materials) { if let bot, let client = store.client { BotMaterialsView(bot: bot, client: client) } }
        .confirmationDialog("Удалить ботса и его разговор? Напоминания и повторяющиеся дела этого ботса будут отменены.", isPresented: $deleting, titleVisibility: .visible) {
            Button("Удалить ботса", role: .destructive) { Task { await remove() } }
            Button("Отмена", role: .cancel) {}
        }
    }
    private var header: some View {
        HStack {
            Menu {
                Button("Все ботсы") { selected = nil; workspace.newChat(provider: "cloud") }
                ForEach(bots) { item in Button(item.name) { Task { await open(item) } } }
            } label: { Label("Мои ботсы · \(bots.count)", systemImage: "person.2") }.disabled(workspace.sending || workspace.loading)
            Spacer()
            Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") }.help("Обновить ботсов").disabled(busy)
            Button("Создать ботса", systemImage: "plus") { editID = nil; draft = BotDraft(); editing = true }.disabled(workspace.sending || workspace.loading)
        }.padding(20)
    }
    private var gallery: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 20) { DesktopMascot(size: 100); VStack(alignment: .leading, spacing: 8) { Text("Ваши личные ботсы").font(.largeTitle.bold()); Text("У каждого — свой характер, инструкции и память о вашем разговоре.").foregroundStyle(.secondary) } }
                if !bots.isEmpty {
                    Text("Мои помощники").font(.title2.bold())
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220))], spacing: 16) {
                        ForEach(bots) { item in
                            Button { Task { await open(item) } } label: {
                                HStack { BotAvatar(slug: item.personality?.avatar ?? "nika", dataURL: item.personality?.avatar_image ?? ""); VStack(alignment: .leading) { Text(item.name).font(.headline); Text(item.personality?.instructions_label ?? "Личный помощник").font(.caption).foregroundStyle(.secondary).lineLimit(2) }; Spacer() }.padding(16).frame(maxWidth: .infinity, alignment: .leading).nikaGlass()
                            }.buttonStyle(.plain)
                        }
                    }
                }
                Text("Какой бот вам нужен?").font(.title2.bold())
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220))], spacing: 16) {
                    ForEach(presets) { preset in
                        Button { draft = BotDraft(); draft.apply(preset); editID = nil; editing = true } label: {
                            VStack(alignment: .leading, spacing: 12) { BotAvatar(slug: preset.avatar, size: 80); Text(preset.name).font(.headline); Text(preset.tagline).font(.callout).foregroundStyle(.secondary).frame(minHeight: 40, alignment: .topLeading) }.padding(20).frame(maxWidth: .infinity, alignment: .leading).nikaGlass()
                        }.buttonStyle(.plain)
                    }
                    Button { draft = BotDraft(); editID = nil; editing = true } label: {
                        VStack(alignment: .leading, spacing: 12) { Image(systemName: "plus.circle").font(.system(size: 40)).frame(height: 80); Text("Свой ботс").font(.headline); Text("Задайте имя, облик и то, в чём он будет вам помогать.").font(.callout).foregroundStyle(.secondary).frame(minHeight: 40) }.padding(20).frame(maxWidth: .infinity, alignment: .leading).nikaGlass()
                    }.buttonStyle(.plain)
                }
            }.padding(28)
        }
    }
    private func load() async {
        guard let client = store.client, !busy else { return }
        busy = true; error = nil; defer { busy = false }
        do {
            let result: [PersonalBot] = try await DesktopAPI(client: client).request("personal-agents")
            guard !Task.isCancelled else { return }; bots = result; loaded = true
            if let selected, !bots.contains(where: { $0.id == selected }) { self.selected = nil; workspace.newChat(provider: "cloud") }
            presets = try await DesktopAPI(client: client).request("personal-agents/presets")
        } catch { self.error = "Не удалось загрузить ботсов. Проверьте подключение. \(error.localizedDescription)"; loaded = true }
    }
    private func open(_ item: PersonalBot) async {
        guard !workspace.sending else { return }
        selected = item.id; await workspace.open(item.chat)
    }
    private func remove() async {
        guard let bot, let client = store.client else { return }
        busy = true; defer { busy = false }
        do {
            let _: EmptyResponse = try await DesktopAPI(client: client).request("personal-agents/\(bot.id)", method: "DELETE")
            bots.removeAll { $0.id == bot.id }; selected = nil; workspace.newChat(provider: "cloud")
        } catch { self.error = error.localizedDescription }
    }
}

struct BotEditor: View {
    @State var draft: BotDraft
    var preferredHeight: CGFloat = 650
    let presets: [BotPreset]
    let client: BFFClient?
    let editID: String?
    let saved: (PersonalBot) -> Void
    @State private var busy = false
    @State private var error: String?
    @State private var importing = false
    @State private var roles: [BFFAgent] = []
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 14) {
            HStack { Text(editID == nil ? "Создать ботса" : "Настроить ботса").font(.title2.bold()); Spacer(); Button("Отмена") { dismiss() }.disabled(busy) }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    HStack { BotAvatar(slug: draft.avatar, dataURL: draft.image, size: 64); TextField("Имя", text: $draft.name).textFieldStyle(.roundedBorder) }
                    Text("Облик").font(.headline)
                    HStack(spacing: 12) {
                        ForEach(BotAvatar.looks, id: \.0) { slug, name in
                            Button { draft.avatar = slug; draft.image = "" } label: {
                                VStack { BotAvatar(slug: slug, size: 44); Text(name).font(.caption) }.padding(6)
                                    .background(draft.avatar == slug ? Color.accentColor.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 12))
                            }.buttonStyle(.plain)
                        }
                        Button("Своя…") { importing = true }
                    }
                    Picker("Готовый бот", selection: $draft.presetID) {
                        Text("Свой ботс").tag("")
                        ForEach(presets) { Text($0.name).tag($0.id) }
                        if !draft.presetID.isEmpty && !presets.contains(where: { $0.id == draft.presetID }) { Text("Текущий бот").tag(draft.presetID) }
                    }.onChange(of: draft.presetID) { _, value in
                        if let preset = presets.first(where: { $0.id == value }) { draft.apply(preset) }
                    }
                    if draft.presetID.isEmpty {
                        Picker("Роль", selection: $draft.roleID) {
                            Text("Универсальный помощник").tag("")
                            ForEach(roles) { Text($0.name).tag($0.id) }
                            if !draft.roleID.isEmpty && !roles.contains(where: { $0.id == draft.roleID }) { Text("Текущая роль").tag(draft.roleID) }
                        }.onChange(of: draft.roleID) { _, value in
                            if let role = roles.first(where: { $0.id == value }) { draft.instructions = role.systemPrompt; draft.label = role.name }
                        }
                    }
                    Text("Инструкции").font(.headline)
                    Text("Расскажите, чем помогать и как отвечать. Эти инструкции сохраняются у ботса.").font(.callout).foregroundStyle(.secondary)
                    DesktopTextArea(text: $draft.instructions, height: min(144, max(88, DesktopFormLayout.height(preferredHeight) - 506)), label: "Инструкции ботсу")
                    Text("\(draft.instructions.count) / 8000").font(.caption).foregroundStyle(draft.instructions.count > 8000 ? Color.red : .secondary)
                    if let error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
                }.padding(.horizontal, 2).padding(.vertical, 8)
            }.scrollIndicators(.visible).disabled(busy)
            Divider()
            HStack { if busy { ProgressView().controlSize(.small); Text("Сохраняем…") }; Spacer(); Button(editID == nil ? "Создать" : "Сохранить") { Task { await save() } }.buttonStyle(.borderedProminent).disabled(busy || !draft.valid || client == nil) }
        }.padding(24).frame(width: 590, height: DesktopFormLayout.height(preferredHeight)).background { AuroraCanvas() }.interactiveDismissDisabled(busy)
        .task { if let client { do { roles = try await DesktopAPI(client: client).request("agents/presets") } catch { self.error = "Каталог ролей недоступен. Можно задать свои инструкции." } } }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.png, .jpeg], allowsMultipleSelection: false) { result in
            do {
                guard let url = try result.get().first else { return }
                let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                let bytes = try Data(contentsOf: url)
                guard bytes.count <= 145_000, NSImage(data: bytes) != nil else { throw DesktopError("Выберите PNG или JPEG до 145 КБ.") }
                draft.image = "data:image/\(url.pathExtension.lowercased() == "png" ? "png" : "jpeg");base64," + bytes.base64EncodedString(); draft.avatar = "custom"
            } catch { self.error = error.localizedDescription }
        }
    }
    private func save() async {
        guard let client, draft.valid, !busy else { return }; busy = true; error = nil; defer { busy = false }
        do {
            let bot: PersonalBot = try await DesktopAPI(client: client).request(editID.map { "personal-agents/\($0)" } ?? "personal-agents", method: editID == nil ? "POST" : "PATCH", body: draft.body)
            guard !Task.isCancelled else { return }; saved(bot)
        } catch { self.error = "Не удалось сохранить. Ваши изменения остались в форме. \(error.localizedDescription)" }
    }
}
struct BotMaterials: Decodable {
    let files: [File]; let links: [LinkItem]
    struct File: Decodable, Identifiable {
        let file_id: String?; let filename: String; let mime_type: String; let message_id: String
        var id: String { (file_id ?? message_id) + filename }
    }
    struct LinkItem: Decodable, Identifiable {
        let url: String; let title: String; let domain: String
        var id: String { url }
        var safeURL: URL? { guard let value = URL(string: url), ["https", "http"].contains(value.scheme?.lowercased() ?? "") else { return nil }; return value }
    }
}
struct BotSchedule: Decodable, Identifiable {
    let id: String; let chat_id: String; let text: String; let active: Bool; let next_fire_at: String?
}
struct BotMaterialsView: View {
    let bot: PersonalBot
    let client: BFFClient
    @State private var content: BotMaterials?
    @State private var schedules: [BotSchedule] = []
    @State private var error: String?
    @State private var loading = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text(bot.name + " · Материалы и дела").font(.title2.bold()); Spacer(); Button("Готово") { dismiss() } }
            if loading { ProgressView() }
            if let error { Text(error).foregroundStyle(.red); Button("Повторить") { Task { await load() } } }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Файлы").font(.headline)
                    if let content {
                        if content.files.isEmpty { Text("Файлов пока нет").foregroundStyle(.secondary) }
                        ForEach(content.files) { file in
                            if let id = file.file_id { InlineAttachment(attachment: .init(path: "api/files/" + id, name: file.filename, mime: file.mime_type), client: client) }
                            else { Label(file.filename + " · в истории разговора", systemImage: "doc") }
                        }
                        Divider(); Text("Ссылки").font(.headline)
                        if content.links.isEmpty { Text("Ссылок пока нет").foregroundStyle(.secondary) }
                        ForEach(content.links) { item in if let url = item.safeURL { Link(item.title.isEmpty ? item.domain : item.title, destination: url) } }
                    }
                    Divider(); Text("Дела и напоминания").font(.headline)
                    if schedules.isEmpty && !loading && error == nil { Text("Пока нет дел").foregroundStyle(.secondary) }
                    ForEach(schedules) { item in
                        VStack(alignment: .leading) { Label(item.text, systemImage: item.active ? "clock" : "checkmark.circle"); if let date = item.next_fire_at { Text(date).font(.caption).foregroundStyle(.secondary) } }.opacity(item.active ? 1 : 0.55)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }.padding(24).frame(width: DesktopFormLayout.width(620), height: DesktopFormLayout.height(600)).background { AuroraCanvas() }.task { await load() }
    }
    private func load() async {
        loading = true; error = nil; defer { loading = false }
        do {
            content = try await DesktopAPI(client: client).request("personal-agents/\(bot.id)/materials")
            let all: [BotSchedule] = try await DesktopAPI(client: client).request("schedules", query: [.init(name: "limit", value: "100")])
            schedules = all.filter { $0.chat_id == bot.id }
        } catch { self.error = "Не удалось обновить материалы или дела. \(error.localizedDescription)" }
    }
}
