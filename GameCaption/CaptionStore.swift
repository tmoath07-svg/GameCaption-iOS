import Foundation
import SwiftUI

struct CaptionRecord: Identifiable, Codable {
    var id: UUID = UUID()
    var source: String
    var translation: String
    var from: String
    var to: String
    var createdAt: Date = Date()
}

@MainActor
final class CaptionStore: ObservableObject {
    @Published private(set) var items: [CaptionRecord] = []
    private let storageKey = "gamecaption.history.v1"

    init() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([CaptionRecord].self, from: data)
        else { return }
        items = decoded
    }

    func add(source: String, result: String, sourceLanguage: String, targetLanguage: String) {
        guard !result.isEmpty else { return }
        if let first = items.first, first.source == source,
           first.translation == result, first.from == sourceLanguage, first.to == targetLanguage { return }
        items.insert(.init(source: source, translation: result,
                           from: sourceLanguage, to: targetLanguage), at: 0)
        if items.count > 100 { items.removeLast(items.count - 100) }
        save()
    }

    func remove(at offsets: IndexSet) {
        items.remove(atOffsets: offsets)
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
