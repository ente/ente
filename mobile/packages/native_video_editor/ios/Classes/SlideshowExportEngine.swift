import AVFoundation
import CoreImage
import ImageIO

public final class SlideshowExportEngine: Sendable {
    public init() {}

    public func export(
        _ request: SlideshowExportRequest,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        try? FileManager.default.removeItem(at: request.outputURL)
        do {
            let timeline = try await SlideshowTimeline.prepare(request)
            let session = try SlideshowWriterSession(
                request: request,
                timeline: timeline,
                onProgress: onProgress
            )
            try await session.run()
            let outputSize =
                (try? request.outputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            guard outputSize > 0 else {
                throw VideoEditorError.export("Slideshow export produced no output")
            }
            onProgress(1)
            return request.outputURL
        } catch is CancellationError {
            try? FileManager.default.removeItem(at: request.outputURL)
            throw CancellationError()
        } catch let error as VideoEditorError {
            try? FileManager.default.removeItem(at: request.outputURL)
            throw error
        } catch {
            try? FileManager.default.removeItem(at: request.outputURL)
            throw VideoEditorError.export("Failed to export slideshow", error)
        }
    }
}

struct SlideshowVideoSource: @unchecked Sendable {
    let asset: AVURLAsset
    let videoTrack: AVAssetTrack
    let audioTrack: AVAssetTrack?
    let orientation: CGImagePropertyOrientation
    let trackStart: CMTime
}

struct SlideshowSegment: @unchecked Sendable {
    let item: SlideshowItem
    let start: Double
    let duration: Double
    let video: SlideshowVideoSource?

    var end: Double { start + duration }

    var playsMusic: Bool {
        if case .photo = item { return true }
        return false
    }

    var playsVideoAudio: Bool {
        if case .video(_, let isMuted) = item, !isMuted, video?.audioTrack != nil {
            return true
        }
        return false
    }
}

struct SlideshowMusicSource: @unchecked Sendable {
    let asset: AVURLAsset
    let track: AVAssetTrack
    let fadeIn: Double
    let fadeOut: Double
}

struct SlideshowTimeline: Sendable {
    let segments: [SlideshowSegment]
    let music: SlideshowMusicSource?

    var duration: Double { segments.last?.end ?? 0 }

    var hasAudio: Bool {
        music != nil || segments.contains(where: \.playsVideoAudio)
    }

    static func prepare(_ request: SlideshowExportRequest) async throws -> SlideshowTimeline {
        var segments: [SlideshowSegment] = []
        var cursor: Double = 0
        for item in request.items {
            try Task.checkCancellation()
            switch item {
            case .photo(_, let durationMs, _):
                let duration = Double(durationMs) / 1000
                segments.append(
                    SlideshowSegment(item: item, start: cursor, duration: duration, video: nil))
                cursor += duration
            case .video(let url, _):
                let source = try await loadVideo(url)
                let duration = try await source.asset.load(.duration).seconds
                guard duration.isFinite, duration > 0 else {
                    throw VideoEditorError.composition("Slideshow video has no duration")
                }
                segments.append(
                    SlideshowSegment(item: item, start: cursor, duration: duration, video: source)
                )
                cursor += duration
            }
        }
        var music: SlideshowMusicSource?
        if let requestedMusic = request.music {
            let asset = AVURLAsset(url: requestedMusic.url)
            if let track = try await asset.loadTracks(withMediaType: .audio).first {
                music = SlideshowMusicSource(
                    asset: asset,
                    track: track,
                    fadeIn: Double(requestedMusic.fadeInMs) / 1000,
                    fadeOut: Double(requestedMusic.fadeOutMs) / 1000
                )
            }
        }
        return SlideshowTimeline(segments: segments, music: music)
    }

    private static func loadVideo(_ url: URL) async throws -> SlideshowVideoSource {
        let asset = AVURLAsset(url: url)
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw VideoEditorError.composition("Slideshow video has no video track")
        }
        let audioTrack = try await asset.loadTracks(withMediaType: .audio).first
        let transform = try await videoTrack.load(.preferredTransform)
        let timeRange = try await videoTrack.load(.timeRange)
        return SlideshowVideoSource(
            asset: asset,
            videoTrack: videoTrack,
            audioTrack: audioTrack,
            orientation: orientation(for: transform),
            trackStart: timeRange.start
        )
    }

