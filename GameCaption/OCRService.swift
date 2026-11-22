import Foundation
import Vision
import UIKit
import ImageIO

extension OCRService {
    struct ImportedImage {
        let preview: UIImage
        let text: String
    }

    static func importImage(data: Data, language: String) async throws -> ImportedImage {
        try await Task.detached(priority: .userInitiated) {
            guard let image = CGImageSourceCreateWithData(data as CFData, nil) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            return try scanImage(image, language: language)
        }.value
    }

    static func importImage(url: URL, language: String) async throws -> ImportedImage {
        try await Task.detached(priority: .userInitiated) {
            let permitted = url.startAccessingSecurityScopedResource()
            defer { if permitted { url.stopAccessingSecurityScopedResource() } }
            guard let image = CGImageSourceCreateWithURL(url as CFURL, nil) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            return try scanImage(image, language: language)
        }.value
    }

    private static func scanImage(_ image: CGImageSource, language: String) throws -> ImportedImage {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 3000
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(image, 0, options as CFDictionary) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let text = try recognize(VNImageRequestHandler(cgImage: thumbnail, options: [:]),
                                 language: languageIdentifier(language))
        return ImportedImage(preview: UIImage(cgImage: thumbnail), text: text)
    }
}
