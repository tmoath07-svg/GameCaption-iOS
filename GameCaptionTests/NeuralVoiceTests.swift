#if GAMECAPTION_NEURAL_VOICE
import AVFoundation
import XCTest
@testable import GameCaption

final class NeuralVoiceTests: XCTestCase {
    func testArabicModelGeneratesPlayablePCM() throws {
        let root = try XCTUnwrap(Bundle.main.resourceURL).appendingPathComponent("NeuralArabicVoice")
        let wav = try OfflineArabicVoice.generate("مرحباً بك. اضغط زر البدء للمتابعة.", resources: root)
        let audio = try AVAudioPlayer(data: wav)
        XCTAssertGreaterThan(audio.duration, 0.5)
        XCTAssertEqual(audio.format.sampleRate, 24_000)
        XCTAssertEqual(audio.numberOfChannels, 1)
    }
}
#endif
