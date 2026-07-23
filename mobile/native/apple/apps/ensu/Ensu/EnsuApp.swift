import SwiftUI

@main
struct EnsuApp: App {
    init() {
        EnsuLogging.shared.start()
        ModelDownloader.registerBackgroundTask()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
