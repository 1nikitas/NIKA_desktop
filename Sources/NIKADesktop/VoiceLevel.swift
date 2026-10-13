import Foundation
import AVFoundation

/// Same RMS × 7 normalization as iPhone SpeechRecognitionService. No audio is retained.
enum VoiceLevel {
    static func normalized(rms: Double) -> Double { rms.isFinite ? min(1, max(0, rms * 7)) : 0 }
    static func normalized(decibels: Float) -> Double { decibels.isFinite ? normalized(rms: pow(10, Double(decibels) / 20)) : 0 }
    static func rms(_ samples: UnsafeBufferPointer<Float>) -> Double {
        guard !samples.isEmpty else { return 0 }
        let sum = samples.reduce(0.0) { $0 + Double($1) * Double($1) }
        return sqrt(sum / Double(samples.count))
    }
    static func shaped(_ level: Double) -> Double { pow(level.isFinite ? min(1, max(0, level)) : 0, 0.55) }
    static func smoothed(_ target: Double, previous: Double) -> Double {
        let target = target.isFinite ? min(1, max(0, target)) : 0
        let value = previous + (target - previous) * (target > previous ? 0.6 : 0.22)
        return value < 0.002 ? 0 : value
    }
}
/// The audio callback writes a scalar; the UI consumes it at 20 Hz instead of spawning
/// unbounded main-actor tasks from the realtime audio thread. Each capture owns a mailbox.
final class VoiceLevelMailbox: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0.0
    private var updated = 0.0
    func accept(_ buffer: AVAudioPCMBuffer) {
        guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else { return }
        let samples = UnsafeBufferPointer(start: channels[0], count: Int(buffer.frameLength))
        let level = VoiceLevel.normalized(rms: VoiceLevel.rms(samples))
        lock.lock(); value = level; updated = ProcessInfo.processInfo.systemUptime; lock.unlock()
    }
    func read() -> Double {
        lock.lock(); defer { lock.unlock() }
        return ProcessInfo.processInfo.systemUptime - updated < 0.25 ? value : 0
    }
}
