import AVFoundation

public struct VideoMetadata: Equatable, Sendable {
    public let durationMs: Int64
    public let width: Int
    public let height: Int
    public let displayWidth: Int
    public let displayHeight: Int
    public let rotationDegrees: Int
    public let bitrate: Int64?
    public let frameRate: Double?

    public init(
        durationMs: Int64,
        width: Int,
        height: Int,
        displayWidth: Int,
        displayHeight: Int,
        rotationDegrees: Int,
        bitrate: Int64?,
        frameRate: Double?
    ) {
        self.durationMs = durationMs
        self.width = width
        self.height = height
        self.displayWidth = displayWidth
        self.displayHeight = displayHeight
        self.rotationDegrees = rotationDegrees
        self.bitrate = bitrate
        self.frameRate = frameRate
    }
}

public enum VideoFramePolicy: Sendable {
    case precise
    case nearestSync
}

public struct VideoFrameRequest: Sendable {
    public let inputURL: URL
    public let outputURLs: [URL]
    public let positionsMs: [Int64]
    public let maxWidth: Int
    public let maxHeight: Int
    public let quality: Int
    public let policy: VideoFramePolicy

    public init(
        inputURL: URL,
        outputURLs: [URL],
        positionsMs: [Int64],
        maxWidth: Int,
        maxHeight: Int,
        quality: Int,
        policy: VideoFramePolicy
    ) throws {
        let inputURL = inputURL.standardizedFileURL.resolvingSymlinksInPath()
        let outputURLs = outputURLs.map {
            $0.standardizedFileURL.resolvingSymlinksInPath()
        }
        guard FileManager.default.fileExists(atPath: inputURL.path),
            !positionsMs.isEmpty,
            positionsMs.count == outputURLs.count,
            positionsMs.allSatisfy({ $0 >= 0 }),
            !outputURLs.contains(inputURL),
            Set(outputURLs.map(\.path)).count == outputURLs.count,
            maxWidth > 0,
            maxHeight > 0,
            (1...100).contains(quality)
        else {
            throw VideoEditorError.invalidRequest("Invalid frame extraction request")
        }
        self.inputURL = inputURL
        self.outputURLs = outputURLs
        self.positionsMs = positionsMs
        self.maxWidth = maxWidth
        self.maxHeight = maxHeight
        self.quality = quality
        self.policy = policy
    }
}

public struct VideoFrameResult: Equatable, Sendable {
    public let outputURL: URL
    public let width: Int
    public let height: Int
}

public struct VideoFrameExtractionResult: Equatable, Sendable {
    public let videoInfo: VideoMetadata
    public let frames: [VideoFrameResult]
}

public struct VideoCrop: Equatable, Sendable {
    public let x: Int
    public let y: Int
    public let width: Int
    public let height: Int

