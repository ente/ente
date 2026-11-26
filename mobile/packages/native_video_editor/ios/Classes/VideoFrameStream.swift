import Accelerate
import AVFoundation

public struct VideoFrameStreamRequest: Sendable {
    public let outputURL: URL
    public let width: Int
    public let height: Int
    public let frameRate: Int
    public let bitrate: Int

    public init(outputURL: URL, width: Int, height: Int, frameRate: Int, bitrate: Int) throws {
        guard width > 0, height > 0, width % 2 == 0, height % 2 == 0,
            (1...60).contains(frameRate),
            bitrate > 0
        else {
            throw VideoEditorError.invalidRequest("Invalid frame stream settings")
        }
        self.outputURL = outputURL.standardizedFileURL
        self.width = width
        self.height = height
        self.frameRate = frameRate
        self.bitrate = bitrate
    }
}

public final class VideoFrameStream: VideoWriterFrameSource, @unchecked Sendable {
    private static let queueLimit = 2
    private static let extendedRangeBlack = 384
    private static let extendedRangeSpan = 510.0
    private static let extendedRangePadding: UInt16 = 6
    private static let extendedRangeLevels: [UInt8] = (0..<1024).map { level in
        let scale = Float(1.0 / extendedRangeSpan)
        let value = min(max(Float(level - extendedRangeBlack) * scale, 0), 1)
        return UInt8((value * 255).rounded(.toNearestOrEven))
    }

    public let request: VideoFrameStreamRequest
    private let pool: CVPixelBufferPool
    private let session: VideoWriterSession
    private let condition = NSCondition()
    private var queued: [VideoWriterFrame] = []
    private var failure: Error?
    private var isClosed = false
    private var frameCount: Int64 = 0
    private var task: Task<Void, Error>?

    public init(request: VideoFrameStreamRequest) throws {
        self.request = request
        var pool: CVPixelBufferPool?
        let status = CVPixelBufferPoolCreate(
            kCFAllocatorDefault,
            [kCVPixelBufferPoolMinimumBufferCountKey: Self.queueLimit + 2] as CFDictionary,
            [
                kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey: request.width,
                kCVPixelBufferHeightKey: request.height,
                kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
            ] as CFDictionary,
            &pool
        )
        guard status == kCVReturnSuccess, let pool else {
            throw VideoEditorError.export("Failed to allocate video frames")
        }
        self.pool = pool
        session = try VideoWriterSession(
            settings: VideoWriterSettings(
                outputURL: request.outputURL,
                width: request.width,
                height: request.height,
                frameRate: request.frameRate,
                bitrate: request.bitrate,
                colorProperties: [
                    AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                    AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                    AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
                ],
                optimizesForNetworkUse: false
            ),
            onProgress: { _ in }
        )
    }

    public func start() async throws {
        try throwIfStopped()
        try? FileManager.default.removeItem(at: request.outputURL)
        try await withCheckedThrowingContinuation { (started: CheckedContinuation<Void, Error>) in
            task = Task { [self] in
                var pendingStart: CheckedContinuation<Void, Error>? = started
                do {
                    try await session.run(
                        frames: { _ in
                            pendingStart?.resume()
                            pendingStart = nil
                            return self
                        },
                        audio: { nil }
                    )
                } catch {
                    fail(error)
                    pendingStart?.resume(throwing: error)
                    throw error
                }
            }
        }
    }

    public func append(rgba: Data) throws {
        try throwIfStopped()
        let buffer = try makeBuffer(rgba)
        condition.lock()
        defer { condition.unlock() }
        while queued.count >= Self.queueLimit, failure == nil, !isClosed {
            condition.wait()
        }
        if let failure { throw failure }
        guard !isClosed else {
            throw VideoEditorError.export("The video frame stream is closed")
        }
        queued.append(
            VideoWriterFrame(
                buffer: buffer,
                time: CMTime(value: frameCount, timescale: CMTimeScale(request.frameRate))
            )
        )
        frameCount += 1
        condition.broadcast()
    }

    public func finish() async throws -> URL {
        guard close() else {
            await cancel()
            throw VideoEditorError.export("The video frame stream has no frames")
        }
        try await task?.value
        return request.outputURL
    }

    public func cancel() async {
        fail(CancellationError())
        task?.cancel()
        _ = await task?.result
        try? FileManager.default.removeItem(at: request.outputURL)
    }

    func next() throws -> VideoWriterFrame? {
        condition.lock()
        defer { condition.unlock() }
        while queued.isEmpty, failure == nil, !isClosed {
            condition.wait()
        }
        if let failure { throw failure }
        guard !queued.isEmpty else { return nil }
        let frame = queued.removeFirst()
        condition.broadcast()
        return frame
    }

    func takeProgressUpdate() -> Double? { nil }

    private func close() -> Bool {
        condition.lock()
        defer { condition.unlock() }
        isClosed = true
        condition.broadcast()
        return frameCount > 0
    }

    private func fail(_ error: Error) {
        condition.lock()
        if failure == nil { failure = error }
        condition.broadcast()
        condition.unlock()
    }

    private func throwIfStopped() throws {
        condition.lock()
        defer { condition.unlock() }
        if let failure { throw failure }
    }

    private func makeBuffer(_ rgba: Data) throws -> CVPixelBuffer {
        let width = request.width
        let height = request.height
        let extendedRange = rgba.count == width * height * 8
        guard rgba.count == width * height * 4 || extendedRange else {
            throw VideoEditorError.invalidRequest("Video frame has the wrong size")
        }
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &buffer)
        guard status == kCVReturnSuccess, let buffer else {
            throw VideoEditorError.export("Failed to allocate a video frame")
        }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        if extendedRange {
            copyExtendedRange(rgba, into: buffer)
            return buffer
        }
        let error = rgba.withUnsafeBytes { bytes -> vImage_Error in
            var source = vImage_Buffer(
                data: UnsafeMutableRawPointer(mutating: bytes.baseAddress),
                height: vImagePixelCount(height),
                width: vImagePixelCount(width),
                rowBytes: width * 4
            )
            var destination = vImage_Buffer(
                data: CVPixelBufferGetBaseAddress(buffer),
                height: vImagePixelCount(height),
                width: vImagePixelCount(width),
                rowBytes: CVPixelBufferGetBytesPerRow(buffer)
            )
            return vImagePermuteChannels_ARGB8888(
                &source, &destination, [2, 1, 0, 3], vImage_Flags(kvImageNoFlags))
        }
        guard error == kvImageNoError else {
            throw VideoEditorError.export("Failed to convert a video frame")
        }
        return buffer
    }

    private func copyExtendedRange(_ bgra: Data, into buffer: CVPixelBuffer) {
        guard let destination = CVPixelBufferGetBaseAddress(buffer) else { return }
        let components = request.width * 4
        let destinationStride = CVPixelBufferGetBytesPerRow(buffer)
        Self.extendedRangeLevels.withUnsafeBufferPointer { levels in
            bgra.withUnsafeBytes { bytes in
                guard let source = bytes.baseAddress else { return }
                for row in 0..<request.height {
                    let from = source + row * components * 2
                    let to = (destination + row * destinationStride)
                        .assumingMemoryBound(to: UInt8.self)
                    for index in 0..<components {
                        let word = (from + index * 2).loadUnaligned(as: UInt16.self)
                        to[index] = levels[Int(word >> Self.extendedRangePadding)]
                    }
                }
            }
        }
    }
}
