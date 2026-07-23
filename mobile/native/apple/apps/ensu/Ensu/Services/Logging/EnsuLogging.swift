import Foundation
import UIKit
#if canImport(ZIPFoundation)
import ZIPFoundation
#endif

enum EnsuLogLevel: String {
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"
}

struct EnsuLogEntry: Identifiable, Hashable {
    let id = UUID()
    let timestamp: Date
    let level: EnsuLogLevel
    let tag: String
    let message: String
    let details: String?
}

final class EnsuLogging {
    static let shared = EnsuLogging()

    private let queue = DispatchQueue(label: "io.ente.ensu.logging")

    private let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private let lineFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    private var isStarted = false
    private(set) var logsDirectory: URL!

    private let maxLogFiles: Int

    private init(maxLogFiles: Int = 5) {
        self.maxLogFiles = maxLogFiles
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true

        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let base = support ?? FileManager.default.temporaryDirectory
        logsDirectory = base.appendingPathComponent("logs", isDirectory: true)

        queue.async {
            do {
                try FileManager.default.createDirectory(at: self.logsDirectory, withIntermediateDirectories: true)
                self.pruneOldLogFiles()
            } catch {
                // Best-effort: fallback to temp.
                self.logsDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("logs", isDirectory: true)
                try? FileManager.default.createDirectory(at: self.logsDirectory, withIntermediateDirectories: true)
            }

            let launchMessage = self.buildAppLaunchMessage()
            self.log(level: .info, tag: "App", message: launchMessage)
        }
    }

    func logger(_ tag: String) -> EnsuLogger {
        EnsuLogger(tag: tag)
    }

    func log(level: EnsuLogLevel, tag: String, message: String, details: String? = nil, error: Error? = nil) {
        start()

        let safeMessage = EnsuLogSanitizer.sanitize(message) ?? ""
        let safeDetails = EnsuLogSanitizer.sanitize(combineDetails(details: details, error: error))

        let entry = EnsuLogEntry(
            timestamp: Date(),
            level: level,
            tag: tag,
            message: safeMessage,
            details: safeDetails
        )

        queue.async {
            let line = self.formatLine(entry)
            self.appendToFile(line)
        }
    }

    func todayLogFileURL() -> URL {
        start()
        let name = "\(dayFormatter.string(from: Date())).txt"
        return logsDirectory.appendingPathComponent(name)
    }

    func listLogFiles() -> [URL] {
        start()
        let urls = (try? FileManager.default.contentsOfDirectory(at: logsDirectory, includingPropertiesForKeys: nil)) ?? []
        return urls
            .filter { $0.pathExtension.lowercased() == "txt" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func readLogText(fileURL: URL? = nil) -> String {
        start()
        let url = fileURL ?? todayLogFileURL()
        return queue.sync {
            (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        }
    }

    func createLogsArchive() throws -> URL {
        start()
        let name = "ensu-logs-\(dayFormatter.string(from: Date()))-\(Int(Date().timeIntervalSince1970)).zip"
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: dest.path) {
            try? FileManager.default.removeItem(at: dest)
        }

        #if canImport(ZIPFoundation)
        if #available(iOS 16.0, macOS 13.0, *) {
            try FileManager.default.zipItem(at: logsDirectory, to: dest, shouldKeepParent: true)
            return dest
        }
        #endif

        // Fallback: concatenate logs into a single text file.
        let fallback = dest.deletingPathExtension().appendingPathExtension("txt")
        var combined = ""
        for file in listLogFiles() {
            combined += "\n===== \(file.lastPathComponent) =====\n"
            combined += readLogText(fileURL: file)
        }
        try combined.write(to: fallback, atomically: true, encoding: .utf8)
        return fallback
    }

    private func appendToFile(_ text: String) {
        let url = todayLogFileURL()
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }

        do {
            let handle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd()
            if let data = text.data(using: .utf8) {
                try handle.write(contentsOf: data)
            }
            try handle.close()
        } catch {
            // Best-effort: ignore.
        }
    }

    private func pruneOldLogFiles() {
        let files = listLogFiles()
        guard files.count > maxLogFiles else { return }
        let toDelete = files.prefix(files.count - maxLogFiles)
        for file in toDelete {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private func formatLine(_ entry: EnsuLogEntry) -> String {
        let ts = lineFormatter.string(from: entry.timestamp)
        var out = "[\(entry.tag)][\(entry.level.rawValue)] [\(ts)] \(entry.message)\n"
        if let details = entry.details, !details.isEmpty {
            for line in details.split(separator: "\n", omittingEmptySubsequences: false) {
                out += "\(line)\n"
            }
        }
        return out
    }

    private func combineDetails(details: String?, error: Error?) -> String? {
        var parts: [String] = []
        if let details, !details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(details)
        }
        if let error {
            parts.append("type: \(String(describing: type(of: error)))")
            parts.append("error: \(error)")
            parts.append("trace: \(Thread.callStackSymbols.joined(separator: "\n"))")
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }

    private func buildAppLaunchMessage() -> String {
        var parts: [String] = ["App launched"]

        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            if let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                parts.append("app=\(version)+\(build)")
            } else {
                parts.append("app=\(version)")
            }
        }

        parts.append("device=\(UIDevice.current.model)")

        parts.append("os=\(ProcessInfo.processInfo.operatingSystemVersionString)")
        return parts.joined(separator: " ")
    }
}

struct EnsuLogger {
    let tag: String

    func info(_ message: String, details: String? = nil) {
        EnsuLogging.shared.log(level: .info, tag: tag, message: message, details: details)
    }

    func warning(_ message: String, details: String? = nil) {
        EnsuLogging.shared.log(level: .warning, tag: tag, message: message, details: details)
    }

    func error(_ message: String, _ error: Error? = nil, details: String? = nil) {
        EnsuLogging.shared.log(level: .error, tag: tag, message: message, details: details, error: error)
    }
}

private enum EnsuLogSanitizer {
    private static let emailPattern = "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}"
    private static let bearerPattern = "(?i)bearer\\s+[A-Za-z0-9._-]+"
    private static let keyValuePattern = "(?i)(token|authToken|accessToken|refreshToken|authorization|password|otp|secret|secretKey|masterKey|encryptedToken|srpA|srpB|srpM1|srpM2|kek)\\s*[:=]\\s*([^\\s,;]+)"
    private static let queryPattern = "(?i)(token|key|sig|signature|auth|session|passkey|otp)=([^&\\s]+)"
    private static let longBlobPattern = "[A-Za-z0-9+/=]{40,}"

    static func sanitize(_ input: String?) -> String? {
        guard let input, !input.isEmpty else { return input }
        var out = input
        out = out.replacingRegex(bearerPattern, with: "Bearer <redacted>")
        out = out.replacingRegex(keyValuePattern, with: "$1=<redacted>")
        out = out.replacingRegex(queryPattern, with: "$1=<redacted>")
        out = out.replacingRegex(emailPattern, with: "<redacted-email>")
        out = out.replacingRegex(longBlobPattern, with: "<redacted-blob>")
        return out
    }
}

private extension String {
    func replacingRegex(_ pattern: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return self }
        let range = NSRange(startIndex..<endIndex, in: self)
        return regex.stringByReplacingMatches(in: self, options: [], range: range, withTemplate: replacement)
    }
}
