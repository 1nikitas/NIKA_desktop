import Foundation
import UserNotifications
import AppKit

@MainActor
enum CompletionNotifications {
    static func enable() async throws -> Bool { try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
    static func finished() {
        guard UserDefaults.standard.bool(forKey: "completionNotifications"), !NSApp.isActive else { return }
        let content = UNMutableNotificationContent()
        content.title = "NIKA закончила ответ"; content.body = "Откройте приложение, чтобы прочитать результат."; content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
