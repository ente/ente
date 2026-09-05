@preconcurrency import Flutter
import Foundation

@MainActor
final class TextRecognitionChannelAdapter {
    private let channel: FlutterMethodChannel
    private let recognizer = TextRecognizer()
    private var isAttached = true

    init(registrar: FlutterPluginRegistrar) {
        channel = FlutterMethodChannel(
            name: Self.channelName,
            binaryMessenger: registrar.messenger()
        )
        channel.setMethodCallHandler { [weak self] call, result in
            self?.handle(call, result: result)
        }
    }

    func detach() {
        guard isAttached else { return }
        isAttached = false
        recognizer.cancelAll()
        channel.setMethodCallHandler(nil)
    }

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard isAttached else {
            result(TextRecognitionError.cancelled.flutterError)
            return
        }
        switch call.method {
        case "textRecognition.detectText":
            handleDetectText(call, result: result)
        case "textRecognition.detectTextRegions":
            handleDetectTextRegions(call, result: result)
        case "textRecognition.cancelRequest":
            handleCancelRequest(call, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func handleDetectText(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let arguments = call.arguments as? [String: Any],
            let imagePath = arguments["imagePath"] as? String
        else {
            result(invalidArgument("imagePath is required"))
            return
        }
        recognizer.recognizeText(
            imagePath: imagePath,
            includeAllConfidenceScores: arguments["includeAllConfidenceScores"] as? Bool ?? false,
            requestId: arguments["requestId"] as? String
        ) { outcome in
            deliver(outcome, to: result, channelValue: \.channelValue)
        }
    }

    private func handleDetectTextRegions(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let arguments = call.arguments as? [String: Any],
            let imagePath = arguments["imagePath"] as? String
        else {
            result(invalidArgument("imagePath is required"))
            return
        }
        recognizer.detectTextRegions(
            imagePath: imagePath,
            requestId: arguments["requestId"] as? String
        ) { outcome in
            deliver(outcome, to: result, channelValue: \.channelValue)
        }
    }

    private func handleCancelRequest(_ call: FlutterMethodCall, result: FlutterResult) {
        guard let arguments = call.arguments as? [String: Any],
            let requestId = arguments["requestId"] as? String, !requestId.isEmpty
        else {
            result(invalidArgument("requestId is required"))
            return
        }
        recognizer.cancel(requestId: requestId)
        result(nil)
    }

    private static let channelName = "io.ente.photos.vision/text_recognition"
}

private func invalidArgument(_ message: String) -> FlutterError {
    FlutterError(code: "INVALID_ARGUMENT", message: message, details: nil)
}

private func deliver<Value: Sendable>(
    _ outcome: Result<Value, TextRecognitionError>,
    to result: @escaping FlutterResult,
    channelValue: @escaping @Sendable (Value) -> [String: Any]
) {
    DispatchQueue.main.async {
        switch outcome {
        case .success(let value):
            result(channelValue(value))
        case .failure(let error):
            result(error.flutterError)
        }
    }
}

extension TextRecognitionError {
    fileprivate var flutterError: FlutterError {
        switch self {
        case .imageNotFound:
            FlutterError(code: "IMAGE_NOT_FOUND", message: "Image file does not exist", details: nil)
        case .imageUndecodable:
            FlutterError(code: "IMAGE_DECODE_ERROR", message: "Failed to load image from path", details: nil)
        case .imageBitmapUnavailable:
            FlutterError(code: "IMAGE_DECODE_ERROR", message: "Failed to get CGImage", details: nil)
        case .cancelled:
            FlutterError(code: "CANCELLED", message: "OCR request was cancelled", details: nil)
        case .detectionFailed(let error):
            FlutterError(
                code: "DETECTION_ERROR",
                message: "Failed to detect text regions",
                details: error.localizedDescription
            )
        case .recognitionFailed(let error):
            FlutterError(
                code: "RECOGNITION_ERROR",
                message: "Text recognition failed",
                details: error.localizedDescription
            )
        }
    }
}

extension TextRecognitionResult {
    fileprivate var channelValue: [String: Any] {
        [
            "blocks": blocks.map(\.channelValue),
            "imageWidth": imageWidth,
            "imageHeight": imageHeight,
        ]
    }
}

extension RecognizedTextBlock {
    fileprivate var channelValue: [String: Any] {
        [
            "text": text,
            "confidence": Double(confidence),
            "points": points.channelValue,
            "characters": characters.map(\.channelValue),
        ]
    }
}

extension RecognizedCharacter {
    fileprivate var channelValue: [String: Any] {
        [
            "text": text,
            "confidence": Double(confidence),
            "points": points.channelValue,
        ]
    }
}

extension TextRegionsResult {
    fileprivate var channelValue: [String: Any] {
        [
            "regions": regions.map(\.channelValue),
            "imageWidth": imageWidth,
            "imageHeight": imageHeight,
        ]
    }
}

extension TextRegion {
    fileprivate var channelValue: [String: Any] {
        [
            "confidence": Double(confidence),
            "points": points.channelValue,
        ]
    }
}

extension [CGPoint] {
    fileprivate var channelValue: [[String: Double]] {
        map { ["x": Double($0.x), "y": Double($0.y)] }
    }
}
