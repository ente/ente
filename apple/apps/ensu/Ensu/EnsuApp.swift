import SwiftUI

@main
struct EnsuApp: App {
    private let assetStoreTask: Task<AssetStore, Never>

    init() {
        EnsuLogging.shared.start()
        AssetStore.registerBackgroundTask()
        assetStoreTask = Task { await AssetStore() }
    }

    var body: some Scene {
        WindowGroup {
            RootView(assetStoreTask: assetStoreTask)
        }
    }
}
