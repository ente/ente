import SwiftUI

struct RootView: View {
    let assetStore: AssetStore

    var body: some View {
        ZStack {
            EnsuColor.backgroundBase
                .ignoresSafeArea()

            HomeView(assetStore: assetStore)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tint(EnsuColor.action)
    }
}
