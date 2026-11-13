import SwiftUI

struct RootView: View {
    let chatModelTask: Task<ChatViewModel, Never>
    @State private var chatModel: ChatViewModel?

    var body: some View {
        ZStack {
            EnsuColor.backgroundBase
                .ignoresSafeArea()

            if let chatModel {
                HomeView(chatModel: chatModel)
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tint(EnsuColor.action)
        .task {
            guard chatModel == nil else { return }
            chatModel = await chatModelTask.value
        }
    }
}
