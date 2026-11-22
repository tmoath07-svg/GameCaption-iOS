import Foundation
import Speech
import AVFoundation

final class LiveSpeechRecognizer: ObservableObject {
    @Published private(set) var transcript = ""
    @Published private(set) var isListening = false
    @Published private(set) var statusText = "استخدم الميكروفون للتعرف على الكلام أثناء اللعب."
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?

    func start(language: String) {
        guard !isListening else { return }
        SFSpeechRecognizer.requestAuthorization { [weak self] authorization in
            DispatchQueue.main.async {
                guard let self else { return }
                guard authorization == .authorized else {
                    self.statusText = "فعّل إذن التعرف على الكلام من إعدادات الآيفون."
                    return
                }
                AVAudioSession.sharedInstance().requestRecordPermission { allowed in
                    DispatchQueue.main.async {
                        guard allowed else {
                            self.statusText = "فعّل إذن الميكروفون من الإعدادات."
                            return
                        }
                        self.beginRecording(language: language)
                    }
                }
            }
        }
    }

    private func beginRecording(language: String) {
        stop()
        let instance = SFSpeechRecognizer(locale: Locale(identifier: language))
        guard let instance, instance.isAvailable else {
            statusText = "التعرف على الكلام غير مدعوم حاليًا للغة أو الجهاز المختار."
            return
        }
        recognizer = instance
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // System may fall back to network recognition for languages without an on-device model.
        if instance.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        recognitionRequest = request
        do {
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .mixWithOthers])
            try audio.setActive(true, options: .notifyOthersOnDeactivation)
            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }
            audioEngine.prepare()
            try audioEngine.start()
            isListening = true
            statusText = "الميكروفون شغّال. تحدث أو شغّل الصوت قريبًا من الآيفون."
            recognitionTask = instance.recognitionTask(with: request) { [weak self] result, error in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if let result { self.transcript = result.bestTranscription.formattedString }
                    if let error {
                        self.statusText = "توقف التعرف على الكلام: \(error.localizedDescription)"
                        self.stop()
                    } else if result?.isFinal == true {
                        self.stop()
                    }
                }
            }
        } catch {
            statusText = "تعذر تشغيل الصوت: \(error.localizedDescription)"
            stop()
        }
    }

    func stop() {
        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        isListening = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
