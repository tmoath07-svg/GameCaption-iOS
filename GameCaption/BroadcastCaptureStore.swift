import Foundation
import Combine

/// Shared state read by the host app from a user-initiated ReplayKit broadcast extension.
@MainActor
final class BroadcastCaptureStore: ObservableObject {
    static let appGroup = "group.com.tmoath07.gamecaption"
    @Published private(set) var isBroadcasting = false
    @Published private(set) var recognizedText = ""
    @Published private(set) var translatedText = ""
    @Published private(set) var statusText = "ابدأ بث الشاشة من زر النظام ثم افتح تطبيق اللعب."
    @Published private(set) var revision = ""
    @Published private(set) var updatedAt: Date?

    private var defaults: UserDefaults? { UserDefaults(suiteName: Self.appGroup) }

    func configure(source: String, target: String) {
        defaults?.set(source, forKey: "capture.sourceLanguage")
        defaults?.set(target, forKey: "capture.targetLanguage")
    }

    func refresh() {
        guard let defaults else {
            statusText = "تعذر الوصول لمجموعة التطبيق. تأكد من توقيع التطبيق والإضافة بصلاحية App Groups."
            return
        }
        isBroadcasting = defaults.bool(forKey: "capture.active")
        let currentRevision = defaults.string(forKey: "capture.revision") ?? ""
        let newText = defaults.string(forKey: "capture.sourceText") ?? ""
        let newTranslation = defaults.string(forKey: "capture.translatedText") ?? ""
        if currentRevision != revision { revision = currentRevision }
        if newText != recognizedText { recognizedText = newText }
        if newTranslation != translatedText { translatedText = newTranslation }
        let status = defaults.string(forKey: "capture.status") ?? ""
        statusText = status.isEmpty ? (isBroadcasting ? "البث شغّال." : "البث متوقف.") : status
        let time = defaults.double(forKey: "capture.updatedAt")
        updatedAt = time > 0 ? Date(timeIntervalSince1970: time) : nil
    }
}
