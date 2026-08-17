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
        let levelName: String
        switch level {
        case .error: levelName = "error"
        case .warn: levelName = "warn"
        case .info: levelName = "info"
        }
        print("[\(levelName)][rust][\(target)] \(message)")
    }
}
