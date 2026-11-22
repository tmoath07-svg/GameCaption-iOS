import Foundation
import Combine
import AVFoundation
import SherpaOnnx

/// Neural text-to-speech using independently licensed Nabra-82M (Apache-2.0).
/// Unlike AVSpeechSynthesizer, both voice weights are embedded with the IPA.
@MainActor
final class OfflineArabicVoice: ObservableObject {
    enum Quality: String, CaseIterable, Identifiable {
        case efficient = "سريع (INT8)"
        case detailed = "أعلى دقة (FP16)"
        var id: String { rawValue }
        var resource: String {
            switch self {
            case .efficient: "model.int8"
            case .detailed: "model.fp16"
            }
        }
    }

    @Published private(set) var isSynthesizing = false
    @Published private(set) var status = "صوت عربي عصبي يعمل محليًا بدون اشتراك أو خادم."
    private var player: AVAudioPlayer?
    private var lastFile: URL?
    private let workQueue = DispatchQueue(label: "com.tmoath07.gamecaption.neuralvoice", qos: .userInitiated)

    func speak(_ text: String, quality: Quality) {
        guard !isSynthesizing else { return }
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { status = "الترجمة فاضية."; return }

        // A single long synthesis can exhaust iOS memory. Limit to a useful caption length.
        let clipped = String(input.prefix(400))
        guard let model = Bundle.main.path(forResource: quality.resource, ofType: "onnx",
                                           inDirectory: "NeuralArabicVoice"),
              let tokens = Bundle.main.path(forResource: "tokens", ofType: "txt",
                                            inDirectory: "NeuralArabicVoice"),
              let voices = Bundle.main.path(forResource: "voices", ofType: "bin",
                                            inDirectory: "NeuralArabicVoice"),
              let dataDir = Bundle.main.path(forResource: "espeak-ng-data", ofType: nil,
                                             inDirectory: "NeuralArabicVoice") else {
            status = "ملفات الصوت العصبي غير موجودة داخل IPA. أعد بناء نسخة النماذج."
            return
        }

        player?.stop()
        player = nil
        isSynthesizing = true
        status = "جاري توليد الصوت بالعربي محليًا..."
        workQueue.async { [weak self] in
            let result = Self.generate(clipped, model: model, tokens: tokens,
                                       voices: voices, dataDir: dataDir)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isSynthesizing = false
                switch result {
                case .success(let file):
                    do {
                        let player = try AVAudioPlayer(contentsOf: file)
                        player.prepareToPlay()
                        guard player.play() else {
                            self.status = "تعذر تشغيل الصوت الناتج."
                            try? FileManager.default.removeItem(at: file)
                            return
                        }
                        if let lastFile = self.lastFile { try? FileManager.default.removeItem(at: lastFile) }
                        self.lastFile = file
                        self.player = player
                        self.status = "نطق عربي عصبي محلي — \(quality.rawValue)"
                    } catch {
                        self.status = "فشل تشغيل الصوت: \(error.localizedDescription)"
                    }
                case .failure(let error):
                    self.status = "فشل توليد الصوت العصبي: \(error.localizedDescription)"
                }
            }
        }
    }

    private enum VoiceError: Error, LocalizedError {
        case outputMissing
        var errorDescription: String? { "لم يتم إنشاء ملف صوت صالح من النموذج." }
    }

    nonisolated private static func generate(_ text: String, model: String, tokens: String,
                                             voices: String, dataDir: String) -> Result<URL, Error> {
        // This is the documented Kokoro-compatible interface supported by Nabra-82M.
        let config = sherpaOnnxOfflineTtsKokoroModelConfig(
            model: model, voices: voices, tokens: tokens, dataDir: dataDir
        )
        let modelConfig = sherpaOnnxOfflineTtsModelConfig(kokoro: config, numThreads: 2)
        var ttsConfig = sherpaOnnxOfflineTtsConfig(model: modelConfig)
        let engine = SherpaOnnxOfflineTtsWrapper(config: &ttsConfig)
        let audio = engine.generate(text: text, sid: 0, speed: 1.0)
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("gamecaption-neural-\(UUID().uuidString).wav")
        _ = audio.save(filename: output.path)
        let outputSize = (try? FileManager.default.attributesOfItem(atPath: output.path))?[.size] as? NSNumber
        guard (outputSize?.intValue ?? 0) > 44 else {
            return .failure(VoiceError.outputMissing)
        }
        return .success(output)
    }
}
