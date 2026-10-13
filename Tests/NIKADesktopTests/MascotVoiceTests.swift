import XCTest
import AVFoundation
@testable import NIKADesktop

final class MascotVoiceTests: XCTestCase {
    func testPCMAndRecorderLevelsAgree() {
        let samples: [Float] = [0.05, -0.05, 0.05, -0.05]
        let pcm = samples.withUnsafeBufferPointer { VoiceLevel.normalized(rms: VoiceLevel.rms($0)) }
        XCTAssertEqual(pcm, 0.35, accuracy: 0.0001)
        XCTAssertEqual(VoiceLevel.normalized(decibels: Float(20 * log10(0.05))), pcm, accuracy: 0.0001)
        XCTAssertGreaterThan(VoiceLevel.shaped(pcm), pcm, "Quiet speech must visibly light the glow")
        XCTAssertEqual(VoiceLevel.normalized(rms: .nan), 0)
        XCTAssertEqual(VoiceLevel.normalized(rms: 2), 1)
        XCTAssertEqual(VoiceLevel.normalized(decibels: -.infinity), 0)
    }
    func testSilenceReleasesGlow() {
        var level = VoiceLevel.smoothed(1, previous: 0)
        XCTAssertGreaterThan(level, 0.5)
        for _ in 0..<30 { level = VoiceLevel.smoothed(0, previous: level) }
        XCTAssertEqual(level, 0)
    }
    func testAudioMailboxExpiresAfterCaptureStops() async throws {
        let mailbox = VoiceLevelMailbox()
        XCTAssertEqual(mailbox.read(), 0)
        let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 320)!
        buffer.frameLength = 320
        for i in 0..<320 { buffer.floatChannelData![0][i] = i % 2 == 0 ? 0.1 : -0.1 }
        mailbox.accept(buffer)
        XCTAssertEqual(mailbox.read(), 0.7, accuracy: 0.0001)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(mailbox.read(), 0, "Stopped capture must not leave a bright glow")
    }
    @MainActor func testEveryMascotPoseIsBundled() {
        for pose in MascotPose.allCases {
            let image = MascotAssets.image(pose)
            XCTAssertGreaterThan(image.size.width, 100, pose.rawValue)
            XCTAssertNotNil(image.tiffRepresentation, pose.rawValue)
        }
    }
}
