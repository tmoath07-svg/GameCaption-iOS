import UIKit
import XCTest
@testable import GameCaption

final class SubtitlePipelineTests: XCTestCase {
    func testCaptionChangesDeduplicateWhitespaceAndClearAfterTwoEmptyFrames() {
        var changes = SubtitleChanges()
        XCTAssertEqual(changes.update("  Press   Start\r\n  to continue  "), "Press Start\nto continue")
        XCTAssertNil(changes.update("Press Start\nto continue"))
        XCTAssertNil(changes.update(""))
        XCTAssertNil(changes.update("Press Start\nto continue"))
        XCTAssertNil(changes.update(""))
        XCTAssertEqual(changes.update(" "), "")
        XCTAssertNil(changes.update(""))
        XCTAssertEqual(changes.update("Press Start\nto continue"), "Press Start\nto continue")
    }

    @MainActor
    func testVisionRecognizesRenderedEnglishCaption() async throws {
        let size = CGSize(width: 900, height: 240)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            ("Press Start to continue" as NSString).draw(
                at: CGPoint(x: 40, y: 140),
                withAttributes: [.font: UIFont.systemFont(ofSize: 56, weight: .semibold),
                                 .foregroundColor: UIColor.white]
            )
        }
        let data = try XCTUnwrap(image.pngData())
        let result = try await OCRService.importImage(data: data, language: "en")
        XCTAssertEqual(result.text, "Press Start to continue")
    }

    func testSubtitleRegionStaysInFrame() {
        XCTAssertEqual(SubtitleRegion(bottom: 0, height: 0.35).rectangle,
                       CGRect(x: 0, y: 0, width: 1, height: 0.35))
        XCTAssertEqual(SubtitleRegion(bottom: 0.9, height: 0.5).rectangle,
                       CGRect(x: 0, y: 0.5, width: 1, height: 0.5))
    }

    func testBroadcastExchangesSettingsAndAnAtomicCaption() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let writer = try XCTUnwrap(BroadcastExchange(container: directory))
        let reader = try XCTUnwrap(BroadcastExchange(container: directory))
        XCTAssertNil(try reader.snapshot())
        XCTAssertFalse(try reader.hostIsForeground())
        try writer.writeHostForeground(true)
        XCTAssertTrue(try reader.hostIsForeground())
        let settings = CaptureSettings(region: SubtitleRegion(bottom: 0.15, height: 0.25))
        try writer.writeSettings(settings)
        XCTAssertEqual(try reader.settings(), settings)
        let caption = CaptureSnapshot(settings: settings, source: "Play", translation: "العب")
        try writer.writeSnapshot(caption)
        XCTAssertEqual(try reader.snapshot(), caption)
        let cleared = CaptureSnapshot(active: false, settings: settings)
        try writer.writeSnapshot(cleared)
        XCTAssertEqual(try reader.snapshot(), cleared)
    }
}
