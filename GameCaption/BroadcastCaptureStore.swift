import Foundation
import Combine

@MainActor
final class BroadcastCaptureStore: ObservableObject {
    @Published private(set) var statusText = "ابدأ بث الشاشة من زر النظام ثم افتح تطبيق اللعب."
    @Published private(set) var settingsError: String?
    private let exchange = BroadcastExchange()

    func configure(_ settings: CaptureSettings) {
        guard let exchange else {
            settingsError = "مجموعة التطبيق غير متاحة. تحقق من توقيع التطبيق والإضافة بصلاحية App Groups."
            return
        }
        do {
            try exchange.writeSettings(settings)
            settingsError = nil
        } catch {
            settingsError = "تعذر حفظ إعدادات البث: \(error.localizedDescription)"
        }
    }

    func refresh() -> CaptureSnapshot? {
        guard let exchange else { return nil }
        do {
            guard let snapshot = try exchange.snapshot() else { return nil }
            if snapshot.active && Date().timeIntervalSince(snapshot.updated) > 12 {
                statusText = "توقفت الإطارات. إذا انتهى البث فابدأه مجددًا من زر النظام."
                return nil
            }
            if statusText != snapshot.status { statusText = snapshot.status }
            return snapshot
        } catch {
            statusText = "تعذر قراءة حالة البث: \(error.localizedDescription)"
            return nil
        }
    }
}
