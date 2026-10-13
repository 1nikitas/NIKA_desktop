import SwiftUI
import AVFoundation
@preconcurrency import WebRTC

/// The same NIKA live protocol as iPhone, using macOS CoreAudio through WebRTC.
@MainActor final class LiveDesktopVoice: ObservableObject {
    @Published var status = "Готов к разговору"
    @Published var active = false
    @Published var connected = false
    @Published var muted = false
    @Published private(set) var inputLevel = 0.0
    @Published private(set) var outputLevel = 0.0
    private var meteringTask: Task<Void, Never>?
    @Published var transcript = ""
    @Published var error: String?
    var onDelegation: ((String, String) -> Void)?
    private var lastUser = ""
    private var speaker: LiveVoiceTranscriptDelta.Speaker?
    private var peer: RTCPeerConnection?
    private var channel: RTCDataChannel?
    private var track: RTCAudioTrack?
    private var observer: VoiceRTCObserver?
    private var task: Task<Void, Never>?
    private var lease = UUID()
    private static let factory: RTCPeerConnectionFactory = { RTCInitializeSSL(); return RTCPeerConnectionFactory(encoderFactory: nil, decoderFactory: nil) }()

    static func makePeer(delegate: RTCPeerConnectionDelegate?) throws -> RTCPeerConnection {
        let configuration = RTCConfiguration(); configuration.sdpSemantics = .unifiedPlan
        guard let peer = factory.peerConnection(with: configuration, constraints: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil), delegate: delegate) else { throw DesktopError("Не удалось открыть голосовое соединение.") }
        return peer
    }
    static func offer(_ peer: RTCPeerConnection) async throws -> RTCSessionDescription {
        try await withCheckedThrowingContinuation { continuation in
            peer.offer(for: RTCMediaConstraints(mandatoryConstraints: ["OfferToReceiveAudio": "true"], optionalConstraints: nil)) { value, error in
                if let value { continuation.resume(returning: value) } else { continuation.resume(throwing: error ?? DesktopError("Не удалось подготовить голосовое соединение.")) }
            }
        }
    }
    func start(client: BFFClient) {
        guard !active else { return }; stop(); active = true; error = nil; transcript = ""; lastUser = ""; speaker = nil; status = "Подключение…"
        let current = lease
        task = Task {
            do {
                guard await AVCaptureDevice.requestAccess(for: .audio) else { throw DesktopError("Разрешите доступ к микрофону в настройках macOS.") }
                try Task.checkCancellation(); guard current == lease else { return }
                let observer = VoiceRTCObserver { [weak self] signal in Task { @MainActor in guard let self, self.lease == current else { return }; self.receive(signal) } }
                self.observer = observer
                let peer = try Self.makePeer(delegate: observer); self.peer = peer
                let source = Self.factory.audioSource(with: RTCMediaConstraints(mandatoryConstraints: ["googEchoCancellation": "true", "googNoiseSuppression": "true"], optionalConstraints: nil))
                let track = Self.factory.audioTrack(with: source, trackId: "nika-microphone"); track.isEnabled = false; self.track = track
                peer.add(track, streamIds: ["nika-live"])
                let configuration = RTCDataChannelConfiguration()
                guard let channel = peer.dataChannel(forLabel: "oai-events", configuration: configuration) else { throw DesktopError("Не удалось открыть канал голоса.") }
                channel.delegate = observer; self.channel = channel
                let offer = try await Self.offer(peer)
                try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in peer.setLocalDescription(offer) { if let error = $0 { c.resume(throwing: error) } else { c.resume() } } }
                for _ in 0..<20 { if peer.iceGatheringState == .complete { break }; try await Task.sleep(for: .milliseconds(100)) }
                let answer = try await client.createLiveVoiceSession(sdp: peer.localDescription?.sdp ?? offer.sdp, language: "ru")
                try Task.checkCancellation(); guard current == lease else { return }
                try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in peer.setRemoteDescription(RTCSessionDescription(type: .answer, sdp: answer.sdp)) { if let error = $0 { c.resume(throwing: error) } else { c.resume() } } }
                guard current == lease else { return }; track.isEnabled = true
                startMetering(peer, lease: current)
                try await Task.sleep(for: .seconds(20))
                if current == lease && !connected { throw DesktopError("Голосовое соединение не установилось. Попробуйте ещё раз или выберите обычный разговор.") }
            } catch is CancellationError {} catch { guard current == lease else { return }; self.error = error.localizedDescription; stop() }
        }
    }
    func mute() { muted.toggle(); if muted { inputLevel = 0 }; track?.isEnabled = !muted; send(.muteInput(muted)) }
    func commentary(id: String, text: String) { send(.commentaryAppend(delegationID: id, content: text, eventID: UUID().uuidString)) }
    private func send(_ event: LiveVoiceClientEvent) { if let data = try? event.encoded(), channel?.readyState == .open { _ = channel?.sendData(RTCDataBuffer(data: data, isBinary: false)) } }
    func stop() {
        meteringTask?.cancel(); meteringTask = nil; inputLevel = 0; outputLevel = 0
        send(.close); lease = UUID(); task?.cancel(); task = nil; track?.isEnabled = false
        channel?.close(); channel = nil; peer?.close(); peer = nil; track = nil; observer = nil; active = false; connected = false; muted = false; status = "Разговор завершён"
    }
    private func startMetering(_ peer: RTCPeerConnection, lease current: UUID) {
        meteringTask?.cancel()
        meteringTask = Task { [weak self] in
            while !Task.isCancelled {
                let levels: (Double, Double) = await withCheckedContinuation { continuation in
                    peer.statistics { report in
                        var input = 0.0, output = 0.0
                        for statistic in report.statistics.values where (statistic.values["kind"] as? String) == "audio" {
                            let level = (statistic.values["audioLevel"] as? NSNumber)?.doubleValue ?? 0
                            if statistic.type == "media-source" { input = max(input, level) }
                            if statistic.type == "inbound-rtp" { output = max(output, level) }
                        }
                        continuation.resume(returning: (input, output))
                    }
                }
                guard let self, !Task.isCancelled, self.lease == current else { return }
                self.inputLevel = self.muted ? 0 : VoiceLevel.smoothed(levels.0, previous: self.inputLevel)
                self.outputLevel = VoiceLevel.smoothed(levels.1, previous: self.outputLevel)
                try? await Task.sleep(for: .milliseconds(80))
            }
        }
    }
    private func receive(_ signal: VoiceRTCObserver.Signal) {
        switch signal {
        case .channel(let state): if state == .open { connected = true; status = "Я слушаю — можно перебивать" }
        case .connection(let state):
            if state == .failed || state == .disconnected { error = "Голосовое соединение прервалось. Подключитесь ещё раз."; stop() }
        case .data(let data):
            guard let event = LiveVoiceServerEvent.parse(data) else { return }
            switch event {
            case .transcript(let delta):
                if speaker != delta.speaker { transcript += "\n\n" + (delta.speaker == .user ? "Вы: " : "NIKA: "); if delta.speaker == .user { lastUser = "" }; speaker = delta.speaker }
                transcript += delta.text; if delta.speaker == .user { lastUser += delta.text }
            case .delegationCreated(let id, _): onDelegation?(id, lastUser)
            case .error(_, let message, _): error = message
            case .sessionClosed: stop()
            default: break
            }
        }
    }
}
private final class VoiceRTCObserver: NSObject, RTCPeerConnectionDelegate, RTCDataChannelDelegate, @unchecked Sendable {
    enum Signal { case connection(RTCPeerConnectionState), channel(RTCDataChannelState), data(Data) }
    let handler: (Signal) -> Void
    init(handler: @escaping (Signal) -> Void) { self.handler = handler }
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCPeerConnectionState) { handler(.connection(newState)) }
    func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) { handler(.channel(dataChannel.readyState)) }
    func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) { handler(.data(buffer.data)) }
}