    public init(x: Int, y: Int, width: Int, height: Int) throws {
        guard x >= 0, y >= 0, width > 0, height > 0 else {
            throw VideoEditorError.invalidRequest("Invalid crop rectangle")
        }
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct VideoEditRequest: Sendable {
    public let inputURL: URL
    public let outputURL: URL
    public let trimStartMs: Int64?
    public let trimEndMs: Int64?
    public let rotateDegrees: Int?
    public let crop: VideoCrop?
    public let speed: Double

    public init(
        inputURL: URL,
        outputURL: URL,
        trimStartMs: Int64?,
        trimEndMs: Int64?,
        rotateDegrees: Int?,
        crop: VideoCrop?,
        speed: Double
    ) throws {
        let inputURL = inputURL.standardizedFileURL.resolvingSymlinksInPath()
        let outputURL = outputURL.standardizedFileURL.resolvingSymlinksInPath()
        guard inputURL != outputURL,
            FileManager.default.fileExists(atPath: inputURL.path),
            (trimStartMs == nil) == (trimEndMs == nil),
            trimStartMs == nil || (trimStartMs! >= 0 && trimStartMs! < trimEndMs!),
            rotateDegrees == nil || [0, 90, 180, 270].contains(rotateDegrees!),
            speed.isFinite,
            speed > 0
        else {
            throw VideoEditorError.invalidRequest("Invalid video processing request")
        }
        self.inputURL = inputURL
        self.outputURL = outputURL
        self.trimStartMs = trimStartMs
        self.trimEndMs = trimEndMs
        self.rotateDegrees = rotateDegrees
        self.crop = crop
        self.speed = speed
    }
}

public struct VideoEditResult: Equatable, Sendable {
    public let outputURL: URL
    public let isReEncoded: Bool
}

public enum VideoEditorError: LocalizedError {
    case invalidRequest(String)
    case metadataUnavailable(String, Error? = nil)
    case frameExtraction(String, Error? = nil)
    case frameWrite(String, Error? = nil)
    case invalidTimeRange(String)
    case composition(String, Error? = nil)
    case export(String, Error? = nil)

    public var message: String {
        switch self {
        case .invalidRequest(let message),
            .metadataUnavailable(let message, _),
            .frameExtraction(let message, _),
            .frameWrite(let message, _),
            .invalidTimeRange(let message),
            .composition(let message, _),
            .export(let message, _):
            return message
        }
    }

    public var errorDescription: String? { message }

    public var underlyingError: Error? {
        switch self {
        case .metadataUnavailable(_, let error),
            .frameExtraction(_, let error),
            .frameWrite(_, let error),
            .composition(_, let error),
            .export(_, let error):
            return error
        case .invalidRequest, .invalidTimeRange:
            return nil
        }
    }
}

public struct SlideshowMotion: Sendable {
    public let startScale: Double
    public let endScale: Double
    public let startOffset: CGPoint
    public let endOffset: CGPoint

    public init(
        startScale: Double,
        endScale: Double,
        startOffset: CGPoint,
        endOffset: CGPoint
    ) throws {
        let values = [
            startScale, endScale,
            startOffset.x, startOffset.y,
            endOffset.x, endOffset.y,
        ]
        guard values.allSatisfy(\.isFinite), startScale > 0, endScale > 0 else {
            throw VideoEditorError.invalidRequest("Invalid slideshow motion")
        }
        self.startScale = startScale
        self.endScale = endScale
        self.startOffset = startOffset
        self.endOffset = endOffset
    }
}

public enum SlideshowItem: Sendable {
    case photo(url: URL, durationMs: Int64, motion: SlideshowMotion)
    case video(url: URL, isMuted: Bool)

    public var url: URL {
        switch self {
        case .photo(let url, _, _), .video(let url, _):
            return url
        }
    }
}

public struct SlideshowMusic: Sendable {
    public let url: URL
    public let fadeInMs: Int64
    public let fadeOutMs: Int64

    public init(url: URL, fadeInMs: Int64, fadeOutMs: Int64) throws {
        guard fadeInMs >= 0, fadeOutMs >= 0 else {
            throw VideoEditorError.invalidRequest("Invalid slideshow music fades")
        }
        self.url = url.standardizedFileURL.resolvingSymlinksInPath()
        self.fadeInMs = fadeInMs
        self.fadeOutMs = fadeOutMs
    }
}

public struct SlideshowExportRequest: Sendable {
    public let outputURL: URL
    public let width: Int
    public let height: Int
    public let frameRate: Int
    public let crossfadeMs: Int64
    public let items: [SlideshowItem]
    public let music: SlideshowMusic?

    public init(
        outputURL: URL,
        width: Int,
        height: Int,
        frameRate: Int,
        crossfadeMs: Int64,
        items: [SlideshowItem],
        music: SlideshowMusic?
    ) throws {
        let outputURL = outputURL.standardizedFileURL.resolvingSymlinksInPath()
        let inputURLs = items.map { $0.url.standardizedFileURL.resolvingSymlinksInPath() }
        guard !items.isEmpty,
            width > 0, height > 0, width % 2 == 0, height % 2 == 0,
            (1...60).contains(frameRate),
            crossfadeMs >= 0,
            inputURLs.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }),
            !inputURLs.contains(outputURL),
            music.map({ FileManager.default.fileExists(atPath: $0.url.path) && $0.url != outputURL })
                ?? true
        else {
            throw VideoEditorError.invalidRequest("Invalid slideshow export request")
        }
        for item in items {
            if case .photo(_, let durationMs, _) = item,
                durationMs <= 0 || crossfadeMs > durationMs
            {
                throw VideoEditorError.invalidRequest("Photo durations must exceed the crossfade")
            }
        }
        self.outputURL = outputURL
        self.width = width
        self.height = height
        self.frameRate = frameRate
        self.crossfadeMs = crossfadeMs
        self.items = items
        self.music = music
    }
}
