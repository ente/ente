import AVFoundation

public final class VideoExportEngine: Sendable {
    public init() {}

    public func export(
        _ request: VideoEditRequest,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> VideoEditResult {
        try? FileManager.default.removeItem(at: request.outputURL)
        do {
            let prepared = try await prepareExport(request)
            let session = prepared.session
            let sessionBox = ExportSessionBox(session)
            let progressTask = Task {
                while !Task.isCancelled {
                    onProgress(Double(sessionBox.value.progress))
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
            }
            defer { progressTask.cancel() }

            try await run(session)
            onProgress(1)
            let outputSize =
                (try? request.outputURL.resourceValues(
                    forKeys: [.fileSizeKey]
                ).fileSize) ?? 0
            guard outputSize > 0 else {
                throw VideoEditorError.export("Export produced no output")
            }
            return VideoEditResult(
                outputURL: request.outputURL,
                isReEncoded: prepared.isReEncoded
            )
        } catch is CancellationError {
            try? FileManager.default.removeItem(at: request.outputURL)
            throw CancellationError()
        } catch let error as VideoEditorError {
            try? FileManager.default.removeItem(at: request.outputURL)
            throw error
        } catch {
            try? FileManager.default.removeItem(at: request.outputURL)
            throw VideoEditorError.export("Failed to process video", error)
        }
    }

    private func prepareExport(
        _ request: VideoEditRequest
    ) async throws -> (session: AVAssetExportSession, isReEncoded: Bool) {
        let asset = AVURLAsset(url: request.inputURL)
        let duration = try await asset.load(.duration)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else {
            throw VideoEditorError.composition("Video track is unavailable")
        }

        let videoTrackRange = try await videoTrack.load(.timeRange)
        let naturalSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        let composition = AVMutableComposition()
        guard
            let compositionVideoTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
        else {
            throw VideoEditorError.composition("Failed to create video track")
        }

        let requestedRange: CMTimeRange
        if let trimStartMs = request.trimStartMs, let trimEndMs = request.trimEndMs {
            requestedRange = CMTimeRange(
                start: CMTime(value: trimStartMs, timescale: 1000),
                end: CMTime(value: trimEndMs, timescale: 1000)
            )
        } else {
            requestedRange = CMTimeRange(start: .zero, duration: duration)
        }
        guard let videoTimeRange = validIntersection(requestedRange, videoTrackRange) else {
            throw VideoEditorError.invalidTimeRange(
                "The edit range does not contain video"
            )
        }

        var compositionAudioTrack: AVMutableCompositionTrack?
        do {
            try compositionVideoTrack.insertTimeRange(videoTimeRange, of: videoTrack, at: .zero)
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            if let audioTrack = audioTracks.first {
                let audioTrackRange = try await audioTrack.load(.timeRange)
                if let audioTimeRange = validIntersection(videoTimeRange, audioTrackRange),
                    let mutableAudioTrack = composition.addMutableTrack(
                        withMediaType: .audio,
                        preferredTrackID: kCMPersistentTrackID_Invalid
                    )
                {
                    try mutableAudioTrack.insertTimeRange(
                        audioTimeRange,
                        of: audioTrack,
                        at: CMTimeSubtract(audioTimeRange.start, videoTimeRange.start)
                    )
                    compositionAudioTrack = mutableAudioTrack
                }
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw VideoEditorError.composition("Failed to insert media track", error)
        }

        if request.speed != 1 {
            let sourceTimeRange = CMTimeRange(start: .zero, duration: composition.duration)
            let outputDuration = CMTimeMultiplyByFloat64(
                sourceTimeRange.duration,
                multiplier: 1 / request.speed
            )
            compositionVideoTrack.scaleTimeRange(sourceTimeRange, toDuration: outputDuration)
            compositionAudioTrack?.scaleTimeRange(sourceTimeRange, toDuration: outputDuration)
        }

        let isReEncoded =
            request.crop != nil || (request.rotateDegrees ?? 0) != 0 || request.speed != 1
        var videoComposition: AVMutableVideoComposition?
        if isReEncoded {
            let transformPlan = try VideoTransformPlanner.makePlan(
                naturalSize: naturalSize,
                preferredTransform: preferredTransform,
                crop: request.crop,
                rotateDegrees: request.rotateDegrees
            )
            let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)
            let minimumFrameDuration = try await videoTrack.load(.minFrameDuration)
            let mutableVideoComposition = AVMutableVideoComposition()
            mutableVideoComposition.frameDuration = frameDuration(
                nominalFrameRate: nominalFrameRate,
                minimumFrameDuration: minimumFrameDuration
            )
            mutableVideoComposition.renderSize = transformPlan.renderSize

            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: .zero, duration: composition.duration)
            let layerInstruction = AVMutableVideoCompositionLayerInstruction(
                assetTrack: compositionVideoTrack
            )
            layerInstruction.setTransform(transformPlan.transform, at: .zero)
            instruction.layerInstructions = [layerInstruction]
            mutableVideoComposition.instructions = [instruction]
            videoComposition = mutableVideoComposition
        } else {
            compositionVideoTrack.preferredTransform = preferredTransform
        }

        let preset =
            isReEncoded
            ? AVAssetExportPresetHighestQuality
            : AVAssetExportPresetPassthrough
        guard let session = AVAssetExportSession(asset: composition, presetName: preset) else {
            throw VideoEditorError.export("Failed to create export session")
        }
        session.videoComposition = videoComposition
        session.outputURL = request.outputURL
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true
        if !isReEncoded {
            session.timeRange = CMTimeRange(start: .zero, duration: composition.duration)
        }
        return (session, isReEncoded)
    }

    private func run(_ session: AVAssetExportSession) async throws {
        let sessionBox = ExportSessionBox(session)
        try await withTaskCancellationHandler(
            operation: {
                try await withCheckedThrowingContinuation { continuation in
                    sessionBox.value.exportAsynchronously {
                        switch sessionBox.value.status {
                        case .completed:
                            continuation.resume()
                        case .cancelled:
                            continuation.resume(throwing: CancellationError())
                        case .failed:
                            continuation.resume(
                                throwing: VideoEditorError.export(
                                    "Failed to process video",
                                    sessionBox.value.error
                                )
                            )
                        default:
                            continuation.resume(
                                throwing: VideoEditorError.export(
                                    "Unknown export status",
                                    sessionBox.value.error
                                )
                            )
                        }
                    }
                }
            },
            onCancel: {
                sessionBox.value.cancelExport()
            })
    }

    private func validIntersection(
        _ requestedRange: CMTimeRange,
        _ availableRange: CMTimeRange
    ) -> CMTimeRange? {
        let intersection = CMTimeRangeGetIntersection(
            requestedRange,
            otherRange: availableRange
        )
        guard intersection.isValid,
            !intersection.isEmpty,
            intersection.duration.isNumeric,
            CMTimeCompare(intersection.duration, .zero) > 0
        else {
            return nil
        }
        return intersection
    }

    private func frameDuration(
        nominalFrameRate: Float,
        minimumFrameDuration: CMTime
    ) -> CMTime {
        if nominalFrameRate.isFinite && nominalFrameRate > 0 {
            return CMTime(value: 1, timescale: Int32(round(nominalFrameRate)))
        }
        if minimumFrameDuration.isValid && minimumFrameDuration.value != 0 {
            return minimumFrameDuration
        }
        return CMTime(value: 1, timescale: 30)
    }
}

private final class ExportSessionBox: @unchecked Sendable {
    let value: AVAssetExportSession

    init(_ value: AVAssetExportSession) {
        self.value = value
    }
}
