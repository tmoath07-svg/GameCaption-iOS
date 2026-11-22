import XCTest
@testable import GameCaption

@MainActor
final class CaptionStoreTests: XCTestCase {
    func testRecordEncodesAndDecodes() throws {
        let record = CaptionRecord(source: "Hello", translation: "مرحبًا", from: "en", to: "ar")
        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(CaptionRecord.self, from: data)
        XCTAssertEqual(decoded.source, "Hello")
        XCTAssertEqual(decoded.translation, "مرحبًا")
        XCTAssertEqual(decoded.from, "en")
        XCTAssertEqual(decoded.to, "ar")
    }

    func testHistoryDeduplicatesAndSaves() {
        UserDefaults.standard.removeObject(forKey: "gamecaption.history.v1")
        defer { UserDefaults.standard.removeObject(forKey: "gamecaption.history.v1") }
        let store = CaptionStore()
        store.add(source: "Play", result: "العب", sourceLanguage: "en", targetLanguage: "ar")
        store.add(source: "Play", result: "العب", sourceLanguage: "en", targetLanguage: "ar")
        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(CaptionStore().items.first?.translation, "العب")
    }
}
