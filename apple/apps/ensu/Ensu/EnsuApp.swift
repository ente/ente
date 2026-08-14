import SwiftUI

@main
struct EnsuApp: App {
    private let assetStore: AssetStore

    init() {
        EnsuLogging.shared.start()
        AssetStore.registerBackgroundTask()
        assetStore = AssetStore()
    }

    var body: some Scene {
        WindowGroup {
            RootView(assetStore: assetStore)
        }
    }
}
