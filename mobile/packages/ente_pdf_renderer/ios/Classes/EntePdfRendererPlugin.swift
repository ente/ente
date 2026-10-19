import Flutter
import PDFKit
import UIKit

public class EntePdfRendererPlugin: NSObject, FlutterPlugin {
  private struct PdfError: Error {
    let code: String
    let message: String
  }

  private var documents: [Int: PDFDocument] = [:]
  private var nextId = 1
  private let queue = DispatchQueue(label: "io.ente.pdf_renderer", qos: .userInitiated)

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "io.ente/pdf_renderer", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(EntePdfRendererPlugin(), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any] ?? [:]
    queue.async {
      do {
        let reply: Any?
        switch call.method {
        case "open":
          guard let path = arguments["path"] as? String else {
            throw PdfError(code: "invalid", message: "Missing path")
          }
          reply = try self.open(path: path, password: arguments["password"] as? String)
        case "render":
          guard let id = arguments["id"] as? Int, let page = arguments["page"] as? Int,
                let width = arguments["width"] as? Int, let height = arguments["height"] as? Int else {
            throw PdfError(code: "invalid", message: "Missing render arguments")
          }
          reply = try self.render(id: id, page: page, width: width, height: height)
        case "close":
          if let id = arguments["id"] as? Int {
            self.documents.removeValue(forKey: id)
          }
          reply = nil
        default:
          DispatchQueue.main.async { result(FlutterMethodNotImplemented) }
          return
        }
        DispatchQueue.main.async { result(reply) }
      } catch let error as PdfError {
        DispatchQueue.main.async {
          result(FlutterError(code: error.code, message: error.message, details: nil))
        }
      } catch {
        DispatchQueue.main.async { result(FlutterError(code: "invalid", message: "\(error)", details: nil)) }
      }
    }
  }

  private func rotatedSize(_ page: PDFPage) -> CGSize {
    let bounds = page.bounds(for: .cropBox)
    return page.rotation % 180 == 0 ? bounds.size : CGSize(width: bounds.height, height: bounds.width)
  }

  private func open(path: String, password: String?) throws -> [String: Any] {
    guard let document = PDFDocument(url: URL(fileURLWithPath: path)) else {
      throw PdfError(code: "invalid", message: "Not a readable PDF")
    }
    if document.isLocked {
      guard let password else {
        throw PdfError(code: "password_required", message: "PDF needs a password")
      }
      guard document.unlock(withPassword: password) else {
        throw PdfError(code: "password_incorrect", message: "Wrong password")
      }
    }
    var widths: [Double] = []
    var heights: [Double] = []
    for index in 0..<document.pageCount {
      guard let page = document.page(at: index) else {
        throw PdfError(code: "invalid", message: "Page \(index + 1) unreadable")
      }
      let size = rotatedSize(page)
      widths.append(Double(size.width))
      heights.append(Double(size.height))
    }
    let id = nextId
    nextId += 1
    documents[id] = document
    return ["id": id, "widths": widths, "heights": heights]
  }

  private func render(id: Int, page: Int, width: Int, height: Int) throws -> FlutterStandardTypedData {
    guard let document = documents[id], let pdfPage = document.page(at: page - 1) else {
      throw PdfError(code: "invalid", message: "Document \(id) is closed")
    }
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    let size = CGSize(width: width, height: height)
    let pageSize = rotatedSize(pdfPage)
    let data = UIGraphicsImageRenderer(size: size, format: format).pngData { context in
      UIColor.white.setFill()
      context.fill(CGRect(origin: .zero, size: size))
      let graphics = context.cgContext
      graphics.translateBy(x: 0, y: size.height)
      graphics.scaleBy(x: size.width / pageSize.width, y: -size.height / pageSize.height)
      pdfPage.draw(with: .cropBox, to: graphics)
    }
    return FlutterStandardTypedData(bytes: data)
  }
}
