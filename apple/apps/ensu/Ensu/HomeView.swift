import SwiftUI

struct HomeView: View {
    let chatModel: ChatViewModel

    var body: some View {
        ChatView(viewModel: chatModel)
    }
}
