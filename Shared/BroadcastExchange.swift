import Foundation

struct CaptureSettings: Codable, Equatable {
    var source = "en"
    var target = "ar"
    var translate = true
    var region = SubtitleRegion()
}

struct CaptureSnapshot: Codable, Equatable {
    var active = true
    var revision = UUID()
    var settings: CaptureSettings
    var source = ""
    var translation = ""
    var status = ""
    var updated = Date()
}

struct BroadcastExchange {
    static let group = "group.com.tmoath07.gamecaption"
    let directory: URL

    init?(container: URL? = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: BroadcastExchange.group)) {
        guard let container else { return nil }
        directory = container
    }

    func settings() throws -> CaptureSettings {
        try read("capture-settings.json") ?? CaptureSettings()
    }

    func writeSettings(_ settings: CaptureSettings) throws {
        try write(settings, to: "capture-settings.json")
    }

    func snapshot() throws -> CaptureSnapshot? {
        try read("capture-snapshot.json")
    }

    func writeSnapshot(_ snapshot: CaptureSnapshot) throws {
        try write(snapshot, to: "capture-snapshot.json")
    }

    private func read<T: Decodable>(_ name: String) throws -> T? {
        do {
            return try JSONDecoder().decode(T.self, from: Data(contentsOf: directory.appendingPathComponent(name)))
        } catch CocoaError.fileReadNoSuchFile {
            return nil
        }
    }

    private func write<T: Encodable>(_ value: T, to name: String) throws {
        try JSONEncoder().encode(value).write(to: directory.appendingPathComponent(name),
                                             options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
