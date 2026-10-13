import SwiftUI
import AVFoundation

struct AuthenticationView: View {
    @ObservedObject var store: DesktopStore
    @Environment(\.dismiss) private var dismiss
    @State private var telegramTask: Task<Void, Never>?
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 20) {
            HStack { NikaMark(size: 42); Text("NIKA").tracking(2); Spacer(); Button("Позже") { telegramTask?.cancel(); dismiss() } }
            Text("Продолжим\nваш разговор.").font(.system(size: 32, weight: .medium, design: .rounded))
            Text("Войдите, чтобы открыть разговоры, агентов и память вашего аккаунта.").foregroundStyle(.secondary)
            Text("Нажмите кнопку и подтвердите вход в Telegram. После подтверждения приложение откроет ваш аккаунт автоматически.")
                .font(.callout).foregroundStyle(.secondary)
            if let error = store.error { Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled) }
            if store.busy { ProgressView("Подтвердите вход в Telegram…") }
            Button {
                telegramTask = Task { await store.telegram(); if store.login != nil { dismiss() } }
            } label: {
                Label("Войти через Telegram", systemImage: "paperplane.fill").frame(maxWidth: .infinity)
            }.buttonStyle(.borderedProminent).controlSize(.large).disabled(store.busy)
            DisclosureGroup("Адрес сервера") { TextField("https://nika-agent.ru", text: $store.baseURL).textFieldStyle(.roundedBorder).disabled(store.busy) }.font(.caption).foregroundStyle(.secondary)
            Text("Для локальных моделей вход не нужен.").font(.caption).foregroundStyle(.tertiary)
        }.padding(28) }.scrollIndicators(.visible).frame(width: 450, height: DesktopFormLayout.height(450)).background { AuroraCanvas() }.onDisappear { telegramTask?.cancel() }.onChange(of: store.login?.session.clientID) { _, id in if id != nil { dismiss() } }
    }
}

