import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = CastViewModel()
    
    var body: some View {
        ZStack {
            switch viewModel.currentView {
            case .connecting:
                StatusView(
                    status: .loading(viewModel.statusMessage),
                    onRetry: nil,
                    debugLogs: nil
                )
                
            case .pairing:
                PairingView(deviceCode: viewModel.deviceCode)
                
            case .slideshow:
                SlideshowView(
                    imageData: viewModel.currentImageData,
                    videoData: viewModel.currentVideoData,
                    isVideo: viewModel.currentFile?.isVideo ?? false,
                    slideshowService: viewModel.slideshowService
                )
                
            case .error:
                StatusView(
                    status: .error(viewModel.errorMessage ?? "Unknown error"),
                    onRetry: viewModel.retryOperation,
                    debugLogs: nil
                )
                
            case .empty:
                StatusView(
                    status: .empty("No photos were found in this album"),
                    onRetry: nil,
                    debugLogs: nil
                )
            }
        }
        .animation(.easeInOut(duration: 0.6), value: viewModel.currentView)
    }
}

#Preview {
    ContentView()
}
