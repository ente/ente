import Flutter
import Foundation
import UIKit
import UniformTypeIdentifiers

public class DirUtilsPlugin: NSObject, FlutterPlugin {
    private var pendingResult: FlutterResult?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "io.ente.scoped_dir_access",
            binaryMessenger: registrar.messenger()
        )
        let instance = DirUtilsPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "pickDirectory":
            handlePickDirectory(result: result)
        case "startAccess":
            handleStartAccess(call: call, result: result)
        case "stopAccess":
            handleStopAccess(call: call, result: result)
        case "writeFile":
            handleWriteFile(call: call, result: result)
        case "readFile":
            handleReadFile(call: call, result: result)
        case "deleteFile":
            handleDeleteFile(call: call, result: result)
        case "listFiles":
            handleListFiles(call: call, result: result)
        case "exists":
            handleExists(call: call, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func handlePickDirectory(result: @escaping FlutterResult) {
        guard let viewController = UIApplication.shared.windows.first?.rootViewController else {
            result(FlutterError(code: "NO_VIEW_CONTROLLER", message: "Could not find root view controller", details: nil))
            return
        }

        pendingResult = result

        let picker: UIDocumentPickerViewController
        if #available(iOS 14.0, *) {
            picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        } else {
            picker = UIDocumentPickerViewController(documentTypes: ["public.folder"], in: .open)
        }
        picker.delegate = self
        picker.allowsMultipleSelection = false

        viewController.present(picker, animated: true)
    }

    private func handleStartAccess(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let base64Bookmark = args["bookmark"] as? String,
              let bookmarkData = Data(base64Encoded: base64Bookmark) else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing or invalid 'bookmark' argument", details: nil))
            return
        }

        do {
            var isStale = false
            // On iOS, security scope is implicit in the bookmark data itself
            // (unlike macOS which requires .withSecurityScope option)
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            let success = url.startAccessingSecurityScopedResource()
            result([
                "success": success,
                "path": url.path,
                "isStale": isStale
            ])
        } catch {
            result(FlutterError(
                code: "ACCESS_ERROR",
                message: "Failed to start access: \(error.localizedDescription)",
                details: nil
            ))
        }
    }

    private func handleStopAccess(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let base64Bookmark = args["bookmark"] as? String,
              let bookmarkData = Data(base64Encoded: base64Bookmark) else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing or invalid 'bookmark' argument", details: nil))
            return
        }

        do {
            var isStale = false
            // On iOS, security scope is implicit in the bookmark data itself
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            url.stopAccessingSecurityScopedResource()
            result(true)
        } catch {
            result(FlutterError(
                code: "ACCESS_ERROR",
                message: "Failed to stop access: \(error.localizedDescription)",
                details: nil
            ))
        }
    }

    private func handleWriteFile(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let path = args["path"] as? String,
              let content = args["content"] as? FlutterStandardTypedData else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing 'path' or 'content' argument", details: nil))
            return
        }

        let url = URL(fileURLWithPath: path)

        do {
            try content.data.write(to: url)
            result(true)
        } catch {
            result(FlutterError(
                code: "WRITE_ERROR",
                message: "Failed to write file: \(error.localizedDescription)",
                details: nil
            ))
        }
    }

    private func handleReadFile(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let path = args["path"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing 'path' argument", details: nil))
            return
        }

        let url = URL(fileURLWithPath: path)

        do {
            let data = try Data(contentsOf: url)
            result(FlutterStandardTypedData(bytes: data))
        } catch {
            result(FlutterError(
                code: "READ_ERROR",
                message: "Failed to read file: \(error.localizedDescription)",
                details: nil
            ))
        }
    }

    private func handleDeleteFile(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let path = args["path"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing 'path' argument", details: nil))
            return
        }

        let url = URL(fileURLWithPath: path)

        do {
            try FileManager.default.removeItem(at: url)
            result(true)
        } catch {
            result(FlutterError(
                code: "DELETE_ERROR",
                message: "Failed to delete: \(error.localizedDescription)",
                details: nil
            ))
        }
    }

    private func handleListFiles(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let path = args["path"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing 'path' argument", details: nil))
            return
        }

        let url = URL(fileURLWithPath: path)

        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )

            var files: [[String: Any]] = []
            for fileURL in contents {
                let resourceValues = try fileURL.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey])
                let isDirectory = resourceValues.isDirectory ?? false
                let modDate = resourceValues.contentModificationDate ?? Date()

                files.append([
                    "name": fileURL.lastPathComponent,
                    "path": fileURL.path,
                    "isDirectory": isDirectory,
                    "lastModified": Int64(modDate.timeIntervalSince1970 * 1000)
                ])
            }

            result(files)
        } catch {
            result(FlutterError(
                code: "LIST_ERROR",
                message: "Failed to list files: \(error.localizedDescription)",
                details: nil
            ))
        }
    }

    private func handleExists(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let path = args["path"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing 'path' argument", details: nil))
            return
        }

        let exists = FileManager.default.fileExists(atPath: path)
        result(exists)
    }
}

extension DirUtilsPlugin: UIDocumentPickerDelegate {
    public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let result = pendingResult else { return }
        pendingResult = nil

        guard let url = urls.first else {
            result(FlutterError(code: "NO_SELECTION", message: "No directory selected", details: nil))
            return
        }

        let didStartAccessing = url.startAccessingSecurityScopedResource()

        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            // Create bookmark while we have security-scoped access
            let bookmarkData = try url.bookmarkData(
                options: .minimalBookmark,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )

            let base64Bookmark = bookmarkData.base64EncodedString()

            result([
                "path": url.path,
                "bookmark": base64Bookmark
            ])
        } catch {
            NSLog("DirUtilsPlugin: Failed to create bookmark: \(error)")
            result(FlutterError(
                code: "BOOKMARK_ERROR",
                message: "Failed to create bookmark: \(error.localizedDescription)",
                details: nil
            ))
        }
    }

    public func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        guard let result = pendingResult else { return }
        pendingResult = nil
        result(nil) // User cancelled
    }
}
