import FlutterMacOS
import Foundation

public class DirUtilsPlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "io.ente.scoped_dir_access",
            binaryMessenger: registrar.messenger
        )
        let instance = DirUtilsPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "createBookmarkFromPath":
            handleCreateBookmarkFromPath(call: call, result: result)
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

    // Must run while picker access is still active.
    private func handleCreateBookmarkFromPath(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let path = args["path"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing 'path' argument", details: nil))
            return
        }

        let url = URL(fileURLWithPath: path)

        do {
            // On macOS, we must use .withSecurityScope for app-scoped bookmarks
            let bookmarkData = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )

            let base64Bookmark = bookmarkData.base64EncodedString()

            result([
                "path": url.path,
                "bookmark": base64Bookmark
            ])
        } catch {
            NSLog("DirUtilsPlugin (macOS): Failed to create bookmark: \(error)")
            result(FlutterError(
                code: "BOOKMARK_ERROR",
                message: "Failed to create bookmark: \(error.localizedDescription)",
                details: nil
            ))
        }
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
            // On macOS, we must use .withSecurityScope when resolving
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            // Critical: must call startAccessingSecurityScopedResource on the resolved URL
            let success = url.startAccessingSecurityScopedResource()

            result([
                "success": success,
                "path": url.path,
                "isStale": isStale
            ])
        } catch {
            NSLog("DirUtilsPlugin (macOS): Failed to start access: \(error)")
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
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            url.stopAccessingSecurityScopedResource()
            result(true)
        } catch {
            NSLog("DirUtilsPlugin (macOS): Failed to stop access: \(error)")
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
