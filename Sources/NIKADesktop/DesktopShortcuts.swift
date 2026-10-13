import AppIntents
import Foundation

@available(macOS 15.0, *)
struct AskNIKAIntent: AppIntent {
    static var title: LocalizedStringResource = "Спросить NIKA"
    static var description = IntentDescription("Открыть вопрос в NIKA. Отправка — после подтверждения в приложении.")
    @Parameter(title: "Вопрос") var question: String
    static var openAppWhenRun = true
    func perform() async throws -> some IntentResult & OpensIntent {
        var components = URLComponents(); components.scheme = "nika-desktop"; components.host = "ask"; components.queryItems = [.init(name: "text", value: question)]
        guard let url = components.url else { throw CocoaError(.coderInvalidValue) }
        return .result(opensIntent: OpenURLIntent(url))
    }
}
@available(macOS 15.0, *)
struct NikaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AskNIKAIntent(), phrases: ["Спросить \(.applicationName)"], shortTitle: "Спросить NIKA", systemImageName: "sparkle")
    }
}
