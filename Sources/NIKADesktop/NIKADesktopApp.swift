import SwiftUI
import AppKit
import Carbon

@main
struct NIKADesktopApp: App {
    @NSApplicationDelegateAdaptor(DesktopDelegate.self) private var delegate
    @StateObject private var store = DesktopStore()
    @AppStorage("appearance") private var appearance = "system"
    var body: some Scene {
        WindowGroup("NIKA", id: "main") {
            OnboardingGate { DesktopWindow(store: store) }.preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
                .onAppear { delegate.store = store; delegate.installHotKey() }
                .onReceive(NotificationCenter.default.publisher(for: .init("NIKAHotKeyChanged"))) { _ in delegate.installHotKey() }
        }.defaultSize(width: 1180, height: 800).commands { DesktopCommands(store: store) }
        Settings { DesktopSettingsView(store: store).preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil) }
        MenuBarExtra {
            Button("Быстрый вопрос") { delegate.quickAsk() }
            Button("Открыть NIKA") { NSApp.activate(ignoringOtherApps: true); NSApp.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil) }
            Divider()
            Text(store.library.loadedID == nil ? "Локальная модель не загружена" : "Локальная модель готова")
            SettingsLink { Text("Настройки…") }
            Divider(); Button("Завершить NIKA") { NSApp.terminate(nil) }
        } label: { Image(nsImage: MascotAssets.menuIcon).accessibilityLabel("NIKA") }
    }
}

struct DesktopCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.workspace) private var workspace
    let store: DesktopStore
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Новое окно") { openWindow(id: "main") }.keyboardShortcut("n", modifiers: [.command, .shift])
            Button("Новый разговор") { workspace?.newChat(); workspace?.requestedDestination = "chat" }.keyboardShortcut("n").disabled(workspace == nil)
        }
        CommandMenu("Разговор") {
            Button("Найти разговор") { workspace?.focusSearch = UUID() }.keyboardShortcut("f")
            Button("Выбрать модель…") { workspace?.requestedDestination = "chat"; workspace?.modelPicker = true }.keyboardShortcut("m", modifiers: [.command, .shift])
            Button("Голосовой разговор") { workspace?.requestedDestination = "chat"; workspace?.voicePanel = true }.keyboardShortcut("v", modifiers: [.command, .shift])
            Button("Предыдущий разговор") { workspace?.navigateConversation(-1) }.keyboardShortcut(.upArrow, modifiers: [.command, .option])
            Button("Следующий разговор") { workspace?.navigateConversation(1) }.keyboardShortcut(.downArrow, modifiers: [.command, .option])
            Divider()
            Button("Отправить") { workspace?.send() }.keyboardShortcut(.return).disabled(workspace == nil)
            Button("Остановить ответ") { workspace?.stop() }.keyboardShortcut(".").disabled(workspace?.sending != true)
            Button("Показать контекст") { workspace?.inspector.toggle() }.keyboardShortcut("i", modifiers: [.command, .option])
            Button("Новый локальный разговор") { if let model = store.library.models.first(where: { store.library.installed.contains($0.id) && $0.auxiliaryFor == nil }) { workspace?.newChat(provider: model.id) } }.keyboardShortcut("l", modifiers: [.command, .shift])
        }
        SidebarCommands()
    }
}

@MainActor
final class DesktopDelegate: NSObject, NSApplicationDelegate {
    weak var store: DesktopStore?
    private var panel: NSPanel?
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var terminating = false
    func applicationDidFinishLaunching(_ notification: Notification) { NSApp.servicesProvider = self; NSUpdateDynamicServices(); NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true) }
    @objc func askNIKA(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        let text = pasteboard.string(forType: .string) ?? ""
        guard !text.isEmpty else { error.pointee = "Выделите текст для NIKA."; return }
        var parts = URLComponents(); parts.scheme = "nika-desktop"; parts.host = "ask"; parts.queryItems = [.init(name: "text", value: text)]
        if let url = parts.url { NSWorkspace.shared.open(url) }
    }
    func installHotKey() {
        if let hotKey { UnregisterEventHotKey(hotKey); self.hotKey = nil }
        if let handler { RemoveEventHandler(handler); self.handler = nil }
        guard UserDefaults.standard.object(forKey: "quickAskEnabled") == nil || UserDefaults.standard.bool(forKey: "quickAskEnabled") else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            let delegate = Unmanaged<DesktopDelegate>.fromOpaque(userData).takeUnretainedValue()
            Task { @MainActor in
                if UserDefaults.standard.object(forKey: "quickAskEnabled") == nil || UserDefaults.standard.bool(forKey: "quickAskEnabled") { delegate.quickAsk() }
            }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
        let id = EventHotKeyID(signature: 0x4E494B41, id: 1)
        let key = UserDefaults.standard.string(forKey: "quickAskKey") ?? "space"
        let code = key == "n" ? kVK_ANSI_N : key == "k" ? kVK_ANSI_K : kVK_Space
        RegisterEventHotKey(UInt32(code), UInt32(controlKey | optionKey), id, GetApplicationEventTarget(), 0, &hotKey)
    }
    func quickAsk() {
        guard let store else { return }
        if let panel { panel.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 780, height: 560), styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        panel.title = "Быстрый вопрос · NIKA"; panel.isReleasedWhenClosed = false; panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: OnboardingGate { QuickAskView(store: store) })
        panel.center(); self.panel = panel; panel.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if terminating { return .terminateNow }
        terminating = true
        store?.library.pauseAll()
        Task { await store?.library.unload(); try? await Task.sleep(for: .milliseconds(500)); NSApp.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
}
struct QuickAskView: View {
    @StateObject private var workspace: Workspace
    @State private var models = false
    @State private var login = false
    let store: DesktopStore
    init(store: DesktopStore) { self.store = store; _workspace = StateObject(wrappedValue: Workspace(store: store)) }
    var body: some View {
        ConversationView(workspace: workspace, showModels: { models = true }, signIn: { login = true }).background { AuroraCanvas() }
            .sheet(isPresented: $models) { ModelLibraryView(library: store.library, store: store) { model in workspace.newChat(provider: model.id); models = false }.frame(width: 820, height: 650) }
            .sheet(isPresented: $login) { AuthenticationView(store: store) }
    }
}
