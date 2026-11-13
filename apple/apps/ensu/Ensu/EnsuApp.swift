import SwiftUI

@main
struct EnsuApp: App {
    private let chatModelTask: Task<ChatViewModel, Never>

    init() {
        EnsuLogging.shared.start()
        AssetStore.registerBackgroundTask()
        _ = ResponseNotifications.shared
        chatModelTask = Task { await ChatViewModel(assetStore: AssetStore()) }
    }

    var body: some Scene {
        WindowGroup {
            RootView(chatModelTask: chatModelTask)
        }
    }
}