struct LiveDesktopVoiceView: View {
    @ObservedObject var workspace: Workspace
    @StateObject private var voice = LiveDesktopVoice()
    @State private var delegation: String?
    var body: some View {
        VStack(spacing: 16) {
            DesktopMascot(pose: workspace.sending ? .thinking : voice.outputLevel > 0.02 ? .speaking : .idle, size: 144)
            Text(voice.status).font(.title2)
            ScrollView { Text(voice.transcript.isEmpty ? "Говорите естественно. NIKA слышит вас и отвечает голосом." : voice.transcript).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(height: 120)
            if let error = voice.error { Text(error).font(.callout).foregroundStyle(.red) }
            HStack {
                if voice.active { Button(voice.muted ? "Включить микрофон" : "Выключить микрофон") { voice.mute() }; Button("Завершить") { finish() } }
                else { Button("Начать живой разговор") { if let client = workspace.store.client { voice.start(client: client) } }.buttonStyle(.borderedProminent).disabled(workspace.store.client == nil || workspace.sending) }
            }
            Text("Аудио передаётся в облачный голосовой сервис NIKA. Доступен только для облачных разговоров.").font(.caption).foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { AuroraCanvas(level: voice.inputLevel, listening: voice.connected && !voice.muted) }
        .onAppear { voice.onDelegation = { id, text in
            guard !workspace.sending, workspace.draft.isEmpty, !text.isEmpty else { voice.commentary(id: id, text: "В чате уже есть незавершённое действие или черновик. Попроси пользователя завершить его."); return }
            delegation = id; workspace.draft = text; workspace.send()
        } }
        .onChange(of: workspace.sending) { _, sending in
            guard !sending, let id = delegation else { return }; delegation = nil
            voice.commentary(id: id, text: workspace.error ?? workspace.messages.last(where: { $0.role == "assistant" })?.content ?? "Не удалось получить результат.")
        }
        .onChange(of: workspace.store.login?.session.clientID) { _, _ in finish() }
        .onDisappear { finish() }
    }
    private func finish() { voice.stop(); if delegation != nil { workspace.stop(); delegation = nil } }
}
