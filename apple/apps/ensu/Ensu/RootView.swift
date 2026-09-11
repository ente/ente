import SwiftUI

struct RootView: View {
    let assetStoreTask: Task<AssetStore, Never>
    @State private var assetStore: AssetStore?

    var body: some View {
        ZStack {
            EnsuColor.backgroundBase
                .ignoresSafeArea()

            if let assetStore {
                HomeView(assetStore: assetStore)
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tint(EnsuColor.action)
        .task {
            assetStore = await assetStoreTask.value
        }
    }
}
