import Foundation
import ReplayKit
import Vision
import Translation
import CoreMedia
import ImageIO

/// System broadcast extension: OCR runs only after the user explicitly starts a ReplayKit broadcast.
/// No raw frames are retained or transmitted to an external server.
final class SampleHandler: RPBroadcastSampleHandler {
    private let worker = DispatchQueue(label: "com.tmoath07.gamecaption.broadcast.ocr", qos: .userInitiated)
    private let suite = "group.com.tmoath07.gamecaption"
    private var lastFrame = ProcessInfo.processInfo.systemUptime - 2.0
    private var lastText = ""

    private var defaults: UserDefaults? { UserDefaults(suiteName: suite) }

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        defaults?.set(true, forKey: "capture.active")
        defaults?.set("", forKey: "capture.sourceText")
        defaults?.set("", forKey: "capture.translatedText")
        defaults?.set("البث شغّال؛ جاري البحث عن نصوص...", forKey: "capture.status")
        lastText = ""
    }

    override func broadcastPaused() {
        defaults?.set("البث متوقف مؤقتًا.", forKey: "capture.status")
    }

    override func broadcastResumed() {
        defaults?.set("البث شغّال؛ جاري البحث عن نصوص...", forKey: "capture.status")
    }

    override func broadcastFinished() {
        defaults?.set(false, forKey: "capture.active")
        defaults?.set("انتهى بث الشاشة.", forKey: "capture.status")
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with type: RPSampleBufferType) {
        guard type == .video, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastFrame >= 1.5 else { return }
        lastFrame = now

        worker.async { [weak self, pixelBuffer] in
            guard let self else { return }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true
            do {
                let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
                try handler.perform([request])
                let text = (request.results ?? [])
                    .sorted { $0.boundingBox.midY > $1.boundingBox.midY }
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty, text != self.lastText else { return }
                self.lastText = text
                let revision = UUID().uuidString
                self.defaults?.set(revision, forKey: "capture.revision")
                self.defaults?.set(text, forKey: "capture.sourceText")
                self.defaults?.set("", forKey: "capture.translatedText")
                self.defaults?.set(Date().timeIntervalSince1970, forKey: "capture.updatedAt")

                let source = self.defaults?.string(forKey: "capture.sourceLanguage") ?? "en"
                let target = self.defaults?.string(forKey: "capture.targetLanguage") ?? "ar"
                if source == target {
                    self.defaults?.set(text, forKey: "capture.translatedText")
                    self.defaults?.set("تم التعرف على النص.", forKey: "capture.status")
                } else if #available(iOS 26.0, *) {
                    self.translate(text, revision: revision, source: source, target: target)
                } else {
                    self.defaults?.set("تم التعرف على النص. الترجمة أثناء الخلفية تحتاج iOS 26 أو أحدث.", forKey: "capture.status")
                }
            } catch {
                self.defaults?.set("تعذر التعرف على النص: \(error.localizedDescription)", forKey: "capture.status")
            }
        }
    }

    @available(iOS 26.0, *)
    private func translate(_ text: String, revision: String, source: String, target: String) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                // Non-UI initializer does not download languages. The user must install them first.
                let session = TranslationSession(
                    installedSource: Locale.Language(identifier: source),
                    target: Locale.Language(identifier: target)
                )
                let result = try await session.translate(text)
                guard self.defaults?.string(forKey: "capture.revision") == revision else { return }
                self.defaults?.set(result.targetText, forKey: "capture.translatedText")
                self.defaults?.set("تمت الترجمة أثناء بث الشاشة.", forKey: "capture.status")
                self.defaults?.set(Date().timeIntervalSince1970, forKey: "capture.updatedAt")
            } catch {
                guard self.defaults?.string(forKey: "capture.revision") == revision else { return }
                self.defaults?.set("تعذر الترجمة. نزّل اللغتين من إعدادات ترجمة iOS ثم أعد المحاولة.", forKey: "capture.status")
            }
        }
    }
}
