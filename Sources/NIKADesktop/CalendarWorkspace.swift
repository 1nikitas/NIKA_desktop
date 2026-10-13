import SwiftUI
import EventKit

@MainActor
final class DesktopCalendar: ObservableObject {
    let store = EKEventStore()
    @Published var events: [EKEvent] = []
    @Published var reminders: [EKReminder] = []
    @Published var error: String?
    @Published var authorized = false
    @Published var remindersAuthorized = false
    func connect(reminders: Bool = false) async {
        do {
            if reminders { remindersAuthorized = try await store.requestFullAccessToReminders() }
            else { authorized = try await store.requestFullAccessToEvents() }
            if (reminders ? remindersAuthorized : authorized) { await refresh() }
            else { error = "Доступ не разрешён. Его можно изменить в Системных настройках → Конфиденциальность." }
        } catch { self.error = error.localizedDescription }
    }
    func refresh() async {
        if EKEventStore.authorizationStatus(for: .event) == .fullAccess {
            authorized = true
            events = store.events(matching: store.predicateForEvents(withStart: Calendar.current.startOfDay(for: Date()), end: Date().addingTimeInterval(30 * 86_400), calendars: nil)).sorted { $0.startDate < $1.startDate }
        }
        if EKEventStore.authorizationStatus(for: .reminder) == .fullAccess {
            remindersAuthorized = true
            reminders = await withCheckedContinuation { continuation in
                store.fetchReminders(matching: store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)) { continuation.resume(returning: $0 ?? []) }
            }
        }
    }
    func create(title: String, notes: String, date: Date, reminder: Bool, calendarID: String?) async throws {
        if reminder {
            guard remindersAuthorized else { throw DesktopError("Сначала разрешите доступ к напоминаниям.") }
            let item = EKReminder(eventStore: store); item.title = title; item.notes = notes
            item.calendar = calendarID.flatMap(store.calendar(withIdentifier:)) ?? store.defaultCalendarForNewReminders()
            guard item.calendar != nil else { throw DesktopError("Создайте список в приложении «Напоминания».") }
            item.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .timeZone], from: date)
            try store.save(item, commit: true)
        } else {
            guard authorized else { throw DesktopError("Сначала разрешите доступ к календарю.") }
            let event = EKEvent(eventStore: store); event.title = title; event.notes = notes; event.startDate = date; event.endDate = date.addingTimeInterval(3600)
            event.calendar = calendarID.flatMap(store.calendar(withIdentifier:)) ?? store.defaultCalendarForNewEvents
            guard event.calendar != nil else { throw DesktopError("Создайте календарь в приложении «Календарь».") }
            try store.save(event, span: .thisEvent, commit: true)
        }
        await refresh()
    }
}
struct CalendarWorkspace: View {
    @StateObject private var calendar = DesktopCalendar()
    @State private var reminder = false
    @State private var editor = false
    @State private var title = ""
    @State private var notes = ""
    @State private var date = Date().addingTimeInterval(3600)
    @State private var calendarID = ""
    @State private var busy = false
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack { Text("Ваш день на Mac").font(.largeTitle.weight(.medium)); Spacer(); Button("Обновить") { Task { await calendar.refresh() } } }
            Picker("Список", selection: $reminder) { Text("Календарь").tag(false); Text("Напоминания").tag(true) }.pickerStyle(.segmented).frame(width: 320)
            Text("События и напоминания из ваших системных аккаунтов. Доступ запрашивается отдельно; данные не отправляются в облако NIKA.").foregroundStyle(.secondary)
            if reminder ? !calendar.remindersAuthorized : !calendar.authorized {
                Button(reminder ? "Подключить напоминания" : "Подключить календарь") { Task { await calendar.connect(reminders: reminder) } }.buttonStyle(.borderedProminent)
            } else {
                Button(reminder ? "Новое напоминание" : "Новое событие") { title = ""; notes = ""; calendarID = ""; editor = true }
                ScrollView { LazyVStack(alignment: .leading, spacing: 12) {
                    if reminder {
                        if calendar.reminders.isEmpty { EmptyWorkspace(symbol: "checkmark.circle", title: "Всё сделано", detail: "Новых напоминаний пока нет.") }
                        ForEach(calendar.reminders, id: \.calendarItemIdentifier) { item in
                            HStack {
                                Button { Task { do { item.isCompleted = true; try calendar.store.save(item, commit: true); await calendar.refresh() } catch { calendar.error = error.localizedDescription } } } label: { Image(systemName: "circle") }.buttonStyle(.plain)
                                VStack(alignment: .leading) { Text(item.title ?? "Напоминание"); if let due = item.dueDateComponents?.date { Text(due.formatted()).font(.caption).foregroundStyle(.secondary) } }; Spacer(); Text(item.calendar.title).font(.caption).foregroundStyle(.secondary)
                            }.padding(16).nikaGlass()
                        }
                    } else {
                        if calendar.events.isEmpty { EmptyWorkspace(symbol: "calendar", title: "Есть место для планов", detail: "На ближайшие 30 дней событий нет.") }
                        ForEach(calendar.events, id: \.eventIdentifier) { event in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(event.title ?? "Событие").font(.headline)
                                Text(event.startDate.formatted()).foregroundStyle(.secondary)
                                if let location = event.location, !location.isEmpty { Label(location, systemImage: "mappin") }
                                Text(event.calendar.title).font(.caption).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(18).nikaGlass()
                        }
                    }
                } }
            }
            if let error = calendar.error { Text(error).foregroundStyle(.red); Button("Открыть настройки доступа") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security")!) } }
            Spacer(minLength: 0)
        }.padding(32).task { await calendar.refresh() }
        .sheet(isPresented: $editor) {
            VStack(alignment: .leading, spacing: 20) {
                Text(reminder ? "Новое напоминание" : "Новое событие").font(.title2)
                TextField("Название", text: $title).textFieldStyle(.roundedBorder)
                TextField("Заметки", text: $notes, axis: .vertical).lineLimit(2...4).textFieldStyle(.roundedBorder)
                DatePicker("Когда", selection: $date)
                Picker("Календарь / список", selection: $calendarID) {
                    Text("По умолчанию").tag("")
                    ForEach(calendar.store.calendars(for: reminder ? .reminder : .event).filter(\.allowsContentModifications), id: \.calendarIdentifier) { item in Text(item.title).tag(item.calendarIdentifier) }
                }
                if let error = calendar.error { Text(error).foregroundStyle(.red) }
                HStack { Button("Отмена") { editor = false }; Spacer(); Button("Сохранить") { busy = true; Task { defer { busy = false }; do { try await calendar.create(title: title, notes: notes, date: date, reminder: reminder, calendarID: calendarID.isEmpty ? nil : calendarID); editor = false } catch { calendar.error = error.localizedDescription } } }.buttonStyle(.borderedProminent).disabled(title.isEmpty || busy) }
            }.padding(28).frame(width: 460)
        }
    }
}
