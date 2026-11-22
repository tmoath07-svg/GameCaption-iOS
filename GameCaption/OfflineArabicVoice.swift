#if canImport(SherpaOnnx)
import Foundation
import Combine
import AVFoundation
import SherpaOnnx

@MainActor
final class OfflineArabicVoice: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var status = "نطق عربي محلي باستخدام نموذج Nabra INT8."
    private var player: AVAudioPlayer?
    private var batchID = UUID()
    private var generating = false
    private var remaining: ArraySlice<String> = []
    private let workQueue = DispatchQueue(label: "com.tmoath07.gamecaption.neuralvoice", qos: .userInitiated)

    func speak(_ text: String) {
        guard !generating else { return }
        stop()
        remaining = Self.chunks(text)[...]
        playNext()
    }

    func stop() {
        batchID = UUID()
        player?.stop()
        player = nil
        remaining = []
    }

    private func playNext() {
        guard let text = remaining.popFirst() else { return }
        guard let root = Bundle.main.resourceURL?.appendingPathComponent("NeuralArabicVoice"),
              ["model.int8.onnx", "tokens.txt", "voices.bin", "espeak-ng-data/phontab"].allSatisfy({
                  FileManager.default.isReadableFile(atPath: root.appendingPathComponent($0).path)
              }) else {
            status = "ملفات النطق العصبي غير جاهزة."
            return
        }

        let id = batchID
        generating = true
        status = "جاري توليد الصوت بالعربي محليًا..."
        workQueue.async {
            let audio = Result { try Self.generate(text, resources: root) }
            DispatchQueue.main.async {
                self.generating = false
                guard self.batchID == id else { return }
                do {
                    let player = try AVAudioPlayer(data: audio.get())
                    player.delegate = self
                    guard player.play() else { throw VoiceError.noAudio }
                    self.player = player
                    self.status = "جاري تشغيل الصوت العربي."
                } catch {
                    self.remaining = []
                    self.status = "تعذر تشغيل الصوت: \(error.localizedDescription)"
                }
            }
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            guard self.player === player else { return }
            self.player = nil
            self.status = flag ? "اكتمل تشغيل الصوت." : "توقف تشغيل الصوت."
            if flag { self.playNext() }
            else { self.remaining = [] }
        }
    }

    // Preserve the full text while bounding the model's working sequence per inference.
    nonisolated private static func chunks(_ text: String) -> [String] {
        var parts: [String] = []
        var current = ""
        for word in text.split(whereSeparator: \.isWhitespace) {
            var rest = word
            while rest.count > 120 {
                if !current.isEmpty { parts.append(current); current = "" }
                parts.append(String(rest.prefix(120)))
                rest = rest.dropFirst(120)
            }
            if !current.isEmpty, current.count + rest.count + 1 > 120 {
                parts.append(current)
                current = ""
            }
            if !current.isEmpty { current += " " }
            current.append(contentsOf: rest)
        }
        if !current.isEmpty { parts.append(current) }
        return parts
    }

    private enum VoiceError: LocalizedError {
        case noAudio
        var errorDescription: String? { "لم يتم إنشاء مقطع صوت صالح من النموذج." }
    }

    nonisolated private static func generate(_ text: String, resources: URL) throws -> Data {
        let model = sherpaOnnxOfflineTtsKokoroModelConfig(
            model: resources.appendingPathComponent("model.int8.onnx").path,
            voices: resources.appendingPathComponent("voices.bin").path,
            tokens: resources.appendingPathComponent("tokens.txt").path,
            dataDir: resources.appendingPathComponent("espeak-ng-data").path
        )
        let config = sherpaOnnxOfflineTtsModelConfig(kokoro: model, numThreads: 2)
        var ttsConfig = sherpaOnnxOfflineTtsConfig(model: config)
        let engine = SherpaOnnxOfflineTtsWrapper(config: &ttsConfig)
        guard engine.tts != nil else { throw VoiceError.noAudio }
        let audio = engine.generate(text: text, sid: 0, speed: 1)
        guard audio.audio != nil, audio.n > 0, audio.sampleRate > 0 else { throw VoiceError.noAudio }
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("gamecaption-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: file) }
        guard audio.save(filename: file.path) == 1 else { throw VoiceError.noAudio }
        return try Data(contentsOf: file)
    }
}
#endif
