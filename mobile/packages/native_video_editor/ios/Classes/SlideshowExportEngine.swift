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
            let session = try VideoWriterSession(
                settings: VideoWriterSettings(
                    outputURL: request.outputURL,
                    width: request.width,
                    height: request.height,
                    frameRate: request.frameRate,
                    bitrate: request.videoBitrate,
                    audio: timeline.hasAudio
                        ? VideoWriterAudioSettings(
                            sampleRate: SlideshowAudioProducer.sampleRate,
                            channelCount: SlideshowAudioProducer.channelCount
                        )
                        : nil
                ),
                onProgress: onProgress
            )
            try await session.run(
                frames: { SlideshowFrameProducer(request: request, timeline: timeline, pool: $0) },
                audio: { try SlideshowAudioProducer(timeline: timeline) }
            )
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
    var readRange: CMTimeRange?
}

struct SlideshowSegment: @unchecked Sendable {
    let item: SlideshowItem
    let start: Double
    let duration: Double
    let video: SlideshowVideoSource?

    var end: Double { start + duration }

    var playsVideoAudio: Bool {
        if case .video(_, let isMuted, _) = item, !isMuted, video?.audioTrack != nil {
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
    let duckedVolume: Double
    let duckFade: Double

    var videoAudioGain: Double { 1 / (1 + duckedVolume) }
    var duckedMusicGain: Double { duckedVolume * videoAudioGain }
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
            case .video(let url, _, let maxDurationMs):
                var source = try await loadVideo(url)
                var duration = try await source.asset.load(.duration).seconds
                guard duration.isFinite, duration > 0 else {
                    throw VideoEditorError.composition("Slideshow video has no duration")
                }
                if let maxDurationMs, Double(maxDurationMs) / 1000 < duration {
                    duration = Double(maxDurationMs) / 1000
                    source.readRange = CMTimeRange(
                        start: source.trackStart,
                        duration: CMTime(seconds: duration, preferredTimescale: 600)
                    )
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
                    fadeOut: Double(requestedMusic.fadeOutMs) / 1000,
                    duckedVolume: requestedMusic.duckedVolume,
                    duckFade: Double(requestedMusic.duckFadeMs) / 1000
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

private func smoothstep(_ value: Double) -> Double {
    let t = min(max(value, 0), 1)
    return t * t * (3 - 2 * t)
}

private final class SlideshowFrameProducer: VideoWriterFrameSource, @unchecked Sendable {
    typealias Frame = VideoWriterFrame

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
        var background: CIImage?
        var lastImage: CIImage?
        var lastFrameIndex: Int64 = -1
    }

    private static let timescale: CMTimeScale = 1_000_000
    private static let backgroundSampleSize = 32

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
                blurredBackground(
                    try loadImage(url, maxPixelSize: Self.backgroundSampleSize)))
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
            if let readRange = source.readRange {
                reader.timeRange = readRange
            }
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
            let frame = CIImage(cvPixelBuffer: imageBuffer).oriented(source.orientation)
            let background = try state.background ?? videoBackground(for: frame)
            state.background = background
            let image = contained(frame).composited(over: background)
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
        let totalScale = containScale(for: extent) * scale
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

    private func containScale(for extent: CGRect) -> CGFloat {
        min(frameRect.width / extent.width, frameRect.height / extent.height)
    }

    private func videoBackground(for frame: CIImage) throws -> CIImage {
        let extent = frame.extent
        let scale = containScale(for: extent)
        guard
            frameRect.width - extent.width * scale >= 1
                || frameRect.height - extent.height * scale >= 1
        else { return CIImage(color: .black).cropped(to: frameRect) }
        return try renderHold(blurredBackground(shrunk(frame, to: Self.backgroundSampleSize)))
    }

    private func blurredBackground(_ sample: CIImage) -> CIImage {
        covered(sample)
            .clampedToExtent()
            .applyingGaussianBlur(sigma: 24)
            .cropped(to: frameRect)
    }

    private func shrunk(_ image: CIImage, to maxPixelSize: Int) -> CIImage {
        let longSide = max(image.extent.width, image.extent.height)
        guard longSide > CGFloat(maxPixelSize) else { return image }
        let scale = CGFloat(maxPixelSize) / longSide
        return image.clampedToExtent()
            .applyingFilter(
                "CILanczosScaleTransform",
                parameters: [
                    kCIInputScaleKey: scale,
                    kCIInputAspectRatioKey: 1,
                ]
            )
            .cropped(to: image.extent.applying(CGAffineTransform(scaleX: scale, y: scale)).integral)
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

private final class SlideshowAudioProducer: VideoWriterAudioSource, @unchecked Sendable {
    static let sampleRate = 44_100
    static let channelCount = 2
    private static let chunkFrames: Int64 = 1024

    private struct VideoAudio {
        let start: Int64
        let end: Int64
        let asset: AVAsset
        let track: AVAssetTrack
    }

    private let formatDescription: CMAudioFormatDescription
    private let totalFrames: Int64
    private let videoAudio: [VideoAudio]
    private let music: PcmSource?
    private let musicEnvelope: SlideshowMusicEnvelope?
    private let videoAudioGain: Float
    private var videoReader: PcmSource?
    private var videoReaderIndex: Int?
    private var position: Int64 = 0

    init(timeline: SlideshowTimeline) throws {
        let sampleRate = Double(Self.sampleRate)
        let totalFrames = Int64((timeline.duration * sampleRate).rounded())
        let audibleSegments = timeline.segments.filter(\.playsVideoAudio)
        let videoAudio: [VideoAudio] = audibleSegments.compactMap { segment in
            guard let video = segment.video, let track = video.audioTrack else { return nil }
            let start = Int64((segment.start * sampleRate).rounded())
            let end = Int64((segment.end * sampleRate).rounded())
            guard end > start else { return nil }
            return VideoAudio(start: start, end: end, asset: video.asset, track: track)
        }
        self.totalFrames = totalFrames
        self.videoAudio = videoAudio
        music = timeline.music.map { PcmSource(asset: $0.asset, track: $0.track) }
        videoAudioGain = Float(timeline.music?.videoAudioGain ?? 1)
        musicEnvelope = timeline.music.map { music in
            SlideshowMusicEnvelope(
                totalFrames: Double(totalFrames),
                fadeInFrames: music.fadeIn * sampleRate,
                fadeOutFrames: music.fadeOut * sampleRate,
                duckedMusicGain: music.duckedMusicGain,
                duckFadeFrames: music.duckFade * sampleRate,
                videoAudio: audibleSegments.map {
                    (start: $0.start * sampleRate, end: $0.end * sampleRate)
                }
            )
        }

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
        guard position < totalFrames else { return nil }
        let videoIndex = videoAudio.firstIndex { position >= $0.start && position < $0.end }
        var chunkEnd = min(position + Self.chunkFrames, totalFrames)
        if let videoIndex {
            chunkEnd = min(chunkEnd, videoAudio[videoIndex].end)
        } else if let upcoming = videoAudio.first(where: { $0.start > position }) {
            chunkEnd = min(chunkEnd, upcoming.start)
        }
        let frames = Int(chunkEnd - position)
        var samples = [Int16](repeating: 0, count: frames * Self.channelCount)
        if let music, let musicEnvelope {
            try music.read(into: &samples, frames: frames, loops: true)
            applyMusicGain(musicEnvelope, to: &samples, frames: frames)
        }
        if let videoIndex {
            try mixVideoAudio(videoIndex, into: &samples, frames: frames)
        } else {
            videoReader = nil
            videoReaderIndex = nil
        }
        let sample = try makeSampleBuffer(samples, frames: frames, at: position)
        position = chunkEnd
        return sample
    }

    private func mixVideoAudio(_ index: Int, into samples: inout [Int16], frames: Int) throws {
        if videoReaderIndex != index {
            let video = videoAudio[index]
            videoReader = PcmSource(asset: video.asset, track: video.track)
            videoReaderIndex = index
        }
        var video = [Int16](repeating: 0, count: samples.count)
        try videoReader?.read(into: &video, frames: frames, loops: false)
        for sample in samples.indices {
            let scaled = Int32((Float(video[sample]) * videoAudioGain).rounded())
            samples[sample] = Int16(clamping: Int32(samples[sample]) + scaled)
        }
    }

    private func applyMusicGain(
        _ envelope: SlideshowMusicEnvelope,
        to samples: inout [Int16],
        frames: Int
    ) {
        for frame in 0..<frames {
            let gain = envelope.gain(at: Double(position + Int64(frame)))
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

private struct SlideshowMusicEnvelope {
    let totalFrames: Double
    let fadeInFrames: Double
    let fadeOutFrames: Double
    let duckedMusicGain: Double
    let duckFadeFrames: Double
    let ducks: [(start: Double, end: Double)]

    init(
        totalFrames: Double,
        fadeInFrames: Double,
        fadeOutFrames: Double,
        duckedMusicGain: Double,
        duckFadeFrames: Double,
        videoAudio: [(start: Double, end: Double)]
    ) {
        self.totalFrames = totalFrames
        self.fadeInFrames = fadeInFrames
        self.fadeOutFrames = fadeOutFrames
        self.duckedMusicGain = duckedMusicGain
        self.duckFadeFrames = duckFadeFrames
        var ducks: [(start: Double, end: Double)] = []
        for range in videoAudio {
            if let last = ducks.last, (range.start - last.end).rounded() <= 2 * duckFadeFrames {
                ducks[ducks.count - 1] = (last.start, range.end)
            } else {
                ducks.append(range)
            }
        }
        self.ducks = ducks
    }

    func gain(at frame: Double) -> Double {
        var gain = 1.0
        if fadeInFrames > 0 {
            gain = min(gain, frame / fadeInFrames)
        }
        if fadeOutFrames > 0 {
            gain = min(gain, (totalFrames - frame) / fadeOutFrames)
        }
        return max(gain, 0) * duckLevel(at: frame)
    }

    private func duckLevel(at frame: Double) -> Double {
        var level = 1.0
        var index = firstDuck(endingAfter: frame - duckFadeFrames)
        while index < ducks.count, ducks[index].start - duckFadeFrames <= frame {
            let duck = ducks[index]
            index += 1
            let depth: Double
            if frame >= duck.start, frame < duck.end {
                depth = 1
            } else if duckFadeFrames <= 0 {
                depth = 0
            } else if frame < duck.start {
                depth = 1 - (duck.start - frame) / duckFadeFrames
            } else {
                depth = 1 - (frame - duck.end) / duckFadeFrames
            }
            guard depth > 0 else { continue }
            level = min(level, 1 - depth * (1 - duckedMusicGain))
        }
        return level
    }

    private func firstDuck(endingAfter frame: Double) -> Int {
        var low = 0
        var high = ducks.count
        while low < high {
            let middle = (low + high) / 2
            if ducks[middle].end <= frame {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low
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