    private static func orientation(for transform: CGAffineTransform) -> CGImagePropertyOrientation {
        let mirrored = transform.a * transform.d - transform.b * transform.c < 0
        if transform.a == 0 && transform.d == 0 {
            if transform.b > 0 { return mirrored ? .leftMirrored : .right }
            if transform.b < 0 { return mirrored ? .rightMirrored : .left }
            return .up
        }
        if transform.a < 0 { return mirrored ? .upMirrored : .down }
        return mirrored ? .downMirrored : .up
    }
}

private final class SlideshowWriterSession: @unchecked Sendable {
    private let request: SlideshowExportRequest
    private let timeline: SlideshowTimeline
    private let onProgress: @Sendable (Double) -> Void
    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let audioInput: AVAssetWriterInput?
    private let videoQueue = DispatchQueue(label: "io.ente.native_video_editor.slideshow.video")
    private let audioQueue = DispatchQueue(label: "io.ente.native_video_editor.slideshow.audio")
    private let lock = NSLock()
    private let appendLock = NSLock()
    private var terminalError: Error?
    private var pendingInputs = 0
    private var continuation: CheckedContinuation<Void, Error>?

    init(
        request: SlideshowExportRequest,
        timeline: SlideshowTimeline,
        onProgress: @escaping @Sendable (Double) -> Void
    ) throws {
        self.request = request
        self.timeline = timeline
        self.onProgress = onProgress
        writer = try AVAssetWriter(outputURL: request.outputURL, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true

        let bitsPerPixel = 0.12
        let bitrate = Int(
            Double(request.width * request.height * request.frameRate) * bitsPerPixel)
        videoInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: request.width,
                AVVideoHeightKey: request.height,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: bitrate,
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                    AVVideoExpectedSourceFrameRateKey: request.frameRate,
                    AVVideoMaxKeyFrameIntervalKey: request.frameRate * 2,
                ],
            ]
        )
        videoInput.expectsMediaDataInRealTime = false
        adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: request.width,
                kCVPixelBufferHeightKey as String: request.height,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            ]
        )
        guard writer.canAdd(videoInput) else {
            throw VideoEditorError.export("Cannot add slideshow video track")
        }
        writer.add(videoInput)

        if timeline.hasAudio {
            let input = AVAssetWriterInput(
                mediaType: .audio,
                outputSettings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: SlideshowAudioProducer.sampleRate,
                    AVNumberOfChannelsKey: SlideshowAudioProducer.channelCount,
                    AVEncoderBitRateKey: 128_000,
                ]
            )
            input.expectsMediaDataInRealTime = false
            guard writer.canAdd(input) else {
                throw VideoEditorError.export("Cannot add slideshow audio track")
            }
            writer.add(input)
            audioInput = input
        } else {
            audioInput = nil
        }
    }

    func run() async throws {
        guard writer.startWriting() else {
            throw VideoEditorError.export("Failed to start slideshow export", writer.error)
        }
        writer.startSession(atSourceTime: .zero)
        guard let pool = adaptor.pixelBufferPool else {
            writer.cancelWriting()
            throw VideoEditorError.export("Slideshow pixel buffer pool is unavailable")
        }
        let frames = SlideshowFrameProducer(request: request, timeline: timeline, pool: pool)
        let audio = audioInput == nil ? nil : try SlideshowAudioProducer(timeline: timeline)

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
                        pump(videoInput) {
                            guard let frame = try frames.next() else { return false }
                            guard append({ adaptor.append(frame.buffer, withPresentationTime: frame.time) })
                            else {
                                throw VideoEditorError.export(
                                    "Failed to append slideshow frame", writer.error)
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
                            pump(audioInput) {
                                guard let sample = try audio.next() else { return false }
                                guard append({ audioInput.append(sample) }) else {
                                    throw VideoEditorError.export(
                                        "Failed to append slideshow audio", writer.error)
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

    private func pump(_ input: AVAssetWriterInput, appendNext: () throws -> Bool) {
        while input.isReadyForMoreMediaData {
            lock.lock()
            let isRunning = terminalError == nil
            lock.unlock()
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
                        VideoEditorError.export("Failed to finish slideshow export", writer.error))
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

private func smoothstep(_ value: Double) -> Double {
    let t = min(max(value, 0), 1)
    return t * t * (3 - 2 * t)
}

private final class SlideshowFrameProducer: @unchecked Sendable {
    struct Frame {
        let buffer: CVPixelBuffer
        let time: CMTime
    }

    private struct PhotoState {
        let image: CIImage
        let background: CIImage
        let motion: SlideshowMotion
        let frameCount: Int
        var frameIndex = 0
    }

    private struct VideoState {
        let reader: AVAssetReader
        let output: AVAssetReaderTrackOutput
        var lastImage: CIImage?
        var lastFrameIndex: Int64 = -1
    }

    private static let timescale: CMTimeScale = 1_000_000

    private let request: SlideshowExportRequest
    private let segments: [SlideshowSegment]
    private let pool: CVPixelBufferPool
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
    private let frameRect: CGRect
    private let crossfade: Double
    private let frameInterval: Double
    private let estimatedFrames: Double
    private var segmentIndex = 0
    private var hold: CIImage
    private var photo: PhotoState?
    private var video: VideoState?
    private var framesWritten = 0
    private var reportedProgress = 0.0
    private var lastTime = CMTime.invalid

    init(request: SlideshowExportRequest, timeline: SlideshowTimeline, pool: CVPixelBufferPool) {
        self.request = request
        segments = timeline.segments
        self.pool = pool
        frameRect = CGRect(x: 0, y: 0, width: request.width, height: request.height)
        crossfade = Double(request.crossfadeMs) / 1000
        frameInterval = 1 / Double(request.frameRate)
        estimatedFrames = max(1, timeline.duration * Double(request.frameRate))
        hold = CIImage(color: .black).cropped(to: frameRect)
    }

    func takeProgressUpdate() -> Double? {
        let progress = min(1, Double(framesWritten) / estimatedFrames)
        guard progress - reportedProgress >= 0.01 else { return nil }
        reportedProgress = progress
        return progress
    }

    func next() throws -> Frame? {
        while segmentIndex < segments.count {
            let segment = segments[segmentIndex]
            let frame: Frame?
            switch segment.item {
            case .photo:
                frame = try nextPhotoFrame(segment)
            case .video:
                frame = try nextVideoFrame(segment)
            }
            if let frame {
                framesWritten += 1
                lastTime = frame.time
                return frame
            }
            segmentIndex += 1
        }
        return nil
    }

    private func nextPhotoFrame(_ segment: SlideshowSegment) throws -> Frame? {
        guard case .photo(let url, _, let motion) = segment.item else { return nil }
        if photo == nil {
            let maxScale = max(motion.startScale, motion.endScale)
            let maxPixelSize = Int(
                (Double(max(request.width, request.height)) * maxScale).rounded(.up))
            let image = try loadImage(url, maxPixelSize: maxPixelSize)
            let background = try renderHold(
                covered(try loadImage(url, maxPixelSize: 32))
                    .clampedToExtent()
                    .applyingGaussianBlur(sigma: 24)
                    .cropped(to: frameRect)
            )
            photo = PhotoState(
                image: image,
                background: background,
                motion: motion,
                frameCount: max(1, Int((segment.duration * Double(request.frameRate)).rounded()))
            )
        }
        guard var state = photo, state.frameIndex < state.frameCount else {
            photo = nil
            return nil
        }
        let elapsed = Double(state.frameIndex) * frameInterval
        let progress = smoothstep(elapsed / segment.duration)
        let scale = state.motion.startScale
            + (state.motion.endScale - state.motion.startScale) * progress
        let offset = CGPoint(
            x: state.motion.startOffset.x
                + (state.motion.endOffset.x - state.motion.startOffset.x) * progress,
            y: state.motion.startOffset.y
                + (state.motion.endOffset.y - state.motion.startOffset.y) * progress
        )
        let composite = fitted(state.image, scale: scale, offset: offset)
            .composited(over: state.background)
        let buffer = try render(dissolved(composite, elapsed: elapsed))
        state.frameIndex += 1
        if state.frameIndex == state.frameCount {
            hold = try renderHold(composite)
        }
        photo = state
        return Frame(buffer: buffer, time: time(segment.start + elapsed))
    }

    private func nextVideoFrame(_ segment: SlideshowSegment) throws -> Frame? {
        guard let source = segment.video else { return nil }
        if video == nil {
            let reader = try AVAssetReader(asset: source.asset)
            let output = AVAssetReaderTrackOutput(
                track: source.videoTrack,
                outputSettings: [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                ]
            )
            output.alwaysCopiesSampleData = false
            guard reader.canAdd(output) else {
                throw VideoEditorError.composition("Cannot read slideshow video frames")
            }
            reader.add(output)
            guard reader.startReading() else {
                throw VideoEditorError.composition(
                    "Failed to read slideshow video", reader.error)
            }
            video = VideoState(reader: reader, output: output)
        }
        guard var state = video else { return nil }
        while let sample = state.output.copyNextSampleBuffer() {
            guard let imageBuffer = CMSampleBufferGetImageBuffer(sample) else { continue }
            let elapsedTime = CMTimeSubtract(
                CMSampleBufferGetPresentationTimeStamp(sample), source.trackStart
            )
            let elapsed = elapsedTime.seconds
            guard elapsed >= 0, elapsed < segment.duration else { continue }
            let halfTick = 0.5 / Double(elapsedTime.timescale)
            let frameIndex = Int64((elapsed + halfTick) * Double(request.frameRate))
            guard frameIndex > state.lastFrameIndex else { continue }
            let frameTime = time(segment.start + elapsed)
            guard !lastTime.isValid || CMTimeCompare(frameTime, lastTime) > 0 else { continue }
            let image = contained(CIImage(cvPixelBuffer: imageBuffer).oriented(source.orientation))
                .composited(over: CIImage(color: .black).cropped(to: frameRect))
            let buffer = try render(dissolved(image, elapsed: elapsed))
            state.lastImage = image
            state.lastFrameIndex = frameIndex
            video = state
            return Frame(buffer: buffer, time: frameTime)
        }
        if state.reader.status == .failed {
            throw VideoEditorError.composition("Failed to decode slideshow video", state.reader.error)
        }
        if let lastImage = state.lastImage {
            hold = try renderHold(lastImage)
        }
        video = nil
        return nil
    }

    private func dissolved(_ image: CIImage, elapsed: Double) -> CIImage {
        guard segmentIndex > 0, crossfade > 0, elapsed < crossfade else { return image }
        return hold.applyingFilter(
            "CIDissolveTransition",
            parameters: [
                kCIInputTargetImageKey: image,
                kCIInputTimeKey: smoothstep(elapsed / crossfade),
            ]
        )
    }

    private func fitted(_ image: CIImage, scale: Double, offset: CGPoint) -> CIImage {
        let extent = image.extent
        let containScale = min(
            frameRect.width / extent.width, frameRect.height / extent.height)
        let totalScale = containScale * scale
        let transform = CGAffineTransform(
            translationX: frameRect.midX + offset.x * frameRect.width,
            y: frameRect.midY - offset.y * frameRect.height
        )
        .scaledBy(x: totalScale, y: totalScale)
        .translatedBy(x: -extent.midX, y: -extent.midY)
        return image.transformed(by: transform).cropped(to: frameRect)
    }

    private func contained(_ image: CIImage) -> CIImage {
        fitted(image, scale: 1, offset: .zero)
    }

    private func covered(_ image: CIImage) -> CIImage {
        let extent = image.extent
        let coverScale = max(frameRect.width / extent.width, frameRect.height / extent.height)
        let transform = CGAffineTransform(translationX: frameRect.midX, y: frameRect.midY)
            .scaledBy(x: coverScale, y: coverScale)
            .translatedBy(x: -extent.midX, y: -extent.midY)
        return image.transformed(by: transform).cropped(to: frameRect)
    }

    private func loadImage(_ url: URL, maxPixelSize: Int) throws -> CIImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let cgImage = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceShouldCacheImmediately: true,
                    kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                ] as CFDictionary
            )
        else {
            throw VideoEditorError.composition("Failed to decode slideshow photo")
        }
        return CIImage(cgImage: cgImage)
    }

    private func render(_ image: CIImage) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &buffer)
        guard status == kCVReturnSuccess, let buffer else {
            throw VideoEditorError.export("Failed to allocate slideshow frame")
        }
        context.render(image, to: buffer, bounds: frameRect, colorSpace: colorSpace)
        return buffer
    }

    private func renderHold(_ image: CIImage) throws -> CIImage {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            request.width,
            request.height,
            kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary,
            &buffer
        )
        guard status == kCVReturnSuccess, let buffer else {
            throw VideoEditorError.export("Failed to allocate slideshow transition frame")
        }
        context.render(image, to: buffer, bounds: frameRect, colorSpace: colorSpace)
        return CIImage(cvPixelBuffer: buffer)
    }

    private func time(_ seconds: Double) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: Self.timescale)
    }
}

