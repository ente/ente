import Cocoa
import FlutterMacOS
import Vision

public class EnteQrPlugin: NSObject, FlutterPlugin {
  private static let detectionQueue = DispatchQueue(label: "io.ente.qr.detection", qos: .userInitiated)

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "ente_qr", binaryMessenger: registrar.messenger)
    let instance = EnteQrPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getPlatformVersion":
      result("macOS " + ProcessInfo.processInfo.operatingSystemVersionString)
    case "scanQrFromImage":
      guard let imagePath = imagePath(from: call.arguments) else {
        result([
          "success": false,
          "error": "Image path is required",
        ])
        return
      }

      scanQrCode(from: imagePath, result: result)
    case "scanAllQrFromImage":
      guard let imagePath = imagePath(from: call.arguments) else {
        result([
          "success": false,
          "error": "Image path is required",
        ])
        return
      }

      scanAllQrCodes(from: imagePath, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func imagePath(from arguments: Any?) -> String? {
    guard let args = arguments as? [String: Any] else {
      return nil
    }
    return args["imagePath"] as? String
  }

  private func scanQrCode(from imagePath: String, result: @escaping FlutterResult) {
    detectQrCodes(from: imagePath) { detectionResult in
      switch detectionResult {
      case .success(let detections):
        guard let content = detections.first?["content"] as? String else {
          result([
            "success": false,
            "error": "No QR code found in image",
          ])
          return
        }
        result([
          "success": true,
          "content": content,
        ])
      case .failure(let error):
        result([
          "success": false,
          "error": error.localizedDescription,
        ])
      }
    }
  }

  private func scanAllQrCodes(from imagePath: String, result: @escaping FlutterResult) {
    detectQrCodes(from: imagePath) { detectionResult in
      switch detectionResult {
      case .success(let detections):
        result([
          "success": true,
          "detections": detections,
        ])
      case .failure(let error):
        result([
          "success": false,
          "error": error.localizedDescription,
        ])
      }
    }
  }

  private func detectQrCodes(
    from imagePath: String,
    completion: @escaping (Result<[[String: Any]], Error>) -> Void
  ) {
    EnteQrPlugin.detectionQueue.async {
      do {
        let cgImage = try self.loadCgImage(from: imagePath)
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        let observations = request.results ?? []
        let detections = observations.compactMap { observation -> [String: Any]? in
          guard observation.symbology == .qr,
                let payload = observation.payloadStringValue,
                !payload.isEmpty else {
            return nil
          }

          let box = observation.boundingBox
          return [
            "content": payload,
            "x": Double(box.minX),
            "y": Double(1.0 - box.maxY),
            "width": Double(box.width),
            "height": Double(box.height),
          ]
        }

        DispatchQueue.main.async {
          if detections.isEmpty {
            completion(.failure(EnteQrError.noQrCodeFound))
          } else {
            completion(.success(detections))
          }
        }
      } catch {
        DispatchQueue.main.async {
          completion(.failure(error))
        }
      }
    }
  }

  private func loadCgImage(from imagePath: String) throws -> CGImage {
    guard let image = NSImage(contentsOfFile: imagePath) else {
      throw EnteQrError.unableToLoadImage
    }

    var proposedRect = NSRect(origin: .zero, size: image.size)
    guard let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
      throw EnteQrError.unableToCreateCgImage
    }
    return cgImage
  }
}

private enum EnteQrError: LocalizedError {
  case unableToLoadImage
  case unableToCreateCgImage
  case noQrCodeFound

  var errorDescription: String? {
    switch self {
    case .unableToLoadImage:
      return "Unable to load image from path"
    case .unableToCreateCgImage:
      return "Unable to create CGImage from image"
    case .noQrCodeFound:
      return "No QR code found in image"
    }
  }
}
