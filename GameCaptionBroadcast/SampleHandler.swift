import Foundation
import ReplayKit
import Vision
import Translation
import CoreMedia
import ImageIO
import os

final class SampleHandler: RPBroadcastSampleHandler {
    private let worker = DispatchQueue(label: "com.tmoath07.gamecaption.broadcast.ocr", qos: .userInitiated)
    private let exchange = BroadcastExchange()
    private let logger = Logger(subsystem: "com.tmoath07.gamecaption", category: "broadcast")
    private var snapshot = CaptureSnapshot(active: false, settings: CaptureSettings())
    private var changes = SubtitleChanges()
    private var paused = false
    private var lastFrame = -Double.infinity
    private var translationTask: Task<Void, Never>?
    private var inFlightRevision: UUID?
    private var pending: CaptureSnapshot?

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        worker.sync {
            guard exchange != nil else {
                finishBroadcastWithError(NSError(
                    domain: "com.tmoath07.gamecaption.broadcast", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "مجموعة التطبيق غير متاحة. تحقق من صلاحية App Groups."]
                ))
                return
            }
            snapshot = CaptureSnapshot(settings: readSettings(), status: "البث شغّال؛ جاري البحث عن نصوص...")
            changes = SubtitleChanges()
            paused = false
            lastFrame = -.infinity
            publish()
        }
    }

    override func broadcastPaused() {
        worker.sync {
            paused = true
            clearCaption(status: "البث متوقف مؤقتًا.")
            snapshot.active = false
            publish()
        }
    }

    override func broadcastResumed() {
        worker.sync {
            paused = false
            snapshot.active = true
            snapshot.status = "البث شغّال؛ جاري البحث عن نصوص..."
            lastFrame = -.infinity
            publish()
        }
    }

    override func broadcastFinished() {
        worker.sync {
            snapshot.active = false
            clearCaption(status: "انتهى بث الشاشة.")
            publish()
        }
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with type: RPSampleBufferType) {
        guard type == .video else { return }
        // ReplayKit owns the buffer. Sample synchronously so OCR can never enqueue frames.
        worker.sync {
            guard snapshot.active, !paused else { return }
            let now = ProcessInfo.processInfo.systemUptime
            guard now - lastFrame >= 0.70, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            lastFrame = now

            let settings = readSettings()
            if settings != snapshot.settings {
                snapshot.settings = settings
                clearCaption(status: "جاري البحث في منطقة النص...")
                publish()
            }
            if (try? exchange?.hostIsForeground()) == true {
                // Keep the last game caption available for review without reading GameCaption itself.
                if Date().timeIntervalSince(snapshot.updated) >= 3 { publish() }
                return
            }

            let attachment = CMGetAttachment(sampleBuffer, key: RPVideoSampleOrientationKey as CFString,
                                             attachmentModeOut: nil) as? NSNumber
            let orientation = attachment.flatMap { CGImagePropertyOrientation(rawValue: $0.uint32Value) } ?? .up
            do {
                let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: orientation, options: [:])
                let text = try OCRService.recognize(handler, region: settings.region,
                                                    language: OCRService.languageIdentifier(settings.source))
                if let change = changes.update(text) {
                    apply(change, settings: settings)
                } else if Date().timeIntervalSince(snapshot.updated) >= 3 {
                    publish()
                }
            } catch {
                clearCaption(status: "تعذر التعرف على النص: \(error.localizedDescription)")
                publish()
            }
        }
    }

    private func readSettings() -> CaptureSettings {
        do {
            return try exchange?.settings() ?? CaptureSettings()
        } catch {
            logger.error("Cannot read capture settings: \(error.localizedDescription, privacy: .public)")
            return snapshot.settings
        }
    }

    private func apply(_ text: String, settings: CaptureSettings) {
        pending = nil
        snapshot.revision = UUID()
        snapshot.source = text
        snapshot.translation = ""
        if text.isEmpty {
            snapshot.status = "البث شغّال؛ لا يوجد نص في المنطقة المحددة."
        } else if !settings.translate {
            snapshot.status = "تم التعرف على النص. الترجمة التلقائية متوقفة."
        } else if settings.source == settings.target {
            snapshot.translation = text
            snapshot.status = "تم التعرف على النص."
        } else if #available(iOS 26.0, *) {
            snapshot.status = "جاري ترجمة النص أثناء البث..."
            pending = snapshot
            translateNext()
        } else {
            snapshot.status = "تم التعرف على النص. الترجمة أثناء البث تحتاج iOS 26 أو أحدث."
        }
        publish()
    }

    private func clearCaption(status: String) {
        pending = nil
        translationTask?.cancel()
        changes = SubtitleChanges()
        snapshot.revision = UUID()
        snapshot.source = ""
        snapshot.translation = ""
        snapshot.status = status
    }

    private func publish() {
        snapshot.updated = Date()
        do {
            try exchange?.writeSnapshot(snapshot)
        } catch {
            logger.error("Cannot write capture status: \(error.localizedDescription, privacy: .public)")
        }
    }

    @available(iOS 26.0, *)
    private func translateNext() {
        guard inFlightRevision == nil, let item = pending else { return }
        pending = nil
        inFlightRevision = item.revision
        translationTask = Task { @MainActor [weak self] in
            let session = TranslationSession(
                installedSource: Locale.Language(identifier: item.settings.source),
                target: Locale.Language(identifier: item.settings.target)
            )
            let result: Result<String, Error>
            do {
                try Task.checkCancellation()
                result = .success(try await session.translate(item.source).targetText)
            } catch {
                result = .failure(error)
            }
            guard let self else { return }
            self.worker.async { self.complete(result, revision: item.revision) }
        }
    }

    @available(iOS 26.0, *)
    private func complete(_ result: Result<String, Error>, revision: UUID) {
        guard inFlightRevision == revision else { return }
        inFlightRevision = nil
        translationTask = nil
        if snapshot.active, snapshot.revision == revision {
            switch result {
            case .success(let text):
                snapshot.translation = text
                snapshot.status = "تمت الترجمة أثناء بث الشاشة."
            case .failure(let error):
                snapshot.status = "تعذر الترجمة أثناء البث. جهّز اللغات داخل التطبيق. \(error.localizedDescription)"
            }
            publish()
        }
        translateNext()
    }
}
