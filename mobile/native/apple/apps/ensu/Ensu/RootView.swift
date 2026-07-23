import SwiftUI

struct RootView: View {
    var body: some View {
        ZStack {
            EnsuColor.backgroundBase
                .ignoresSafeArea()

            HomeView()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tint(EnsuColor.action)
    }
}