struct DesktopSettingsView: View {
    @ObservedObject var store: DesktopStore
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("auroraIntensity") private var auroraIntensity = 0.65
    @AppStorage("quickAskEnabled") private var quickAsk = true
    @AppStorage("quickAskKey") private var quickAskKey = "space"
    @AppStorage("speechRecognition") private var recognition = "apple"
    @AppStorage("speechVoice") private var speechVoice = ""
    @AppStorage("speechRate") private var speechRate = 0.5
    @AppStorage("completionNotifications") private var notifications = false
    @State private var signIn = false
    @State private var deletion = false
    var body: some View {
        TabView {
            Form {
                Section("Внешний вид") {
                    Picker("Оформление", selection: $appearance) { Text("Системное").tag("system"); Text("Светлое").tag("light"); Text("Тёмное").tag("dark") }
                    Slider(value: $auroraIntensity, in: 0...1) { Text("Насыщенность градиента") }
                    Toggle("Глобальный Quick Ask", isOn: $quickAsk)
                    Picker("Сочетание клавиш", selection: $quickAskKey) { Text("⌃⌥Space").tag("space"); Text("⌃⌥N").tag("n"); Text("⌃⌥K").tag("k") }.disabled(!quickAsk)
                    Toggle("Сообщать о готовом ответе", isOn: Binding(get: { notifications }, set: { enabled in
                        if !enabled { notifications = false }
                        else { Task { do { notifications = try await CompletionNotifications.enable() } catch { store.error = error.localizedDescription } } }
                    }))
                    Text("Меню NIKA в строке меню всегда открывает быстрый разговор.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Аккаунт") {
                    if let login = store.login { LabeledContent("Вы вошли как", value: login.session.username); Button("Выйти") { store.logout() }; Button("Удалить аккаунт…", role: .destructive) { deletion = true } }
                    else { Button("Войти в NIKA") { signIn = true } }
                }
            }.formStyle(.grouped).tabItem { Label("Основные", systemImage: "gearshape") }
            ProviderSettingsView(store: store).tabItem { Label("Провайдеры", systemImage: "cloud") }
            Form {
                Section("Генерация на Mac") {
                    Toggle("Рассуждение (если поддерживается моделью)", isOn: Binding(get: { store.settings.thinking ?? false }, set: { store.settings.thinking = $0 }))
                    Picker("Контекст", selection: $store.settings.context) { ForEach([2048, 4096, 8192, 16384], id: \.self) { Text("\($0) токенов").tag($0).disabled($0 > LocalMemoryBudget.contextLimit(memory: ProcessInfo.processInfo.physicalMemory)) } }
                    Text("Для Mac с 8 ГБ рекомендуем NIKA Smart и контекст 4096. Для изображений уменьшите контекст до 2048 и закройте тяжёлые приложения.").font(.caption).foregroundStyle(.secondary)
                    LabeledContent("Температура", value: String(format: "%.1f", store.settings.temperature))
                    Slider(value: $store.settings.temperature, in: 0...1.5, step: 0.1)
                    LabeledContent("Top P", value: String(format: "%.2f", store.settings.topP))
                    Slider(value: $store.settings.topP, in: 0.1...1, step: 0.05)
                    Picker("Длина ответа", selection: $store.settings.maxTokens) { ForEach([256, 512, 1024, 2048], id: \.self) { Text("\($0) токенов").tag($0) } }
                    Button("Выгрузить модель из памяти") { Task { await store.library.unload() } }
                }
                Section("Файлы моделей") {
                    if store.library.relocating { ProgressView("Перенос и проверка моделей…") }
                    Text(store.library.directory.path).font(.caption).textSelection(.enabled)
                    Button("Изменить папку…") {
                        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
                        panel.begin { response in if response == .OK, let url = panel.url { Task { do { try await store.library.chooseDirectory(url) } catch { store.error = error.localizedDescription } } } }
                    }
                }
            }.formStyle(.grouped).tabItem { Label("Локальные модели", systemImage: "cpu") }
            Form {
                Section("Голос") {
                    Picker("Диктовка", selection: $recognition) { Text("Apple · на устройстве").tag("apple"); Text("NIKA Whisper · отправка аудио на сервер").tag("server") }
                    Text("Серверное распознавание применяется только в облачном чате. Локальные разговоры всегда используют Apple.").font(.caption).foregroundStyle(.secondary)
                    Picker("Голос", selection: $speechVoice) { Text("Системный").tag(""); ForEach(AVSpeechSynthesisVoice.speechVoices(), id: \.identifier) { voice in Text("\(voice.name) · \(voice.language)").tag(voice.identifier) } }
                    Slider(value: $speechRate, in: 0.3...0.65) { Text("Темп речи") }
                }
                RemoteSpeechSettings()
                Section("Обработка данных") {
                    Label("Локальные разговоры остаются на этом Mac", systemImage: "lock.shield")
                    Text("Переключение в облако создаёт новый разговор. Локальная история не отправляется на сервер и не синхронизируется.")
                    Text("Диктовка использует распознавание Apple на устройстве. Если язык недоступен офлайн, приложение сообщает об этом. Озвучка использует установленные системные голоса.")
                    Button("Открыть настройки микрофона") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!) }
                    Button("Показать локальные данные") { NSWorkspace.shared.open(DesktopStore.supportDirectory) }
                }
            }.formStyle(.grouped).tabItem { Label("Приватность и голос", systemImage: "hand.raised") }
        }.padding(12).frame(width: DesktopFormLayout.width(610), height: DesktopFormLayout.height(520))
            .onChange(of: quickAskKey) { _, _ in NotificationCenter.default.post(name: .init("NIKAHotKeyChanged"), object: nil) }
            .onChange(of: quickAsk) { _, _ in NotificationCenter.default.post(name: .init("NIKAHotKeyChanged"), object: nil) }
            .sheet(isPresented: $signIn) { AuthenticationView(store: store) }
            .confirmationDialog("Удалить аккаунт NIKA навсегда?", isPresented: $deletion, titleVisibility: .visible) {
                Button("Удалить аккаунт", role: .destructive) { Task { await store.deleteAccount() } }
            } message: { Text("Облачные данные аккаунта будут удалены. Это действие нельзя отменить. Локальные разговоры на Mac останутся.") }
    }
}
