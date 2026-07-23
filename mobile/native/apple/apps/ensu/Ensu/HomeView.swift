import SwiftUI

struct HomeView: View {
    @StateObject private var chatModel = ChatViewModel()

    var body: some View {
        ChatView(viewModel: chatModel)
    }
}
