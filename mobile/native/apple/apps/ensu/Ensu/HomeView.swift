import SwiftUI

struct HomeView: View {
    @StateObject private var chatModel: ChatViewModel

    init(assetStore: AssetStore) {
        _chatModel = StateObject(wrappedValue: ChatViewModel(assetStore: assetStore))
    }

    var body: some View {
        ChatView(viewModel: chatModel)
    }
}
