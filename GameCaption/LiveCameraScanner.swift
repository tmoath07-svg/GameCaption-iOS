import Foundation
import AVFoundation
import Vision
import SwiftUI
import ImageIO

final class LiveCameraScanner: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published private(set) var isRunning = false
    @Published private(set) var isStarting = false
    @Published private(set) var recognizedText = ""
    @Published private(set) var statusText = "استخدم كاميرا الآيفون لقراءة النصوص من شاشة اللعبة."
    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "gamecaption.camera.session")
    private let frameQueue = DispatchQueue(label: "gamecaption.camera.frames")
    private var configured = false
    private var runID: UUID?
    private var frameRunID: UUID?
    private var lastProcessed = -Double.infinity
    private var changes = SubtitleChanges()
    private var requestedSettings = CaptureSettings()
    private var settings = CaptureSettings()
    private var reportedOCRError = false

    func configure(_ settings: CaptureSettings) {
        guard requestedSettings.source != settings.source || requestedSettings.region != settings.region else { return }
        requestedSettings = settings
        recognizedText = ""
        frameQueue.async {
            self.settings = settings
            self.changes = SubtitleChanges()
            self.lastProcessed = -.infinity
        }
    }

    func start() {
        guard runID == nil else { return }
        let id = UUID()
        runID = id
        isStarting = true
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndStart(id)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] approved in
                DispatchQueue.main.async {
                    guard let self, self.runID == id else { return }
                    if approved { self.configureAndStart(id) }
                    else { self.startFailed(id, "اسمح للكاميرا من الإعدادات.") }
                }
            }
        default:
            startFailed(id, "الكاميرا غير متاحة. افتح إعدادات الخصوصية وفعّل الصلاحية.")
        }
    }

    private func startFailed(_ id: UUID, _ message: String) {
        guard runID == id else { return }
        runID = nil
        isStarting = false
        isRunning = false
        statusText = message
    }

    private func configureAndStart(_ id: UUID) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !self.configured {
                self.session.beginConfiguration()
                self.session.sessionPreset = .hd1920x1080
                guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                      let input = try? AVCaptureDeviceInput(device: device),
                      self.session.canAddInput(input) else {
                    self.session.commitConfiguration()
                    DispatchQueue.main.async { self.startFailed(id, "ما قدرنا نشغّل كاميرا الجهاز.") }
                    return
                }
                self.session.addInput(input)
                let output = AVCaptureVideoDataOutput()
                output.alwaysDiscardsLateVideoFrames = true
                guard self.session.canAddOutput(output) else {
                    self.session.removeInput(input)
                    self.session.commitConfiguration()
                    DispatchQueue.main.async { self.startFailed(id, "تعذر تهيئة إطارات الكاميرا.") }
                    return
                }
                output.setSampleBufferDelegate(self, queue: self.frameQueue)
                self.session.addOutput(output)
                self.session.commitConfiguration()
                self.configured = true
            }
            self.frameQueue.sync {
                self.frameRunID = id
                self.lastProcessed = -.infinity
                self.reportedOCRError = false
                self.changes = SubtitleChanges()
            }
            if !self.session.isRunning { self.session.startRunning() }
            let started = self.session.isRunning
            DispatchQueue.main.async {
                guard self.runID == id else { return }
                if started {
                    self.isStarting = false
                    self.isRunning = true
                    self.statusText = "الكاميرا شغالة؛ يتجدد النص عند تغيّره."
                } else {
                    self.startFailed(id, "تعذّر تشغيل الكاميرا.")
                }
            }
        }
    }

    func stop() {
        guard runID != nil else { return }
        runID = nil
        isRunning = false
        isStarting = false
        recognizedText = ""
        statusText = "الكاميرا متوقفة."
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        let now = ProcessInfo.processInfo.systemUptime
        guard let id = frameRunID, now - lastProcessed >= 0.65,
              let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastProcessed = now
        do {
            let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .right, options: [:])
            let text = try OCRService.recognize(handler, region: settings.region,
                                                language: OCRService.languageIdentifier(settings.source))
            let change = changes.update(text)
            let recovered = reportedOCRError
            reportedOCRError = false
            if change != nil || recovered {
                DispatchQueue.main.async {
                    guard self.runID == id else { return }
                    if let change { self.recognizedText = change }
                    if recovered { self.statusText = "الكاميرا شغالة؛ يتجدد النص عند تغيّره." }
                }
            }
        } catch {
            reportedOCRError = true
            changes = SubtitleChanges()
            DispatchQueue.main.async {
                guard self.runID == id else { return }
                self.recognizedText = ""
                self.statusText = "خطأ قراءة الكاميرا: \(error.localizedDescription)"
            }
        }
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspect
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.previewLayer.session = session
    }
}

final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}
