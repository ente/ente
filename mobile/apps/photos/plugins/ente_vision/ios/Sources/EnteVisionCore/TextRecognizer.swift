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
    case cancelled
    case detectionFailed(Error)
    case recognitionFailed(Error)
}

final class TextRecognizer: @unchecked Sendable {
    private let lock = NSLock()
    private var activeRequests: [RequestKey: RequestState] = [:]
    private let queue = DispatchQueue.global(qos: .userInitiated)

    func recognizeText(
        imagePath: String,
        includeAllConfidenceScores: Bool,
        requestId: String?,
        completion: @escaping @Sendable (Result<TextRecognitionResult, TextRecognitionError>) -> Void
    ) {
        let minimumConfidence: Float = includeAllConfidenceScores ? 0 : Self.minimumConfidence
        run(requestId: requestId, foreignError: { .recognitionFailed($0) }, completion: completion) {
            [self] state in
            let image = try loadOrientedImage(atPath: imagePath, state: state)
            let request = Self.makeRecognizeTextRequest()
            try attach(request, to: state)
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
        requestId: String?,
        completion: @escaping @Sendable (Result<TextRegionsResult, TextRecognitionError>) -> Void
    ) {
        run(requestId: requestId, foreignError: { .detectionFailed($0) }, completion: completion) {
            [self] state in
            let image = try loadOrientedImage(atPath: imagePath, state: state)
            let detectionBitmap =
                Self.downscaled(image.image, longestSide: Self.regionDetectionLongestSide) ?? image.bitmap
            let request = VNDetectTextRectanglesRequest()
            request.reportCharacterBoxes = false
            try attach(request, to: state)
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

    func cancel(requestId: String) {
        lock.lock()
        let state = activeRequests.removeValue(forKey: .client(requestId))
        state?.isCancelled = true
        let request = state?.request
        lock.unlock()
        request?.cancel()
    }

    func cancelAll() {
        lock.lock()
        let states = Array(activeRequests.values)
        activeRequests.removeAll()
        for state in states {
            state.isCancelled = true
        }
        let requests = states.compactMap(\.request)
        lock.unlock()
        for request in requests {
            request.cancel()
        }
    }

    private func run<Value>(
        requestId: String?,
        foreignError: @escaping @Sendable (Error) -> TextRecognitionError,
        completion: @escaping @Sendable (Result<Value, TextRecognitionError>) -> Void,
        _ work: @escaping @Sendable (RequestState) throws -> Value
    ) {
        let state = begin(requestId: requestId)
        queue.async {
            let outcome = Result { try work(state) }
                .mapError { $0 as? TextRecognitionError ?? foreignError($0) }
            completion(self.finish(state, outcome))
        }
    }

    private func begin(requestId: String?) -> RequestState {
        let state = RequestState(key: requestId.map(RequestKey.client) ?? .anonymous(UUID()))
        lock.lock()
        let previous = activeRequests.updateValue(state, forKey: state.key)
        previous?.isCancelled = true
        let previousRequest = previous?.request
        lock.unlock()
        previousRequest?.cancel()
        return state
    }

    private func attach(_ request: VNRequest, to state: RequestState) throws {
        lock.lock()
        defer { lock.unlock() }
        guard !state.isCancelled else { throw TextRecognitionError.cancelled }
        state.request = request
    }

    private func checkNotCancelled(_ state: RequestState) throws {
        lock.lock()
        defer { lock.unlock() }
        if state.isCancelled {
            throw TextRecognitionError.cancelled
        }
    }

    private func finish<Value>(
        _ state: RequestState,
        _ outcome: Result<Value, TextRecognitionError>
    ) -> Result<Value, TextRecognitionError> {
        lock.lock()
        defer { lock.unlock() }
        if activeRequests[state.key] === state {
            activeRequests.removeValue(forKey: state.key)
        }
        state.request = nil
        return state.isCancelled ? .failure(.cancelled) : outcome
    }

    private func loadOrientedImage(atPath path: String, state: RequestState) throws -> OrientedImage {
        try checkNotCancelled(state)
        guard FileManager.default.fileExists(atPath: path) else { throw TextRecognitionError.imageNotFound }
        guard let image = UIImage(contentsOfFile: path) else { throw TextRecognitionError.imageUndecodable }
        try checkNotCancelled(state)
        let oriented = Self.orientedUp(image)
        guard let bitmap = oriented.cgImage else { throw TextRecognitionError.imageBitmapUnavailable }
        try checkNotCancelled(state)
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

private enum RequestKey: Hashable {
    case client(String)
    case anonymous(UUID)
}

private final class RequestState: @unchecked Sendable {
    let key: RequestKey
    var request: VNRequest?
    var isCancelled = false

    init(key: RequestKey) {
        self.key = key
    }
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
