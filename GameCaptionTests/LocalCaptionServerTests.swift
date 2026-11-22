import Foundation
import XCTest
@testable import GameCaption

@MainActor
final class LocalCaptionServerTests: XCTestCase {
    func testBrowserCanReadCurrentCaptionAndUnauthorizedRequestsAreRejected() async throws {
        let server = LocalCaptionServer(port: .any, interfaceAddress: { "127.0.0.1" })
        defer { server.stop() }
        server.start()
        for _ in 0..<100 where !server.running {
            try await Task.sleep(for: .milliseconds(25))
        }
        let browser = try XCTUnwrap(URL(string: server.urlString))
        let overlay = try XCTUnwrap(URL(string: server.overlayURLString))
        var caption = try XCTUnwrap(URLComponents(url: browser, resolvingAgainstBaseURL: false))
        caption.path = "/caption"
        let endpoint = try XCTUnwrap(caption.url)
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let (page, pageResponse) = try await session.data(from: overlay)
        XCTAssertEqual((pageResponse as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertTrue(String(decoding: page, as: UTF8.self).contains("body.overlay{background:transparent}"))
        server.subtitle = "اضغط للمتابعة"
        let (data, response) = try await session.data(from: endpoint)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(try JSONDecoder().decode([String: String].self, from: data)["subtitle"], "اضغط للمتابعة")
        server.subtitle = ""
        let (cleared, _) = try await session.data(from: endpoint)
        XCTAssertEqual(try JSONDecoder().decode([String: String].self, from: cleared)["subtitle"], "")
        caption.query = nil
        let unauthenticated = try XCTUnwrap(caption.url)
        let (_, denied) = try await session.data(from: unauthenticated)
        XCTAssertEqual((denied as? HTTPURLResponse)?.statusCode, 403)
    }
}