private final class SlideshowAudioProducer: @unchecked Sendable {
    static let sampleRate = 44_100
    static let channelCount = 2
    private static let chunkFrames = 1024

    private enum Source {
        case music
        case video(SlideshowVideoSource)
        case silence
    }

    private struct AudioSegment {
        let start: Int64
        let end: Int64
        let source: Source
    }

    private struct MusicRun {
        let start: Int64
        let end: Int64
    }

    private let formatDescription: CMAudioFormatDescription
    private let segments: [AudioSegment]
    private let musicRuns: [MusicRun]
    private let music: PcmSource?
    private let fadeInFrames: Double
    private let fadeOutFrames: Double
    private var videoAudio: PcmSource?
    private var position: Int64 = 0

    init(timeline: SlideshowTimeline) throws {
        let sampleRate = Double(Self.sampleRate)
        var segments: [AudioSegment] = []
        var runs: [MusicRun] = []
        for segment in timeline.segments {
            let start = Int64((segment.start * sampleRate).rounded())
            let end = Int64((segment.end * sampleRate).rounded())
            guard end > start else { continue }
            let source: Source
            if segment.playsMusic, timeline.music != nil {
                source = .music
                if let last = runs.last, last.end == start {
                    runs[runs.count - 1] = MusicRun(start: last.start, end: end)
                } else {
                    runs.append(MusicRun(start: start, end: end))
                }
            } else if segment.playsVideoAudio, let video = segment.video {
                source = .video(video)
            } else {
                source = .silence
            }
            segments.append(AudioSegment(start: start, end: end, source: source))
        }
        self.segments = segments
        musicRuns = runs
        music = timeline.music.map { PcmSource(asset: $0.asset, track: $0.track) }
        fadeInFrames = (timeline.music?.fadeIn ?? 0) * sampleRate
        fadeOutFrames = (timeline.music?.fadeOut ?? 0) * sampleRate

        var description = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(Self.channelCount * 2),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(Self.channelCount * 2),
            mChannelsPerFrame: UInt32(Self.channelCount),
            mBitsPerChannel: 16,
            mReserved: 0
        )
        var formatDescription: CMAudioFormatDescription?
        let status = CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &description,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDescription
        )
        guard status == noErr, let formatDescription else {
            throw VideoEditorError.export("Failed to describe slideshow audio")
        }
        self.formatDescription = formatDescription
    }

    func next() throws -> CMSampleBuffer? {
        guard let segment = segments.first(where: { position >= $0.start && position < $0.end })
        else {
            return nil
        }
        let frames = Int(min(Int64(Self.chunkFrames), segment.end - position))
        var samples = [Int16](repeating: 0, count: frames * Self.channelCount)
        switch segment.source {
        case .music:
            if let music {
                try music.read(into: &samples, frames: frames, loops: true)
                applyMusicGain(to: &samples, frames: frames)
            }
        case .video(let source):
            if videoAudio == nil, let track = source.audioTrack {
                videoAudio = PcmSource(asset: source.asset, track: track)
            }
            try videoAudio?.read(into: &samples, frames: frames, loops: false)
        case .silence:
            break
        }
        let sample = try makeSampleBuffer(samples, frames: frames, at: position)
        position += Int64(frames)
        if position >= segment.end {
            videoAudio = nil
        }
        return sample
    }

    private func applyMusicGain(to samples: inout [Int16], frames: Int) {
        guard let run = musicRuns.first(where: { position >= $0.start && position < $0.end })
        else {
            return
        }
        for frame in 0..<frames {
            let absolute = Double(position + Int64(frame))
            var gain = 1.0
            if fadeInFrames > 0 {
                gain = min(gain, (absolute - Double(run.start)) / fadeInFrames)
            }
            if fadeOutFrames > 0 {
                gain = min(gain, (Double(run.end) - absolute) / fadeOutFrames)
            }
            guard gain < 1 else { continue }
            let clamped = Float(max(gain, 0))
            for channel in 0..<Self.channelCount {
                let index = frame * Self.channelCount + channel
                samples[index] = Int16((Float(samples[index]) * clamped).rounded())
            }
        }
    }

    private func makeSampleBuffer(
        _ samples: [Int16],
        frames: Int,
        at position: Int64
    ) throws -> CMSampleBuffer {
        let byteCount = samples.count * MemoryLayout<Int16>.size
        var blockBuffer: CMBlockBuffer?
        var status = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: byteCount,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: byteCount,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard status == kCMBlockBufferNoErr, let blockBuffer else {
            throw VideoEditorError.export("Failed to allocate slideshow audio")
        }
        status = samples.withUnsafeBytes { bytes in
            CMBlockBufferReplaceDataBytes(
                with: bytes.baseAddress!,
                blockBuffer: blockBuffer,
                offsetIntoDestination: 0,
                dataLength: byteCount
            )
        }
        guard status == kCMBlockBufferNoErr else {
            throw VideoEditorError.export("Failed to copy slideshow audio")
        }
        var sampleBuffer: CMSampleBuffer?
        status = CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: formatDescription,
            sampleCount: frames,
            presentationTimeStamp: CMTime(value: position, timescale: CMTimeScale(Self.sampleRate)),
            packetDescriptions: nil,
            sampleBufferOut: &sampleBuffer
        )
        guard status == noErr, let sampleBuffer else {
            throw VideoEditorError.export("Failed to build slideshow audio")
        }
        return sampleBuffer
    }
}

