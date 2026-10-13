import SwiftUI
import EventKit
import UserNotifications

struct LocalAction: Identifiable, Equatable {
    let id = UUID()
    let tool: String
    let arguments: [String: String]
    static let supported: Set<String> = ["calendar_events", "calendar_create_event", "reminder_create", "reminders_create", "reminders_list", "reminders_complete", "notification_schedule", "notification_list", "notification_cancel", "save_text_file"]
    static let instruction = """
    You can offer native Mac actions. If an action is needed, output ONLY one JSON object:
    {"tool":"tool_name","arguments":{"key":"value"}}.
    Available tools:
    calendar_events: days (1 to 365), optional from/to ISO8601; reads calendar events.
    calendar_create_event: title, date (ISO8601 with timezone), optional end (ISO8601), duration_minutes (default 60), all_day (true/false), notes.
    reminder_create: title, optional date (ISO8601 with timezone), notes, list (existing list name); creates a reminder.
    reminders_list: no arguments; lists incomplete reminders and their identifiers.
    reminders_complete: id (from reminders_list), title; marks that reminder complete.
    notification_schedule: title, body, date (future ISO8601 with timezone); schedules a local notification.
    notification_list: no arguments; lists pending NIKA notifications and their identifiers.
    notification_cancel: id (from notification_list), title; cancels a pending local notification.
    save_text_file: filename (including extension), content; asks the user where to save text/markdown/CSV.
    The user must confirm each action. Never say an action succeeded until you receive its result.
    Do not invent other tools. If no tool is needed, answer normally. After a result, answer in the user's language.
    """
    static func parse(_ text: String) -> LocalAction? {
        var json = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if json.hasPrefix("```json") { json = String(json.dropFirst(7)) }
        else if json.hasPrefix("```") { json = String(json.dropFirst(3)) }
        if json.hasSuffix("```") { json = String(json.dropLast(3)) }
        struct Payload: Decodable { let tool: String; let arguments: [String: String] }
        guard let value = try? JSONDecoder().decode(Payload.self, from: Data(json.utf8)), supported.contains(value.tool) else { return nil }
        return LocalAction(tool: value.tool, arguments: value.arguments)
    }
    var title: String { ["calendar_events": "Посмотреть календарь", "calendar_create_event": "Добавить событие", "reminder_create": "Создать напоминание", "reminders_create": "Создать напоминание", "reminders_list": "Посмотреть напоминания", "reminders_complete": "Завершить напоминание", "notification_schedule": "Запланировать уведомление", "notification_list": "Посмотреть уведомления", "notification_cancel": "Отменить уведомление", "save_text_file": "Сохранить файл"][tool] ?? tool }
    var detail: String {
        if tool == "calendar_events" { return "События на ближайшие \(arguments["days"] ?? "7") дней будут прочитаны локальной моделью на этом Mac." }
        if tool == "save_text_file" { return arguments["filename"] ?? "Документ" }
        if tool == "reminders_list" { return "Незавершённые напоминания будут прочитаны локальной моделью на этом Mac." }
        if tool == "notification_list" { return "Запланированные уведомления NIKA будут прочитаны локальной моделью на этом Mac." }
        return [arguments["title"], arguments["date"], arguments["end"], arguments["duration_minutes"].map { $0 + " мин" }, arguments["all_day"].map { "Весь день: " + $0 }, arguments["notes"], arguments["body"], arguments["id"], arguments["list"]].compactMap { $0 }.joined(separator: "\n")
    }
}
@MainActor
enum LocalActionExecutor {
    static func execute(_ action: LocalAction) async throws -> String {
        guard LocalAction.supported.contains(action.tool) else { throw DesktopError("Это действие не поддерживается на Mac.") }
        let args = action.arguments
        if action.tool.hasPrefix("notification_") { return try await notification(action) }
        if action.tool == "save_text_file" {
            guard let content = args["content"], !content.isEmpty, content.utf8.count <= 5_000_000 else { throw DesktopError("Нет текста для сохранения или он слишком большой.") }
            let panel = NSSavePanel(); panel.nameFieldStringValue = URL(fileURLWithPath: args["filename"] ?? "NIKA.txt").lastPathComponent
            guard await panel.begin() == .OK, let url = panel.url else { return "Пользователь отменил сохранение. Файл не создан." }
            try Data(content.utf8).write(to: url, options: .atomic)
            return "Файл сохранён: \(url.lastPathComponent)."
        }
        let calendar = DesktopCalendar()
        await calendar.connect(reminders: action.tool.hasPrefix("reminder"))
        if let error = calendar.error { throw DesktopError(error) }
        if action.tool == "calendar_events" {
            let start = args["from"].flatMap { ISO8601DateFormatter().date(from: $0) } ?? Date()
            let days = min(365, max(1, Int(args["days"] ?? "7") ?? 7))
            let end = args["to"].flatMap { ISO8601DateFormatter().date(from: $0) } ?? start.addingTimeInterval(Double(days) * 86400)
            guard end > start, end.timeIntervalSince(start) <= 366 * 86400 else { throw DesktopError("Укажите период календаря до одного года.") }
            return calendar.store.events(matching: calendar.store.predicateForEvents(withStart: start, end: end, calendars: nil)).sorted { $0.startDate < $1.startDate }.prefix(100)
                .map { "\($0.startDate.formatted()): \($0.title ?? "Событие")" }.joined(separator: "\n").nonempty(or: "Событий в этом периоде нет.")
        }
        if action.tool == "reminders_list" {
            return calendar.reminders.prefix(100).map { "id=\($0.calendarItemIdentifier): \($0.title ?? "Напоминание")" }.joined(separator: "\n").nonempty(or: "Незавершённых напоминаний нет.")
        }
        if action.tool == "reminders_complete" {
            guard let id = args["id"], let item = calendar.reminders.first(where: { $0.calendarItemIdentifier == id }) else { throw DesktopError("Напоминание не найдено. Сначала обновите список.") }
            item.isCompleted = true; try calendar.store.save(item, commit: true)
            return "Завершено: " + (item.title ?? "Напоминание")
        }
        guard let title = args["title"], !title.isEmpty else { throw DesktopError("Укажите название.") }
        let date = args["date"].flatMap { ISO8601DateFormatter().date(from: $0) }
        if args["date"] != nil && date == nil { throw DesktopError("Укажите точную дату с часовым поясом.") }
        if action.tool.hasPrefix("reminder") {
            let item = EKReminder(eventStore: calendar.store); item.title = title; item.notes = args["notes"]
            if let list = args["list"], !list.isEmpty {
                guard let target = calendar.store.calendars(for: .reminder).first(where: { $0.title == list && $0.allowsContentModifications }) else { throw DesktopError("Такой список напоминаний не найден.") }
                item.calendar = target
            } else { item.calendar = calendar.store.defaultCalendarForNewReminders() }
            guard item.calendar != nil else { throw DesktopError("Создайте список в «Напоминаниях».") }
            if let date { item.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .timeZone], from: date) }
            try calendar.store.save(item, commit: true)
        } else {
            guard let date else { throw DesktopError("Укажите дату события с часовым поясом.") }
            let end = args["end"].flatMap { ISO8601DateFormatter().date(from: $0) } ?? date.addingTimeInterval(Double(min(10080, max(1, Int(args["duration_minutes"] ?? "60") ?? 60))) * 60)
            guard end > date else { throw DesktopError("Событие должно завершаться после начала.") }
            let item = EKEvent(eventStore: calendar.store); item.title = title; item.notes = args["notes"]; item.startDate = date; item.endDate = end; item.isAllDay = ["true", "да", "1"].contains(args["all_day"] ?? "")
            item.calendar = calendar.store.defaultCalendarForNewEvents
            guard item.calendar != nil else { throw DesktopError("Создайте календарь в приложении «Календарь».") }
            try calendar.store.save(item, span: .thisEvent, commit: true)
        }
        return "Создано: \(title)" + (date.map { ", " + $0.formatted() } ?? "") + "."
    }
    static func notificationRequest(_ args: [String: String], now: Date = Date()) throws -> UNNotificationRequest {
        guard let title = args["title"], !title.isEmpty, let raw = args["date"], let date = ISO8601DateFormatter().date(from: raw), date > now else { throw DesktopError("Укажите название и будущую дату уведомления с часовым поясом.") }
        let content = UNMutableNotificationContent(); content.title = title; content.body = args["body"] ?? ""; content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, date.timeIntervalSince(now)), repeats: false)
        return UNNotificationRequest(identifier: "nika-local-" + UUID().uuidString, content: content, trigger: trigger)
    }
    private static func notification(_ action: LocalAction) async throws -> String {
        let center = UNUserNotificationCenter.current()
        if action.tool == "notification_list" {
            let pending = await center.pendingNotificationRequests()
            return pending.map { "id=\($0.identifier): \($0.content.title)" }.joined(separator: "\n").nonempty(or: "Запланированных уведомлений NIKA нет.")
        }
        if action.tool == "notification_cancel" {
            guard let id = action.arguments["id"], await center.pendingNotificationRequests().contains(where: { $0.identifier == id }) else { throw DesktopError("Уведомление не найдено. Сначала обновите список.") }
            center.removePendingNotificationRequests(withIdentifiers: [id]); return "Запланированное уведомление отменено."
        }
        let request = try notificationRequest(action.arguments)
        guard try await center.requestAuthorization(options: [.alert, .sound, .badge]) else { throw DesktopError("Разрешите уведомления NIKA в Системных настройках.") }
        try await center.add(request); return "Уведомление запланировано: \(request.content.title), id=\(request.identifier)."
    }
}
private extension String { func nonempty(or fallback: String) -> String { isEmpty ? fallback : self } }
struct LocalActionConfirmation: View {
    let action: LocalAction
    let resolve: (Bool) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label(action.title, systemImage: "desktopcomputer").font(.title2)
            Text(action.detail).textSelection(.enabled)
            if let content = action.arguments["content"] { ScrollView { Text(content).font(.system(.body, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 260) }
            Text("Действие выполняется на этом Mac. Данные не отправляются в облако NIKA.").font(.caption).foregroundStyle(.secondary)
            HStack { Button("Не выполнять") { resolve(false) }; Spacer(); Button("Разрешить") { resolve(true) }.buttonStyle(.borderedProminent) }
        }.padding(28).frame(width: 510).background { AuroraCanvas() }
    }
}
