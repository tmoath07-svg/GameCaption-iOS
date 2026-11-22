import Foundation
import AVFoundation
import Vision
import SwiftUI
import ImageIO

final class LiveCameraScanner: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published private(set) var isRunning = false
    @Published private(set) var recognizedText = ""
    @Published private(set) var statusText = "استخدم كاميرا الآيفون لقراءة النصوص من شاشة اللعبة."
    let session = AVCaptureSession()
    var scanArea: Double = 1.0
    private let sessionQueue = DispatchQueue(label: "gamecaption.camera.session")
    private let frameQueue = DispatchQueue(label: "gamecaption.camera.frames")
    private var configured = false
    private var lastProcessed = Date.distantPast

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: configureAndStart()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] approved in
                DispatchQueue.main.async {
                    if approved { self?.configureAndStart() }
                    else { self?.statusText = "اسمح للكاميرا من الإعدادات." }
                }
            }
        default:
            statusText = "الكاميرا غير متاحة. افتح إعدادات الخصوصية وفعّل الصلاحية."
        }
    }

    private func configureAndStart() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !self.configured {
                self.session.beginConfiguration()
                self.session.sessionPreset = .high
                guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                      let input = try? AVCaptureDeviceInput(device: device),
                      self.session.canAddInput(input) else {
                    self.session.commitConfiguration()
                    DispatchQueue.main.async { self.statusText = "ما قدرنا نشغّل كاميرا الجهاز." }
                    return
                }
                self.session.addInput(input)
                let output = AVCaptureVideoDataOutput()
                output.alwaysDiscardsLateVideoFrames = true
                output.setSampleBufferDelegate(self, queue: self.frameQueue)
                guard self.session.canAddOutput(output) else {
                    self.session.commitConfiguration()
                    DispatchQueue.main.async { self.statusText = "تعذر تهيئة إطارات الكاميرا." }
                    return
                }
                self.session.addOutput(output)
                self.session.commitConfiguration()
                self.configured = true
            }
            if !self.session.isRunning { self.session.startRunning() }
            DispatchQueue.main.async {
                self.isRunning = self.session.isRunning
                self.statusText = self.session.isRunning ? "الكاميرا شغالة؛ يتجدد النص كل ثانية تقريبًا." : "تعذّر تشغيل الكاميرا."
            }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning { self.session.stopRunning() }
            DispatchQueue.main.async {
                self.isRunning = false
                self.statusText = "الكاميرا متوقفة."
            }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        let now = Date()
        guard now.timeIntervalSince(lastProcessed) > 1.2 else { return }
        lastProcessed = now
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        let size = max(0.4, min(scanArea, 1.0))
        let margin = (1.0 - size) / 2.0
        request.regionOfInterest = CGRect(x: margin, y: margin, width: size, height: size)
        do {
            // Portrait back camera; Vision uses EXIF orientation instead of the preview's UI transform.
            let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .right, options: [:])
            try handler.perform([request])
            let text = (request.results ?? [])
                .sorted { $0.boundingBox.midY > $1.boundingBox.midY }
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")
            guard !text.isEmpty else { return }
            DispatchQueue.main.async { self.recognizedText = text }
        } catch {
            DispatchQueue.main.async { self.statusText = "خطأ قراءة الكاميرا: \(error.localizedDescription)" }
        }
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
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
