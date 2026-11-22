import Foundation
import Combine
import Speech
import AVFoundation

final class LiveSpeechRecognizer: ObservableObject {
    @Published private(set) var transcript = ""
    @Published private(set) var isListening = false
    @Published private(set) var isStarting = false
    @Published private(set) var statusText = "استخدم الميكروفون للتعرف على الكلام أثناء اللعب."
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?
    private var runID: UUID?
    private var installedTap = false
    private var activeAudio = false

    func start(language: String) {
        guard runID == nil else { return }
        let id = UUID()
        runID = id
        isStarting = true
        SFSpeechRecognizer.requestAuthorization { [weak self] authorization in
            DispatchQueue.main.async {
                guard let self, self.runID == id else { return }
                guard authorization == .authorized else {
                    self.stop(message: "فعّل إذن التعرف على الكلام من إعدادات الآيفون.")
                    return
                }
                AVAudioApplication.requestRecordPermission { allowed in
                    DispatchQueue.main.async {
                        guard self.runID == id else { return }
                        guard allowed else {
                            self.stop(message: "فعّل إذن الميكروفون من الإعدادات.")
                            return
                        }
                        self.beginRecording(language: language, id: id)
                    }
                }
            }
        }
    }

    private func beginRecording(language: String, id: UUID) {
        let instance = SFSpeechRecognizer(locale: Locale(identifier: language))
        guard let instance, instance.isAvailable else {
            stop(message: "التعرف على الكلام غير متاح حاليًا للغة أو الجهاز المختار.")
            return
        }
        recognizer = instance
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = instance.supportsOnDeviceRecognition
        recognitionRequest = request
        do {
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .mixWithOthers])
            try audio.setActive(true)
            activeAudio = true
            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                stop(message: "الميكروفون غير متاح حاليًا. تحقق من مصدر الصوت.")
                return
            }
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
            installedTap = true
            audioEngine.prepare()
            try audioEngine.start()
            isStarting = false
            isListening = true
            statusText = "الميكروفون شغّال. تحدث أو شغّل الصوت قريبًا من الآيفون."
            recognitionTask = instance.recognitionTask(with: request) { [weak self] result, error in
                DispatchQueue.main.async {
                    guard let self, self.runID == id else { return }
                    if let result { self.transcript = result.bestTranscription.formattedString }
                    if let error {
                        self.stop(message: "توقف التعرف على الكلام: \(error.localizedDescription)")
                    } else if result?.isFinal == true {
                        self.stop(message: "اكتمل التعرف. اضغط للبدء مجددًا.")
                    }
                }
            }
        } catch {
            stop(message: "تعذر تشغيل الميكروفون: \(error.localizedDescription)")
        }
    }

    func stop() {
        stop(message: "الميكروفون متوقف.")
    }

    private func stop(message: String) {
        guard runID != nil else { return }
        runID = nil
        if audioEngine.isRunning { audioEngine.stop() }
        if installedTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            installedTap = false
        }
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        recognizer = nil
        if activeAudio {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            activeAudio = false
        }
        isListening = false
        isStarting = false
        statusText = message
    }
}
