import Foundation
import Vision

/// Recognizes text from a screenshot the user explicitly selected.
/// No proprietary assets, model weights, or code are shipped with this app.
enum OCRService {
    static func recognizeText(in imageData: Data) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true
            let handler = VNImageRequestHandler(data: imageData, options: [:])
            try handler.perform([request])
            let rows = (request.results ?? []).sorted {
                $0.boundingBox.midY > $1.boundingBox.midY
            }
            return rows.compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")
        }.value
    }
}
