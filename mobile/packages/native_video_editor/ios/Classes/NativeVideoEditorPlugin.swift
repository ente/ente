@preconcurrency import Flutter
import Foundation

@MainActor
public final class NativeVideoEditorPlugin: NSObject, @preconcurrency FlutterPlugin {
    private var isDetached = false
    private var progressEventSink: FlutterEventSink?
    private var frameTasks: [String: Task<Void, Never>] = [:]
    private var frameCancellationResults: [String: FlutterResult] = [:]
    private var exportTask: Task<Void, Never>?
    private var exportCancellationResult: FlutterResult?
    private let metadataReader = VideoMetadataReader()
    private lazy var frameExtractor = VideoFrameExtractor(metadataReader: metadataReader)
    private let videoExporter = VideoExportEngine()

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "native_video_editor",
            binaryMessenger: registrar.messenger()
        )
        let instance = NativeVideoEditorPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
        registrar.publish(instance)

        let progressChannel = FlutterEventChannel(
            name: "native_video_editor/progress",
            binaryMessenger: registrar.messenger()
        )
        progressChannel.setStreamHandler(instance)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard !isDetached else {
            result(flutterError("PLUGIN_DETACHED", message: "Native video editor is detached"))
            return
        }
        switch call.method {
        case "getVideoInfo":
            inspectVideo(call, result: result)
        case "extractFrame":
            extractSingleFrame(call, result: result)
        case "extractTimeline":
            extractTimeline(call, result: result)
        case "cancelFrameExtraction":
            cancelFrameExtraction(call, result: result)
        case "processVideo":
            processVideo(call, result: result)
        case "cancelProcessing":
            cancelProcessing(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func inspectVideo(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
            let videoPath = args["videoPath"] as? String,
            !videoPath.isEmpty
        else {
            result(flutterError("INVALID_ARGS", message: "Invalid arguments"))
            return
        }

        Task { [weak self] in
            guard let self else { return }
            do {
                let info = try await metadataReader.read(
                    from: URL(fileURLWithPath: videoPath)
                )
                guard !isDetached else { return }
                result(info.channelValue)
            } catch {
                guard !isDetached else { return }
                result(flutterError(error, defaultCode: "INFO_ERROR"))
            }
        }
    }

    private func extractSingleFrame(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        guard let args = call.arguments as? [String: Any],
            let outputPath = args["outputPath"] as? String,
            !outputPath.isEmpty,
            let positionMs = int64(args["positionMs"])
        else {
            result(flutterError("INVALID_ARGS", message: "Invalid frame arguments"))
            return
        }
        startFrameExtraction(
            args: args,
            requestID: UUID().uuidString,
            outputPaths: [outputPath],
            positionsMs: [positionMs],
            result: result
        )
    }

    private func extractTimeline(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        guard let args = call.arguments as? [String: Any],
            let requestID = args["requestId"] as? String,
            !requestID.isEmpty,
            let outputPaths = args["outputPaths"] as? [String],
            outputPaths.allSatisfy({ !$0.isEmpty }),
            let positions = args["positionsMs"] as? [NSNumber]
        else {
            result(flutterError("INVALID_ARGS", message: "Invalid timeline arguments"))
            return
        }
        startFrameExtraction(
            args: args,
            requestID: requestID,
            outputPaths: outputPaths,
            positionsMs: positions.map(\.int64Value),
            result: result
        )
    }

    private func startFrameExtraction(
        args: [String: Any],
        requestID: String,
        outputPaths: [String],
        positionsMs: [Int64],
        result: @escaping FlutterResult
    ) {
        guard frameTasks[requestID] == nil else {
            result(
                flutterError(
                    "DUPLICATE_REQUEST",
                    message: "Frame request ID is already active",
                    details: requestID
                ))
            return
        }
        let request: VideoFrameRequest
        do {
            request = try makeFrameRequest(
                args: args,
                outputPaths: outputPaths,
                positionsMs: positionsMs
            )
        } catch {
            result(flutterError(error, defaultCode: "INVALID_ARGS"))
            return
        }

        let task = Task { [weak self] in
            guard let self else { return }
            let value: Any
            do {
                let extraction = try await frameExtractor.extract(request)
                value = extraction.channelValue(outputPaths: outputPaths)
            } catch is CancellationError {
                value = flutterError(
                    "FRAME_CANCELLED",
                    message: "Frame extraction was cancelled",
                    details: requestID
                )
            } catch {
                value = flutterError(error, defaultCode: "FRAME_EXTRACTION_ERROR")
            }
            finishFrameRequest(requestID: requestID, result: result, value: value)
        }
        frameTasks[requestID] = task
    }

    private func cancelFrameExtraction(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        guard let args = call.arguments as? [String: Any],
            let requestID = args["requestId"] as? String
        else {
            result(flutterError("INVALID_ARGS", message: "Missing frame request ID"))
            return
        }
        guard let task = frameTasks[requestID] else {
            result(nil)
            return
        }
        guard frameCancellationResults[requestID] == nil else {
            result(nil)
            return
        }
        frameCancellationResults[requestID] = result
        task.cancel()
    }

    private func finishFrameRequest(
        requestID: String,
        result: @escaping FlutterResult,
        value: Any
    ) {
        guard frameTasks.removeValue(forKey: requestID) != nil else { return }
        let cancellationResult = frameCancellationResults.removeValue(forKey: requestID)
        guard !isDetached else { return }
        result(value)
        cancellationResult?(nil)
    }

    private func processVideo(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        guard exportTask == nil else {
            result(flutterError("CONCURRENT_EXPORT", message: "A video export is already active"))
            return
        }
        guard let args = call.arguments as? [String: Any],
            let outputPath = args["outputPath"] as? String,
            !outputPath.isEmpty
        else {
            result(flutterError("INVALID_ARGS", message: "Invalid arguments"))
            return
        }
        let request: VideoEditRequest
        do {
            request = try makeEditRequest(args: args)
        } catch {
            result(flutterError(error, defaultCode: "INVALID_ARGS"))
            return
        }

        let task = Task { [weak self] in
            guard let self else { return }
            let value: Any
            do {
                let export = try await videoExporter.export(request) { [weak self] progress in
                    Task { @MainActor [weak self] in
                        guard let self, !isDetached else { return }
                        progressEventSink?(progress)
                    }
                }
                value = [
                    "outputPath": outputPath,
                    "isReEncoded": export.isReEncoded,
                ]
            } catch is CancellationError {
                value = flutterError("PROCESS_CANCELLED", message: "Export cancelled")
            } catch {
                value = flutterError(error, defaultCode: "PROCESS_ERROR")
            }
            finishExport(result: result, value: value)
        }
        exportTask = task
    }

    private func cancelProcessing(result: @escaping FlutterResult) {
        guard let exportTask else {
            result(nil)
            return
        }
        guard exportCancellationResult == nil else {
            result(nil)
            return
        }
        exportCancellationResult = result
        exportTask.cancel()
    }

    private func finishExport(result: @escaping FlutterResult, value: Any) {
        guard exportTask != nil else { return }
        exportTask = nil
        let cancellationResult = exportCancellationResult
        exportCancellationResult = nil
        guard !isDetached else { return }
        result(value)
        cancellationResult?(nil)
    }

    private func makeFrameRequest(
        args: [String: Any],
        outputPaths: [String],
        positionsMs: [Int64]
    ) throws -> VideoFrameRequest {
        guard let inputPath = args["inputPath"] as? String,
            !inputPath.isEmpty,
            outputPaths.allSatisfy({ !$0.isEmpty }),
            let maxWidth = int(args["maxWidth"]),
            let maxHeight = int(args["maxHeight"]),
            let quality = int(args["quality"]),
            let policyValue = args["policy"] as? String
        else {
            throw VideoEditorError.invalidRequest("Invalid frame extraction arguments")
        }
        let policy: VideoFramePolicy
        switch policyValue {
        case "precise": policy = .precise
        case "nearestSync": policy = .nearestSync
        default:
            throw VideoEditorError.invalidRequest("Invalid frame policy")
        }
        return try VideoFrameRequest(
            inputURL: URL(fileURLWithPath: inputPath),
            outputURLs: outputPaths.map { URL(fileURLWithPath: $0) },
            positionsMs: positionsMs,
            maxWidth: maxWidth,
            maxHeight: maxHeight,
            quality: quality,
            policy: policy
        )
    }

    private func makeEditRequest(args: [String: Any]) throws -> VideoEditRequest {
        guard let inputPath = args["inputPath"] as? String,
            !inputPath.isEmpty,
            let outputPath = args["outputPath"] as? String,
            !outputPath.isEmpty
        else {
            throw VideoEditorError.invalidRequest("Invalid video paths")
        }
        let cropValues = [
            int(args["cropX"]),
            int(args["cropY"]),
            int(args["cropWidth"]),
            int(args["cropHeight"]),
        ]
        guard cropValues.allSatisfy({ $0 == nil }) || cropValues.allSatisfy({ $0 != nil }) else {
            throw VideoEditorError.invalidRequest("Crop values must be provided together")
        }
        let crop =
            cropValues[0] == nil
            ? nil
            : try VideoCrop(
                x: cropValues[0]!,
                y: cropValues[1]!,
                width: cropValues[2]!,
                height: cropValues[3]!
            )
        return try VideoEditRequest(
            inputURL: URL(fileURLWithPath: inputPath),
            outputURL: URL(fileURLWithPath: outputPath),
            trimStartMs: int64(args["trimStartMs"]),
            trimEndMs: int64(args["trimEndMs"]),
            rotateDegrees: int(args["rotateDegrees"]),
            crop: crop,
            speed: double(args["speed"]) ?? 1
        )
    }

    private func int(_ value: Any?) -> Int? {
        (value as? NSNumber)?.intValue
    }

    private func int64(_ value: Any?) -> Int64? {
        (value as? NSNumber)?.int64Value
    }

    private func double(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }

    private func flutterError(
        _ error: Error,
        defaultCode: String
    ) -> FlutterError {
        guard let videoError = error as? VideoEditorError else {
            return flutterError(
                defaultCode,
                message: error.localizedDescription,
                details: String(describing: error)
            )
        }
        let code: String
        switch videoError {
        case .invalidRequest: code = "INVALID_ARGS"
        case .metadataUnavailable: code = defaultCode
        case .frameExtraction: code = "FRAME_EXTRACTION_ERROR"
        case .frameWrite: code = "FRAME_WRITE_ERROR"
        case .invalidTimeRange: code = "INVALID_TIME_RANGE"
        case .composition: code = "COMPOSITION_ERROR"
        case .export: code = defaultCode
        }
        return flutterError(
            code,
            message: videoError.message,
            details: videoError.underlyingError.map(String.init(describing:))
        )
    }

    private func flutterError(
        _ code: String,
        message: String,
        details: Any? = nil
    ) -> FlutterError {
        FlutterError(code: code, message: message, details: details)
    }

    public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
        guard !isDetached else { return }
        isDetached = true
        progressEventSink = nil
        frameTasks.values.forEach { $0.cancel() }
        frameTasks.removeAll()
        frameCancellationResults.removeAll()
        exportTask?.cancel()
        exportTask = nil
        exportCancellationResult = nil
    }
}

private extension VideoMetadata {
    var channelValue: [String: Any] {
        var value: [String: Any] = [
            "duration": durationMs,
            "width": width,
            "height": height,
            "displayWidth": displayWidth,
            "displayHeight": displayHeight,
            "rotation": rotationDegrees,
        ]
        if let bitrate { value["bitrate"] = bitrate }
        if let frameRate { value["frameRate"] = frameRate }
        return value
    }
}

private extension VideoFrameExtractionResult {
    func channelValue(outputPaths: [String]) -> [String: Any] {
        [
            "videoInfo": videoInfo.channelValue,
            "frames": zip(frames, outputPaths).map { frame, outputPath in
                [
                    "outputPath": outputPath,
                    "width": frame.width,
                    "height": frame.height,
                ] as [String: Any]
            },
        ]
    }
}

extension NativeVideoEditorPlugin: @preconcurrency FlutterStreamHandler {
    public func onListen(
        withArguments arguments: Any?,
        eventSink events: @escaping FlutterEventSink
    ) -> FlutterError? {
        if !isDetached { progressEventSink = events }
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        progressEventSink = nil
        return nil
    }
}
