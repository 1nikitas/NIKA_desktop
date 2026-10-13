import SwiftUI

struct StandardVoiceConversationView: View {
    @ObservedObject var workspace: Workspace
    @StateObject private var voice = DesktopVoice()
    @Environment(\.dismiss) private var dismiss
    @State private var active = false
    @State private var silence: Task<Void, Never>?
    @State private var spokenID: String?
    @State private var submitted = false
    var body: some View {
        ScrollView { VStack(spacing: 18) {
            HStack { Text("Голосовой разговор").font(.headline); Spacer(); Button("Готово") { end(); dismiss() } }
            Spacer()
            DesktopMascot(pose: workspace.sending ? .thinking : voice.speaking ? .speaking : .idle, size: 176)
            Text(workspace.sending ? "NIKA думает…" : voice.speaking ? "NIKA отвечает" : voice.recording ? "Я слушаю" : "Поговорим?").font(.title)
            ScrollView {
                Text(voice.recording ? voice.transcript : workspace.messages.last?.content ?? "Начните говорить. После паузы NIKA отправит вашу фразу и прочитает ответ.")
                    .font(.body).multilineTextAlignment(.center).textSelection(.enabled).frame(maxWidth: 480)
            }.frame(height: 120)
            if let error = voice.error ?? workspace.error { Text(error).foregroundStyle(.red).font(.callout) }
            HStack(spacing: 16) {
                if active {
                    Button("Завершить разговор") { end() }
                    if voice.recording { Button("Отправить сейчас") { submit() }.disabled(voice.transcript.isEmpty) }
                    else { Button("Перебить и говорить") { workspace.stop(); voice.stopSpeaking(); Task { await voice.start() } } }
                } else { Button("Начать") { active = true; Task { await voice.start() } }.buttonStyle(.borderedProminent) }
            }
            Text(workspace.isLocal ? "Распознавание и ответ — на этом Mac." : "Apple распознаёт речь на Mac. Текст отправляется в ваш облачный разговор.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Spacer()
        }.padding(28) }.frame(maxWidth: .infinity, maxHeight: .infinity).background { AuroraCanvas(level: voice.inputLevel, listening: voice.recording) }
        .onChange(of: voice.transcript) { _, text in
            silence?.cancel(); guard active, voice.recording, !text.isEmpty else { return }
            silence = Task { try? await Task.sleep(for: .milliseconds(1700)); guard !Task.isCancelled else { return }; submit() }
        }
        .onChange(of: workspace.sending) { _, sending in
            guard active, submitted, !sending else { return }; submitted = false
            guard workspace.error == nil, let answer = workspace.messages.last, answer.role == "assistant", !answer.content.isEmpty, answer.id != spokenID else { return }
            spokenID = answer.id; voice.speak(answer.content, local: workspace.isLocal)
        }
        .onAppear { voice.finishedSpeaking = { if active { Task { await voice.start() } } } }
        .onDisappear { end() }
    }
    private func submit() {
        guard active, !workspace.sending, !voice.transcript.isEmpty else { return }
        silence?.cancel(); let text = voice.transcript; voice.stop(); workspace.draft = text; submitted = true; workspace.send()
    }
    private func end() { active = false; silence?.cancel(); voice.finishedSpeaking = nil; voice.stop(); voice.stopSpeaking(); if submitted { workspace.stop(); submitted = false } }
}

struct VoiceConversationView: View {
    @ObservedObject var workspace: Workspace
    @State private var live = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 0) {
            if !workspace.isLocal {
                Picker("Режим разговора", selection: $live) {
                    Text("Обычный").tag(false)
                    Text("Живой · WebRTC").tag(true)
                }.pickerStyle(.segmented).padding([.top, .horizontal], 24)
            }
            if live && !workspace.isLocal {
                HStack { Text("Живой разговор").font(.headline); Spacer(); Button("Готово") { dismiss() } }.padding(24)
                ScrollView { LiveDesktopVoiceView(workspace: workspace) }
            } else { StandardVoiceConversationView(workspace: workspace) }
        }.frame(width: DesktopFormLayout.width(600), height: DesktopFormLayout.height(670)).background { AuroraCanvas() }
        .sheet(item: $workspace.localProposal, onDismiss: { workspace.resolveLocalAction(false) }) { action in LocalActionConfirmation(action: action, resolve: workspace.resolveLocalAction) }
    }
}
