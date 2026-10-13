import SwiftUI

struct PendingBrowserInput: Decodable { let request_id: String; let chat_id: String; let task_id: String; let question: String; let root_task_id: String? }

struct BrowserQuestion: Identifiable {
    let id: String; let chatID: String; let taskID: String; let question: String; let options: [String]
    var rootTaskID: String?
    init(pending: PendingBrowserInput) { id = pending.request_id; chatID = pending.chat_id; taskID = pending.task_id; question = pending.question; options = []; rootTaskID = pending.root_task_id }
    init?(event: BFFWebSocketEvent, chatID: String) {
        guard case .unknown("browser_input_requested") = event.type, let fields = event.rawFields, let taskID = event.taskID else { return nil }
        func string(_ keys: [String]) -> String? { for key in keys { if case .string(let value) = fields[key], !value.isEmpty { return value } }; return nil }
        guard let id = string(["request_id", "requestId", "input_id", "id"]), let question = string(["question", "prompt", "message", "text", "description", "data"]) else { return nil }
        self.id = id; self.chatID = chatID; self.taskID = taskID; self.question = question; rootTaskID = string(["root_task_id"])
        if case .array(let array) = fields["options"] { options = array.compactMap { if case .string(let value) = $0 { return value }; return nil } } else { options = [] }
    }
}
struct BrowserActivityView: View {
    @ObservedObject var workspace: Workspace
    @State private var answer = ""
    @State private var busy = false
    @State private var snapshot: BFFBrowserRunSnapshot?
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let question = workspace.browserRequest {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Нужен ваш ответ", systemImage: "person.crop.circle.badge.questionmark").font(.headline)
                    Text(question.question).textSelection(.enabled)
                    ForEach(question.options, id: \.self) { option in Button(option) { submit(option) }.disabled(busy) }
                    TextField("Ваш ответ", text: $answer, axis: .vertical).textFieldStyle(.roundedBorder)
                    Button("Отправить ответ") { submit(answer) }.disabled(answer.isEmpty || busy)
                }.padding(14).nikaGlass()
            }
            ForEach(Array(workspace.browserEvents.enumerated()), id: \.offset) { _, event in
                VStack(alignment: .leading, spacing: 8) {
                    Text(event.nextGoal ?? event.stepTitle ?? "Шаг браузера").font(.callout)
                    if let address = event.stepURL, let url = URL(string: address), ["https", "http"].contains(url.scheme ?? "") { Link(url.host ?? address, destination: url).font(.caption) }
                    if let path = event.screenshotURL, let client = workspace.store.client, let url = URL(string: path, relativeTo: client.baseURL)?.absoluteURL {
                        AuthenticatedImage(url: url, client: client).frame(maxHeight: 180)
                    }
                }
            }
            if let runID = workspace.browserEvents.last?.runID {
                Button("Подробности выполнения") { Task { do { snapshot = try await workspace.store.client?.browserRun(runID: runID) } catch { self.error = error.localizedDescription } } }
            }
            if let snapshot {
                Text(snapshot.status ?? "").font(.caption)
                ForEach(Array((snapshot.steps ?? []).enumerated()), id: \.offset) { _, step in
                    DisclosureGroup(step.nextGoal ?? step.title ?? "Шаг") { Text([step.thinking, step.memory, step.evaluationPreviousGoal].compactMap { $0 }.joined(separator: "\n\n")).font(.caption).textSelection(.enabled) }
                }
                if let result = snapshot.finalResult { Text(result).font(.callout) }
            }
            if let error { Text(error).foregroundStyle(.red).font(.caption) }
        }
    }
    private func submit(_ text: String) { busy = true; Task { await workspace.answerBrowser(text); busy = false; if workspace.browserRequest == nil { answer = "" } } }
}
