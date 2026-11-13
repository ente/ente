import AVFoundation

public struct VideoMetadataReader: Sendable {
    public init() {}

    public func read(from url: URL) async throws -> VideoMetadata {
        try await read(from: AVURLAsset(url: url))
    }

    func read(from asset: AVAsset) async throws -> VideoMetadata {
        do {
            let duration = try await asset.load(.duration)
            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            guard let videoTrack = videoTracks.first else {
                throw VideoEditorError.metadataUnavailable("Video track is unavailable")
            }

            let naturalSize = try await videoTrack.load(.naturalSize)
            let transform = try await videoTrack.load(.preferredTransform)
            let frameRate = try await videoTrack.load(.nominalFrameRate)
            let dataRate = try await videoTrack.load(.estimatedDataRate)
            return try makeMetadata(
                duration: duration,
                naturalSize: naturalSize,
                transform: transform,
                frameRate: frameRate,
                dataRate: dataRate
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as VideoEditorError {
            throw error
        } catch {
            throw VideoEditorError.metadataUnavailable(
                "Failed to load video metadata",
                error
            )
        }
    }

    private func makeMetadata(
        duration: CMTime,
        naturalSize: CGSize,
        transform: CGAffineTransform,
        frameRate: Float,
        dataRate: Float
    ) throws -> VideoMetadata {
        let durationSeconds = CMTimeGetSeconds(duration)
        let transformedBounds = CGRect(origin: .zero, size: naturalSize).applying(transform)
        let angle = atan2(transform.b, transform.a) * 180 / .pi
        let roundedAngle = Int(angle.rounded())
        let rotation = ((roundedAngle % 360) + 360) % 360
        let width = Int(abs(naturalSize.width).rounded())
        let height = Int(abs(naturalSize.height).rounded())
        let displayWidth = Int(abs(transformedBounds.width).rounded())
        let displayHeight = Int(abs(transformedBounds.height).rounded())
        guard width > 0,
            height > 0,
            displayWidth > 0,
            displayHeight > 0,
            [0, 90, 180, 270].contains(rotation)
        else {
            throw VideoEditorError.metadataUnavailable("Invalid video dimensions or rotation")
        }

        return VideoMetadata(
            durationMs: durationSeconds.isFinite
                ? Int64(max(0, durationSeconds * 1000))
                : 0,
            width: width,
            height: height,
            displayWidth: displayWidth,
            displayHeight: displayHeight,
            rotationDegrees: rotation,
            bitrate: dataRate > 0 ? Int64(dataRate) : nil,
            frameRate: frameRate > 0 ? Double(frameRate) : nil
        )
    }
}
