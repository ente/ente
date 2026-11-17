import AVFoundation

struct VideoWriterFrame {
    let buffer: CVPixelBuffer
    let time: CMTime
}

protocol VideoWriterFrameSource: AnyObject {
    func next() throws -> VideoWriterFrame?
    func takeProgressUpdate() -> Double?
}

protocol VideoWriterAudioSource: AnyObject {
    func next() throws -> CMSampleBuffer?
}

struct VideoWriterSettings {
    let outputURL: URL
    let width: Int
    let height: Int
    let frameRate: Int
    let bitrate: Int
    var colorProperties: [String: String]?
    var optimizesForNetworkUse = true
    var audio: VideoWriterAudioSettings?
}

struct VideoWriterAudioSettings {
    let sampleRate: Int
    let channelCount: Int
}

final class VideoWriterSession: @unchecked Sendable {
    private let onProgress: @Sendable (Double) -> Void
    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let audioInput: AVAssetWriterInput?
    private let videoQueue = DispatchQueue(label: "io.ente.native_video_editor.writer.video")
    private let audioQueue = DispatchQueue(label: "io.ente.native_video_editor.writer.audio")
    private let lock = NSLock()
    private let appendLock = NSLock()
    private var terminalError: Error?
    private var pendingInputs = 0
    private var continuation: CheckedContinuation<Void, Error>?

    init(
        settings: VideoWriterSettings,
        onProgress: @escaping @Sendable (Double) -> Void
    ) throws {
        self.onProgress = onProgress
        writer = try AVAssetWriter(outputURL: settings.outputURL, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = settings.optimizesForNetworkUse

        var outputSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: settings.width,
            AVVideoHeightKey: settings.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: settings.bitrate,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoExpectedSourceFrameRateKey: settings.frameRate,
                AVVideoMaxKeyFrameIntervalKey: settings.frameRate * 2,
            ],
        ]
        if let colorProperties = settings.colorProperties {
            outputSettings[AVVideoColorPropertiesKey] = colorProperties
        }
        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: outputSettings)
        videoInput.expectsMediaDataInRealTime = false
        adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: settings.width,
                kCVPixelBufferHeightKey as String: settings.height,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            ]
        )
        guard writer.canAdd(videoInput) else {
            throw VideoEditorError.export("Cannot add video track")
        }
        writer.add(videoInput)

        if let audio = settings.audio {
            let input = AVAssetWriterInput(
                mediaType: .audio,
                outputSettings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: audio.sampleRate,
                    AVNumberOfChannelsKey: audio.channelCount,
                    AVEncoderBitRateKey: 128_000,
                ]
            )
            input.expectsMediaDataInRealTime = false
            guard writer.canAdd(input) else {
                throw VideoEditorError.export("Cannot add audio track")
            }
            writer.add(input)
            audioInput = input
        } else {
            audioInput = nil
        }
    }

    func run(
        frames makeFrames: (CVPixelBufferPool) throws -> VideoWriterFrameSource,
        audio makeAudio: () throws -> VideoWriterAudioSource?
    ) async throws {
        guard writer.startWriting() else {
            throw VideoEditorError.export("Failed to start video export", writer.error)
        }
        writer.startSession(atSourceTime: .zero)
        guard let pool = adaptor.pixelBufferPool else {
            writer.cancelWriting()
            throw VideoEditorError.export("Video pixel buffer pool is unavailable")
        }
        let frames = try makeFrames(pool)
        let audio = audioInput == nil ? nil : try makeAudio()

        try await withTaskCancellationHandler(
            operation: {
                try await withCheckedThrowingContinuation { continuation in
                    lock.lock()
                    self.continuation = continuation
                    pendingInputs = audio == nil ? 1 : 2
                    let error = terminalError
                    lock.unlock()
                    if let error {
                        resume(with: .failure(error))
                        return
                    }
                    videoInput.requestMediaDataWhenReady(on: videoQueue) { [self] in
                        pump(videoInput, on: videoQueue) {
                            guard let frame = try frames.next() else { return false }
                            guard append({ adaptor.append(frame.buffer, withPresentationTime: frame.time) })
                            else {
                                throw VideoEditorError.export(
                                    "Failed to append video frame", writer.error)
                            }
                            if let progress = frames.takeProgressUpdate() {
                                onProgress(progress)
                            }
                            return true
                        }
                    }
                    if let audio {
                        audioInput?.requestMediaDataWhenReady(on: audioQueue) { [self] in
                            guard let audioInput else { return }
                            pump(audioInput, on: audioQueue) {
                                guard let sample = try audio.next() else { return false }
                                guard append({ audioInput.append(sample) }) else {
                                    throw VideoEditorError.export(
                                        "Failed to append audio", writer.error)
                                }
                                return true
                            }
                        }
                    }
                }
            },
            onCancel: {
                terminate(with: CancellationError())
            }
        )
    }

    private func append(_ body: () -> Bool) -> Bool {
        appendLock.lock()
        defer { appendLock.unlock() }
        return body()
    }

    private func pump(
        _ input: AVAssetWriterInput,
        on queue: DispatchQueue,
        appendNext: () throws -> Bool
    ) {
        while input.isReadyForMoreMediaData {
            guard isRunning else { return }
            do {
                guard try autoreleasepool(invoking: appendNext) else {
                    finish(input)
                    return
                }
            } catch {
                terminate(with: error)
                return
            }
        }
        watchForFailure(input, on: queue)
    }

    private func watchForFailure(_ input: AVAssetWriterInput, on queue: DispatchQueue) {
        queue.asyncAfter(deadline: .now() + .milliseconds(250)) { [self] in
            guard isRunning, !input.isReadyForMoreMediaData else { return }
            switch writer.status {
            case .writing:
                watchForFailure(input, on: queue)
            case .failed:
                terminate(with: VideoEditorError.export("Video writer failed", writer.error))
            default:
                return
            }
        }
    }

    private var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return terminalError == nil
    }

    private func finish(_ input: AVAssetWriterInput) {
        input.markAsFinished()
        lock.lock()
        defer { lock.unlock() }
        guard terminalError == nil else { return }
        pendingInputs -= 1
        guard pendingInputs == 0 else { return }
        writer.finishWriting { [self] in
            if writer.status == .completed {
                resume(with: .success(()))
            } else {
                resume(
                    with: .failure(
                        VideoEditorError.export("Failed to finish video export", writer.error))
                )
            }
        }
    }

    private func terminate(with error: Error) {
        lock.lock()
        guard terminalError == nil else {
            lock.unlock()
            return
        }
        terminalError = error
        lock.unlock()
        appendLock.lock()
        writer.cancelWriting()
        appendLock.unlock()
        resume(with: .failure(error))
    }

    private func resume(with result: Result<Void, Error>) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }
}
