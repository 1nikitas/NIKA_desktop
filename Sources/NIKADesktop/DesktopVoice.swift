import Foundation
import Speech
import AVFoundation

@MainActor
final class DesktopVoice: NSObject, ObservableObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    @Published var transcript = ""
    @Published var recording = false
    @Published private(set) var inputLevel = 0.0
    private var meteringTask: Task<Void, Never>?
    @Published var error: String?
    @Published var speaking = false
    @Published var transcribing = false
    var finishedSpeaking: (() -> Void)?
    private var recorder: AVAudioRecorder?
    private var recordingFile: URL?
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognition: SFSpeechRecognitionTask?
    private let speaker = AVSpeechSynthesizer()
    private var remoteTask: Task<Void, Never>?
    private var player: AVAudioPlayer?
    private var speechLease = UUID()
    private var recordingLease = UUID()
    override init() { super.init(); speaker.delegate = self }
    func toggle(client: BFFClient?, local: Bool) async {
        if recorder != nil { await finishServer(client: client); return }
        if recording { stop(); return }
        if UserDefaults.standard.string(forKey: "speechRecognition") == "server", !local {
            guard client != nil else { error = "Для серверной диктовки войдите в NIKA."; return }
            let lease = recordingLease
            guard await AVCaptureDevice.requestAccess(for: .audio) else { error = "Разрешите доступ к микрофону."; return }
            guard lease == recordingLease, !Task.isCancelled else { return }
            do {
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("nika-dictation-\(UUID().uuidString).m4a")
                let recorder = try AVAudioRecorder(url: url, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 24000, AVNumberOfChannelsKey: 1, AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue])
                recorder.isMeteringEnabled = true
                guard recorder.record(forDuration: 120) else { throw DesktopError("Не удалось начать запись.") }
                self.recorder = recorder; recordingFile = url; recording = true; transcript = ""; error = nil
                startMetering(lease: lease) { [weak recorder] in recorder?.updateMeters(); return recorder.map { VoiceLevel.normalized(decibels: $0.averagePower(forChannel: 0)) } ?? 0 }
            } catch { self.error = error.localizedDescription }
        } else { await start() }
    }
    private func finishServer(client: BFFClient?) async {
        stopMetering(); recorder?.stop(); recorder = nil; recording = false
        guard let url = recordingFile, let client else { return }
        recordingFile = nil; transcribing = true
        defer { transcribing = false; try? FileManager.default.removeItem(at: url) }
        do { transcript = try await client.transcribe(audio: Data(contentsOf: url), filename: "dictation.m4a", mimeType: "audio/mp4", language: Locale.current.language.languageCode?.identifier ?? "ru") }
        catch { self.error = error.localizedDescription }
    }
    func start() async {
        stop(); let lease = recordingLease
        error = nil
        let microphone = await AVCaptureDevice.requestAccess(for: .audio)
        guard lease == recordingLease, !Task.isCancelled else { return }
        guard microphone else { error = "Разрешите микрофон в Системных настройках → Конфиденциальность."; return }
        let authorization = await withCheckedContinuation { continuation in SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) } }
        guard lease == recordingLease, !Task.isCancelled else { return }
        guard authorization == .authorized else { error = "Разрешите распознавание речи в Системных настройках."; return }
        guard let recognizer = SFSpeechRecognizer(locale: .current), recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            error = "Офлайн-распознавание Apple для текущего языка недоступно. Используйте текстовый ввод."; return
        }
        transcript = ""
        let request = SFSpeechAudioBufferRecognitionRequest(); request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true; self.request = request
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { error = "Микрофон недоступен."; return }
        let mailbox = VoiceLevelMailbox()
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer); mailbox.accept(buffer) }
        recording = true
        recognition = recognizer.recognitionTask(with: request) { [weak self] result, failure in
            Task { @MainActor in
                guard self?.recordingLease == lease else { return }
                if let result { self?.transcript = result.bestTranscription.formattedString; if result.isFinal { self?.stop() } }
                if let failure, self?.recording == true { self?.error = failure.localizedDescription; self?.stop() }
            }
        }
        do { engine.prepare(); try engine.start(); startMetering(lease: lease) { mailbox.read() } } catch { self.error = error.localizedDescription; stop() }
    }
    func stop() {
        recordingLease = UUID(); stopMetering()
        if recorder != nil { recorder?.stop(); recorder = nil; if let recordingFile { try? FileManager.default.removeItem(at: recordingFile) }; recordingFile = nil }
        else if recording { engine.stop(); engine.inputNode.removeTap(onBus: 0) }
        recording = false; request?.endAudio(); recognition?.cancel(); recognition = nil; request = nil
    }
    private func startMetering(lease: UUID, sample: @escaping @MainActor () -> Double) {
        stopMetering()
        meteringTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.recording, self.recordingLease == lease else { return }
                self.inputLevel = VoiceLevel.smoothed(sample(), previous: self.inputLevel)
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }
    private func stopMetering() { meteringTask?.cancel(); meteringTask = nil; inputLevel = 0 }
    func speak(_ text: String, local: Bool = true) {
        stopSpeaking(); error = nil
        if !local && UserDefaults.standard.string(forKey: "speechProvider") == "elevenlabs" {
            speaking = true; let lease = speechLease
            remoteTask = Task {
                do {
                    let keys = try await Task.detached { try DesktopSpeechKeys.read() }.value
                    try Task.checkCancellation()
                    let session = URLSession(configuration: try keys.configuration(), delegate: SpeechRedirectDelegate(), delegateQueue: nil)
                    defer { session.invalidateAndCancel() }
                    let (data, response) = try await session.data(for: keys.request(text))
                    try Task.checkCancellation(); guard lease == speechLease else { return }
                    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), http.mimeType?.hasPrefix("audio/") == true else { throw DesktopError("ElevenLabs не вернул аудио. Проверьте ключ, Voice ID, квоту и доступность сервиса.") }
                    let player = try AVAudioPlayer(data: data); player.delegate = self; self.player = player
                    guard player.play() else { throw DesktopError("Не удалось воспроизвести голос.") }
                } catch is CancellationError {} catch { guard lease == speechLease else { return }; self.error = error.localizedDescription; speaking = false }
            }; return
        }
        let utterance = AVSpeechUtterance(string: text)
        if let id = UserDefaults.standard.string(forKey: "speechVoice") { utterance.voice = AVSpeechSynthesisVoice(identifier: id) }
        utterance.rate = Float(UserDefaults.standard.double(forKey: "speechRate").nonzeroOr(0.5))
        speaking = true; speaker.speak(utterance)
    }
    func stopSpeaking() { speechLease = UUID(); remoteTask?.cancel(); remoteTask = nil; player?.stop(); player = nil; speaker.stopSpeaking(at: .immediate); speaking = false }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) { Task { @MainActor in guard self.player === player else { return }; self.player = nil; self.speaking = false; if flag { self.finishedSpeaking?() } else { self.error = "Воспроизведение прервалось." } } }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) { Task { @MainActor in self.speaking = false; self.finishedSpeaking?() } }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) { Task { @MainActor in self.speaking = false } }
}
private extension Double { func nonzeroOr(_ fallback: Double) -> Double { self == 0 ? fallback : self }
}
