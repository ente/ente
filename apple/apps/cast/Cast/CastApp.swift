import SwiftUI

@main
struct CastApp: App {
    init() {
        initRustLogging(sink: CastRustLogSink())
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

private final class CastRustLogSink: RustLogSink, @unchecked Sendable {
    func log(level: RustLogLevel, target: String, message: String) {
        let levelName = switch level {
        case .error: "error"
        case .warn: "warn"
        case .info: "info"
        }
        print("[\(levelName)][rust][\(target)] \(message)")
    }
}
