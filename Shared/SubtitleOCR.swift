import Foundation
import Vision
import ImageIO

struct SubtitleRegion: Codable, Equatable {
    var bottom = 0.0
    var height = 0.35

    var rectangle: CGRect {
        let height = min(max(self.height, 0.15), 1)
        return CGRect(x: 0, y: min(max(bottom, 0), 1 - height), width: 1, height: height)
    }
}

/// Emits a new caption once and clears it after two empty samples.
struct SubtitleChanges {
    private(set) var current = ""
    private var emptySamples = 0

    mutating func update(_ text: String) -> String? {
        let normalized = OCRService.normalize(text)
        if normalized.isEmpty {
            emptySamples += 1
            guard emptySamples >= 2, !current.isEmpty else { return nil }
        } else {
            emptySamples = 0
            guard normalized != current else { return nil }
        }
        current = normalized
        return current
    }
}

enum OCRService {
    static func normalize(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).map { line in
            line.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    static func recognize(
        _ handler: VNImageRequestHandler,
        region: SubtitleRegion? = nil,
        language: String? = nil
    ) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        if let language, try request.supportedRecognitionLanguages().contains(language) {
            request.recognitionLanguages = [language]
        } else {
            request.automaticallyDetectsLanguage = true
        }
        if let region { request.regionOfInterest = region.rectangle }
        try handler.perform([request])

        let observations = (request.results ?? []).sorted {
            $0.boundingBox.midY > $1.boundingBox.midY
        }
        // Vision sometimes returns separate observations for words along a single subtitle line.
        var rows: [[VNRecognizedTextObservation]] = []
        for observation in observations {
            let box = observation.boundingBox
            if let anchor = rows.last?.first?.boundingBox,
               abs(anchor.midY - box.midY) < min(anchor.height, box.height) * 0.5 {
                rows[rows.count - 1].append(observation)
            } else {
                rows.append([observation])
            }
        }
        return normalize(rows.map { row in
            row.sorted {
                language == "ar" ? $0.boundingBox.minX > $1.boundingBox.minX
                                 : $0.boundingBox.minX < $1.boundingBox.minX
            }.compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
        }.joined(separator: "\n"))
    }

    static func languageIdentifier(_ code: String) -> String {
        switch code {
        case "en": "en-US"
        case "zh": "zh-Hans"
        default: code
        }
    }
}
