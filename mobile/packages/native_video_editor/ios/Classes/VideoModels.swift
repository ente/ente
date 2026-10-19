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
