import AVFoundation
import ImageIO

public final class VideoFrameExtractor: @unchecked Sendable {
    private let metadataReader: VideoMetadataReader
    private let permits = AsyncPermitPool(limit: 2)

    public init(metadataReader: VideoMetadataReader = VideoMetadataReader()) {
        self.metadataReader = metadataReader
    }

    public func extract(_ request: VideoFrameRequest) async throws -> VideoFrameExtractionResult {
        try await permits.acquire()
        do {
            let result = try await extractWithPermit(request)
            await permits.release()
            return result
        } catch {
            request.outputURLs.forEach { try? FileManager.default.removeItem(at: $0) }
            await permits.release()
            throw error
        }
    }

    private func extractWithPermit(
        _ request: VideoFrameRequest
    ) async throws -> VideoFrameExtractionResult {
        try Task.checkCancellation()
        let asset = AVURLAsset(url: request.inputURL)
        let videoInfo = try await metadataReader.read(from: asset)

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: request.maxWidth, height: request.maxHeight)
        if request.policy == .precise {
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
        } else {
            let tolerance = CMTime(value: 300, timescale: 600)
            generator.requestedTimeToleranceBefore = tolerance
            generator.requestedTimeToleranceAfter = tolerance
        }

        var frames: [VideoFrameResult] = []
        frames.reserveCapacity(request.positionsMs.count)
        for (index, requestedPositionMs) in request.positionsMs.enumerated() {
            try Task.checkCancellation()
            let positionMs = clampedPosition(
                requestedPositionMs,
                durationMs: videoInfo.durationMs
            )
            let image = try await generateImage(
                generator: generator,
                at: CMTime(value: positionMs, timescale: 1000)
            ).value
            let outputURL = request.outputURLs[index]
            try writeJPEG(
                image,
                to: outputURL,
                quality: Double(request.quality) / 100
            )
            try Task.checkCancellation()
            frames.append(
                VideoFrameResult(
                    outputURL: outputURL,
                    width: image.width,
                    height: image.height
                )
            )
        }
        return VideoFrameExtractionResult(videoInfo: videoInfo, frames: frames)
    }

    private func clampedPosition(_ positionMs: Int64, durationMs: Int64) -> Int64 {
        guard durationMs > 0 else { return max(0, positionMs) }
        return min(max(0, positionMs), max(0, durationMs - 1))
    }

    private func generateImage(
        generator: AVAssetImageGenerator,
        at time: CMTime
    ) async throws -> ImageBox {
        let generatorBox = ImageGeneratorBox(generator)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<ImageBox, Error>) in
                generatorBox.value.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) {
                    _, image, _, result, error in
                    if result == .cancelled {
                        continuation.resume(throwing: CancellationError())
                    } else if result == .succeeded, let image {
                        continuation.resume(returning: ImageBox(image))
                    } else {
                        continuation.resume(
                            throwing: VideoEditorError.frameExtraction(
                                "Failed to decode video frame",
                                error
                            )
                        )
                    }
                }
            }
        } onCancel: {
            generatorBox.value.cancelAllCGImageGeneration()
        }
    }

    private func writeJPEG(_ image: CGImage, to url: URL, quality: Double) throws {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? FileManager.default.removeItem(at: url)
            guard
                let destination = CGImageDestinationCreateWithURL(
                    url as CFURL,
                    "public.jpeg" as CFString,
                    1,
                    nil
                )
            else {
                throw VideoEditorError.frameWrite("Could not create JPEG destination")
            }
            let properties =
                [
                    kCGImageDestinationLossyCompressionQuality: quality
                ] as CFDictionary
            CGImageDestinationAddImage(destination, image, properties)
            guard CGImageDestinationFinalize(destination) else {
                throw VideoEditorError.frameWrite("Could not finalize JPEG output")
            }
        } catch let error as VideoEditorError {
            throw error
        } catch {
            throw VideoEditorError.frameWrite("Failed to write video frame", error)
        }
    }
}

private final class ImageGeneratorBox: @unchecked Sendable {
    let value: AVAssetImageGenerator

    init(_ value: AVAssetImageGenerator) {
        self.value = value
    }
}

private final class ImageBox: @unchecked Sendable {
    let value: CGImage

    init(_ value: CGImage) {
        self.value = value
    }
}

private actor AsyncPermitPool {
    private struct Waiter {
        let id: Int
        let continuation: CheckedContinuation<Void, Error>
    }

    private var available: Int
    private var nextWaiterID = 0
    private var waiters: [Waiter] = []

    init(limit: Int) {
        available = limit
    }

    func acquire() async throws {
        try Task.checkCancellation()
        let waiterID = nextWaiterID
        nextWaiterID += 1
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else if available > 0 {
                    available -= 1
                    continuation.resume()
                } else {
                    waiters.append(Waiter(id: waiterID, continuation: continuation))
                }
            }
        } onCancel: {
            Task { await self.cancel(waiterID) }
        }
    }

    func release() {
        if waiters.isEmpty {
            available += 1
        } else {
            waiters.removeFirst().continuation.resume()
        }
    }

    private func cancel(_ waiterID: Int) {
        guard let index = waiters.firstIndex(where: { $0.id == waiterID }) else { return }
        waiters.remove(at: index).continuation.resume(throwing: CancellationError())
    }
}