private final class PcmSource {
    private let asset: AVAsset
    private let track: AVAssetTrack
    private var reader: AVAssetReader?
    private var output: AVAssetReaderAudioMixOutput?
    private var pending: [Int16] = []
    private var pendingOffset = 0
    private var exhausted = false

    init(asset: AVAsset, track: AVAssetTrack) {
        self.asset = asset
        self.track = track
    }

    func read(into samples: inout [Int16], frames: Int, loops: Bool) throws {
        let channels = SlideshowAudioProducer.channelCount
        var filled = 0
        var restarted = false
        while filled < frames {
            if pendingOffset < pending.count {
                let available = (pending.count - pendingOffset) / channels
                let count = min(available, frames - filled)
                let start = pendingOffset
                for index in 0..<(count * channels) {
                    samples[filled * channels + index] = pending[start + index]
                }
                pendingOffset += count * channels
                filled += count
                continue
            }
            if try refill() { continue }
            guard loops, !restarted else { return }
            restarted = true
            reader = nil
            output = nil
            exhausted = false
        }
    }

    private func refill() throws -> Bool {
        if exhausted { return false }
        if reader == nil { try start() }
        guard let output, let reader else { return false }
        pending.removeAll(keepingCapacity: true)
        pendingOffset = 0
        while let sample = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            guard length > 0 else { continue }
            let count = length / MemoryLayout<Int16>.size
            pending = [Int16](repeating: 0, count: count)
            let status = pending.withUnsafeMutableBytes { bytes in
                CMBlockBufferCopyDataBytes(
                    block, atOffset: 0, dataLength: length, destination: bytes.baseAddress!)
            }
            guard status == kCMBlockBufferNoErr else {
                throw VideoEditorError.export("Failed to read slideshow audio")
            }
            return true
        }
        if reader.status == .failed {
            throw VideoEditorError.export("Failed to decode slideshow audio", reader.error)
        }
        exhausted = true
        return false
    }

    private func start() throws {
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderAudioMixOutput(
            audioTracks: [track],
            audioSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: SlideshowAudioProducer.sampleRate,
                AVNumberOfChannelsKey: SlideshowAudioProducer.channelCount,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ]
        )
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else {
            throw VideoEditorError.export("Cannot read slideshow audio track")
        }
        reader.add(output)
        guard reader.startReading() else {
            throw VideoEditorError.export("Failed to start slideshow audio", reader.error)
        }
        self.reader = reader
        self.output = output
    }
}
