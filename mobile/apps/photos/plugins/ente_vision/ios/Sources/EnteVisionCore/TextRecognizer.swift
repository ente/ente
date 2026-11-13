import Foundation
import UIKit
import Vision

struct RecognizedCharacter: Sendable {
    let text: String
    let confidence: Float
    let points: [CGPoint]
}

struct RecognizedTextBlock: Sendable {
    let text: String
    let confidence: Float
    let points: [CGPoint]
    let characters: [RecognizedCharacter]
}

struct TextRecognitionResult: Sendable {
    let blocks: [RecognizedTextBlock]
    let imageWidth: Int
    let imageHeight: Int
}

struct TextRegion: Sendable {
    let confidence: Float
    let points: [CGPoint]
}

struct TextRegionsResult: Sendable {
    let regions: [TextRegion]
    let imageWidth: Int
    let imageHeight: Int
}

enum TextRecognitionError: Error {
    case imageNotFound
    case imageUndecodable
    case imageBitmapUnavailable
    case detectionFailed(Error)
    case recognitionFailed(Error)
}

final class TextRecognizer: Sendable {
    private let queue = DispatchQueue.global(qos: .userInitiated)

    func recognizeText(
        imagePath: String,
        includeAllConfidenceScores: Bool,
        completion: @escaping @Sendable (Result<TextRecognitionResult, TextRecognitionError>) -> Void
    ) {
        let minimumConfidence: Float = includeAllConfidenceScores ? 0 : Self.minimumConfidence
        run(foreignError: { .recognitionFailed($0) }, completion: completion) {
            let image = try Self.loadOrientedImage(atPath: imagePath)
            let request = Self.makeRecognizeTextRequest()
            try VNImageRequestHandler(cgImage: image.bitmap, options: [:]).perform([request])
            let size = image.pixelSize
            let blocks = (request.results ?? []).compactMap { observation -> RecognizedTextBlock? in
                guard let candidate = observation.topCandidates(1).first,
                    candidate.confidence >= minimumConfidence
                else {
                    return nil
                }
                return RecognizedTextBlock(
                    text: candidate.string,
                    confidence: candidate.confidence,
                    points: observation.polygon(in: size),
                    characters: Self.characters(of: candidate, in: size)
                )
            }
            return TextRecognitionResult(
                blocks: blocks.sortedInReadingOrder(),
                imageWidth: image.bitmap.width,
                imageHeight: image.bitmap.height
            )
        }
    }

    func detectTextRegions(
        imagePath: String,
        completion: @escaping @Sendable (Result<TextRegionsResult, TextRecognitionError>) -> Void
    ) {
        run(foreignError: { .detectionFailed($0) }, completion: completion) {
            let image = try Self.loadOrientedImage(atPath: imagePath)
            let detectionBitmap =
                Self.downscaled(image.image, longestSide: Self.regionDetectionLongestSide) ?? image.bitmap
            let request = VNDetectTextRectanglesRequest()
            request.reportCharacterBoxes = false
            try VNImageRequestHandler(cgImage: detectionBitmap, options: [:]).perform([request])
            let size = image.pixelSize
            let regions = (request.results ?? []).map { observation in
                TextRegion(confidence: observation.confidence, points: observation.polygon(in: size))
            }
            return TextRegionsResult(
                regions: regions,
                imageWidth: image.bitmap.width,
                imageHeight: image.bitmap.height
            )
        }
    }

    private func run<Value>(
        foreignError: @escaping @Sendable (Error) -> TextRecognitionError,
        completion: @escaping @Sendable (Result<Value, TextRecognitionError>) -> Void,
        _ work: @escaping @Sendable () throws -> Value
    ) {
        queue.async {
            let outcome = Result { try work() }
                .mapError { $0 as? TextRecognitionError ?? foreignError($0) }
            completion(outcome)
        }
    }

    private static func loadOrientedImage(atPath path: String) throws -> OrientedImage {
        guard FileManager.default.fileExists(atPath: path) else { throw TextRecognitionError.imageNotFound }
        guard let image = UIImage(contentsOfFile: path) else { throw TextRecognitionError.imageUndecodable }
        let oriented = Self.orientedUp(image)
        guard let bitmap = oriented.cgImage else { throw TextRecognitionError.imageBitmapUnavailable }
        return OrientedImage(image: oriented, bitmap: bitmap)
    }

    private static func makeRecognizeTextRequest() -> VNRecognizeTextRequest {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.minimumTextHeight = 0.01
        request.usesLanguageCorrection = true
        if #available(iOS 16.0, *) {
            request.automaticallyDetectsLanguage = true
            request.revision = VNRecognizeTextRequestRevision3
        } else {
            request.recognitionLanguages = preferredRecognitionLanguages(for: request)
        }
        return request
    }

    private static func preferredRecognitionLanguages(for request: VNRecognizeTextRequest) -> [String] {
        let supported = (try? request.supportedRecognitionLanguages()) ?? ["en-US"]
        return RecognitionLanguageSelector.select(
            preferredLanguages: Locale.preferredLanguages,
            supportedLanguages: supported
        )
    }

    private static func characters(of candidate: VNRecognizedText, in size: CGSize) -> [RecognizedCharacter] {
        let text = candidate.string
        return text.indices.compactMap { start in
            let range = start..<text.index(after: start)
            guard let box = try? candidate.boundingBox(for: range) else { return nil }
            return RecognizedCharacter(
                text: String(text[range]),
                confidence: candidate.confidence,
                points: box.polygon(in: size)
            )
        }
    }

    private static func orientedUp(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    private static func downscaled(_ image: UIImage, longestSide maxDimension: CGFloat) -> CGImage? {
        guard let source = image.cgImage else { return nil }
        let width = CGFloat(source.width)
        let height = CGFloat(source.height)
        let longestSide = max(width, height)
        guard longestSide > maxDimension else { return source }
        let scale = maxDimension / longestSide
        let targetSize = CGSize(
            width: max(1, (width * scale).rounded()),
            height: max(1, (height * scale).rounded())
        )
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: targetSize, format: format)
            .image { _ in
                image.draw(in: CGRect(origin: .zero, size: targetSize))
            }
            .cgImage
    }

    private static let minimumConfidence: Float = 0.3
    private static let regionDetectionLongestSide: CGFloat = 1024
}

private struct OrientedImage {
    let image: UIImage
    let bitmap: CGImage

    var pixelSize: CGSize {
        CGSize(width: bitmap.width, height: bitmap.height)
    }
}

extension VNRectangleObservation {
    fileprivate func polygon(in size: CGSize) -> [CGPoint] {
        [topLeft, topRight, bottomRight, bottomLeft].map { corner in
            CGPoint(x: corner.x * size.width, y: (1 - corner.y) * size.height)
        }
    }
}

private let readingOrderLineBand: CGFloat = 10

extension [RecognizedTextBlock] {
    fileprivate func sortedInReadingOrder() -> [RecognizedTextBlock] {
        sorted { first, second in
            let firstOrigin = first.points.boundsOrigin
            let secondOrigin = second.points.boundsOrigin
            if abs(firstOrigin.y - secondOrigin.y) > readingOrderLineBand {
                return firstOrigin.y < secondOrigin.y
            }
            return firstOrigin.x < secondOrigin.x
        }
    }
}

extension [CGPoint] {
    fileprivate var boundsOrigin: CGPoint {
        CGPoint(x: map(\.x).min() ?? 0, y: map(\.y).min() ?? 0)
    }
}
