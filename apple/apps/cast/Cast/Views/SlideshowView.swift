import SwiftUI
import UIKit

struct SlideshowView: View {
    let imageData: Data?
    let videoData: Data?
    let isVideo: Bool
    @ObservedObject var slideshowService: RealSlideshowService

    private var isLivePhoto: Bool {
        slideshowService.currentFile?.isLivePhoto ?? false
    }
    
    @State private var showControls = false
    @State private var controlsTimer: Timer?
    @State private var imageScale: CGFloat = 1.0
    @State private var imageOpacity: Double = 1.0
    @State private var previousImageOpacity: Double = 0.0
    @State private var previousImageData: Data? = nil
    @State private var actionFeedback: ActionFeedback? = nil
    @State private var isPlayingLivePhotoVideo = false
    @State private var lastImageBytes: Int = 0
    @State private var imageDecodeFailed: Bool = false
    @State private var showToast = false
    @State private var toastMessage = ""
    @State private var toastIcon = ""
    @State private var slideTimeRemaining: TimeInterval = 0
    @State private var lastPauseTime: Date?
    @State private var displayImageData: Data? = nil
    @State private var preDecodedImage: UIImage? = nil
    @State private var previousDecodedImage: UIImage? = nil
    
    @FocusState private var isFocused: Bool

    init(imageData: Data? = nil, videoData: Data? = nil, isVideo: Bool = false, slideshowService: RealSlideshowService) {
        self.imageData = imageData
        self.videoData = videoData
        self.isVideo = isVideo
        self.slideshowService = slideshowService
    }
    
    var body: some View {
        // Use pre-decoded images to avoid decoding during render
        let mainUIImage = preDecodedImage
        let previousUIImage = previousDecodedImage

        return GeometryReader { geometry in
            ZStack {
                // Background layer
                if let uiImage = mainUIImage {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .blur(radius: 50)
                        .scaleEffect(2.2)
                        .overlay(Color.teal.opacity(0.001))
                        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                        .ignoresSafeArea()
                } else {
                    Color.black.ignoresSafeArea()
                }
                
                // Foreground content
                if isVideo, let videoData = videoData {
                    VideoPlayerView(
                        videoData: videoData,
                        suggestedFilename: slideshowService.currentFile?.title
                    )
                    .transition(.asymmetric(
                        insertion: .scale(scale: 1.1).combined(with: .opacity),
                        removal: .scale(scale: 0.9).combined(with: .opacity)
                    ))
                } else if isLivePhoto && isPlayingLivePhotoVideo,
                          let liveVideoData = slideshowService.livePhotoVideoData {
                    VideoPlayerView(
                        videoData: liveVideoData,
                        suggestedFilename: slideshowService.currentFile?.title
                    )
                    .transition(.asymmetric(
                        insertion: .scale(scale: 1.1).combined(with: .opacity),
                        removal: .scale(scale: 0.9).combined(with: .opacity)
                    ))
                } else if let uiImage = mainUIImage {
                    // Crossfade image transition
                    ZStack {
                        // Previous image (fading out)
                        if let prevImage = previousUIImage {
                            Image(uiImage: prevImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .scaleEffect(imageScale)
                                .opacity(previousImageOpacity)
                        }
                        
                        // Current image (fading in)
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .scaleEffect(imageScale)
                            .opacity(imageOpacity)
                    }
                    .onAppear {
                        // Pass image data count for logging purposes
                        animateImageIn(bytes: displayImageData?.count ?? 0, isLive: isLivePhoto)
                    }
                    .onDisappear {
                        imageScale = 1.0
                        imageOpacity = 1.0
                        previousImageOpacity = 0.0
                        isPlayingLivePhotoVideo = false
                    }
                    
                    
                } else {
                    // Check if we have an empty state vs loading state
                    if let error = slideshowService.error, 
                       (error.contains("No media files available") || error.contains("Empty file list")) {
                        EmptyState()
                    } else if slideshowService.totalSlides == 0 && !slideshowService.isPlaying {
                        // Still loading initial file list
                        LoadingState()
                    } else {
                        // Files exist but current slide is loading
                        LoadingState()
                    }
                }
                
                // Overlays
                actionFeedbackOverlay
                controlsOverlay
                toastOverlay
            }
        }
        .onChange(of: imageData) { newValue in
            if let newData = newValue {
                Task {
                    // Pre-decode image off main thread
                    let decodedImage = decodedUIImage(from: newData)
                    
                    await MainActor.run {
                        // Store current decoded image as previous for crossfade
                        previousDecodedImage = preDecodedImage
                        previousImageData = displayImageData
                        
                        // Set decoded image first
                        preDecodedImage = decodedImage
                        
                        // Set up opacity states
                        if previousDecodedImage != nil {
                            previousImageOpacity = 1.0
                            imageOpacity = 0.0
                        } else {
                            // First image - no crossfade needed
                            imageOpacity = 1.0
                            previousImageOpacity = 0.0
                        }
                        
                        // Then update display data to trigger view update
                        displayImageData = newData
                        animateImageIn(bytes: newData.count, isLive: isLivePhoto)
                    }
                }
            }
        }
        .onTapGesture { Task { await handlePlayPauseAction() } }
        .onLongPressGesture { handleLongPressGesture() }
        .focusable()
        .focused($isFocused)
        .onMoveCommand { direction in Task { await handleDirectionalInput(direction) } }
        .onPlayPauseCommand {
            if isLivePhoto && slideshowService.livePhotoVideoData != nil {
                handleLongPressGesture()
            } else {
                Task { await handlePlayPauseAction() }
            }
        }
        .onExitCommand { toggleControls() }
        .onAppear {
            startControlsTimer()
            isFocused = true
            // Backup screen saver prevention at view level
            ScreenSaverManager.preventScreenSaver()
            
            // Process initial image data if present and not already processed
            // This handles the case where SlideshowView is created with imageData already populated
            // (e.g., when transitioning from .connecting to .slideshow state)
            // Without this, onChange won't fire and the image won't display
            if let initialImageData = imageData, displayImageData == nil && !isVideo {
                Task {
                    let decodedImage = decodedUIImage(from: initialImageData)
                    
                    await MainActor.run {
                        preDecodedImage = decodedImage
                        imageOpacity = 1.0
                        previousImageOpacity = 0.0
                        displayImageData = initialImageData
                        animateImageIn(bytes: initialImageData.count, isLive: isLivePhoto)
                    }
                }
            }
        }
        .onDisappear {
            // Ensure screen saver prevention is disabled when view disappears
            ScreenSaverManager.allowScreenSaver()
        }
    }
    
    // MARK: - Overlay Views
    
    @ViewBuilder
    private var actionFeedbackOverlay: some View {
        if let feedback = actionFeedback {
            ActionFeedbackView(feedback: feedback)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        withAnimation(.easeOut(duration: 0.25)) { actionFeedback = nil }
                    }
                }
        }
    }
    
    @ViewBuilder
    private var controlsOverlay: some View {
        if showControls {
            EnhancedControlsOverlay(
                isPlaying: slideshowService.isPlaying,
                isPaused: slideshowService.isPaused
            )
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .move(edge: .bottom)),
                removal: .opacity
            ))
        }
    }
    
    @ViewBuilder
    private var toastOverlay: some View {
        if showToast {
            VStack {
                HStack {
                    AppleStyleToast(icon: toastIcon, message: toastMessage)
                    Spacer()
                }
                .padding(.top, 60)
                .padding(.leading, 60)
                Spacer()
            }
        }
    }
    
    private func handleLongPressGesture() {
        showToast(icon: "livephoto.play", message: "Long press called")
        guard isLivePhoto, slideshowService.livePhotoVideoData != nil else { return }
        
        withAnimation(.easeInOut(duration: 0.3)) {
            isPlayingLivePhotoVideo.toggle()
        }
        
        if isPlayingLivePhotoVideo {
            slideshowService.pause()
            showToast(icon: "livephoto.play", message: "Playing Live Photo")
        } else {
            slideshowService.resume()
            showToast(icon: "livephoto", message: "Live Photo Paused")
        }
        
        // Auto-return to image after video plays
        if isPlayingLivePhotoVideo {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isPlayingLivePhotoVideo = false
                }
                slideshowService.resume()
            }
        }
    }
    
    private func handlePlayPauseAction() async {
        slideshowService.togglePlayPause()
        
        await MainActor.run {
            // Show toast notification only
            if slideshowService.isPaused {
                showToast(icon: "pause.fill", message: "Paused")
            } else {
                showToast(icon: "play.fill", message: "Resumed")
            }
        }
    }
    
    private func handleDirectionalInput(_ direction: MoveCommandDirection) async {
        switch direction {
        case .left:
            await slideshowService.previousSlide()
            // No center feedback for navigation
        case .right:
            await slideshowService.nextSlide()
            // No center feedback for navigation
        case .up, .down:
            toggleControls()
        @unknown default:
            break
        }
    }
    
    private func toggleControls() {
        withAnimation(.easeInOut(duration: 0.4)) {
            showControls.toggle()
        }
        if showControls {
            startControlsTimer()
        }
    }
    
    private func startControlsTimer() {
        controlsTimer?.invalidate()
        controlsTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { _ in
            withAnimation(.easeInOut(duration: 0.4)) {
                showControls = false
            }
        }
    }
    
    private func showToast(icon: String, message: String) {
        toastIcon = icon
        toastMessage = message
        showToast = true
        
        // Auto-dismiss after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            showToast = false
        }
    }
    
    // MARK: - Image Decoding & Animation
    
    private func decodedUIImage(from data: Data) -> UIImage? {
        imageDecodeFailed = false
        if let uiImage = UIImage(data: data) {
            // Force decompression by accessing cgImage
            if let cg = uiImage.cgImage {
                return UIImage(cgImage: cg, scale: uiImage.scale, orientation: uiImage.imageOrientation)
            }
            return uiImage
        } else {
            imageDecodeFailed = true
            print("UIImage decode failed (bytes: \(data.count))")
            return nil
        }
    }
    
    private func animateImageIn(bytes: Int, isLive: Bool) {
        lastImageBytes = bytes
        imageScale = 1.0
        
        // Opacity states are already set up in onChange, just animate the crossfade
        withAnimation(.easeInOut(duration: 0.25)) {
            imageOpacity = 1.0
            previousImageOpacity = 0.0
        }
        
        print("Displaying \(isLive ? "live" : "static") image (\(bytes) bytes)")
        
        // Clean up previous image data after animation
        Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
            await MainActor.run {
                previousImageData = nil
                previousImageOpacity = 0.0
            }
        }
    }
}


// MARK: - Supporting Views and Types

struct LoadingState: View {
    @State private var animationPhase: CGFloat = 0
    @State private var pulseScale: CGFloat = 1.0
    
    var body: some View {
        VStack(spacing: 40) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.1), lineWidth: 6)
                    .frame(width: 120, height: 120)
                
                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(
                        LinearGradient(
                            colors: [Color.blue, Color.purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(animationPhase * 360))
                
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.blue.opacity(0.3),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 10,
                            endRadius: 40
                        )
                    )
                    .frame(width: 80, height: 80)
                    .scaleEffect(pulseScale)
            }
            
            
        }
        .onAppear {
            withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                animationPhase = 1.0
            }
            
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                pulseScale = 1.2
            }
        }
    }
}

struct EmptyState: View {
    @State private var pulseScale: CGFloat = 1.0
    
    var body: some View {
        VStack(spacing: 40) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.gray.opacity(0.2),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 20,
                            endRadius: 60
                        )
                    )
                    .frame(width: 120, height: 120)
                    .scaleEffect(pulseScale)
                
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 50, weight: .ultraLight))
                    .foregroundColor(.white.opacity(0.6))
            }
            
            VStack(spacing: 12) {
                Text("No photos in this album")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundColor(.white)
                
                Text("Add some photos to start your slideshow")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                pulseScale = 1.1
            }
        }
    }
}

struct EnhancedControlsOverlay: View {
    let isPlaying: Bool
    let isPaused: Bool
    
    var body: some View {
        VStack {
            Spacer()
            
            HStack {
                Spacer()
                
                VStack(spacing: 20) {
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: isPaused ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(isPaused ? .yellow : .green)
                            
                            Text(isPaused ? "Paused" : "Playing")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        
                        Text("Apple TV Remote Controls")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    
                    HStack(spacing: 40) {
                        NavigationHint(icon: "chevron.left.circle.fill", label: "Previous", direction: .leading)
                        NavigationHint(icon: isPaused ? "play.circle.fill" : "pause.circle.fill", label: isPaused ? "Resume" : "Pause", direction: .center)
                        NavigationHint(icon: "chevron.right.circle.fill", label: "Next", direction: .trailing)
                    }
                    
                    VStack(spacing: 6) {
                        Text("• Touch surface: Play/Pause")
                        Text("• Swipe left/right: Navigate slides")
                        Text("• Menu button: Show/hide controls")
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                }
                .padding(32)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.black.opacity(0.6))
                            .background(
                                RoundedRectangle(cornerRadius: 20).fill(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.05), Color.white.opacity(0.02)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                            )
                        
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    }
                )
                Spacer()
            }
            .padding(.bottom, 60)
        }
    }
}

struct NavigationHint: View {
    let icon: String
    let label: String
    let direction: HorizontalAlignment
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .medium))
            
            Text(label)
                .font(.system(size: 14, weight: .medium))
        }
        .foregroundColor(.white.opacity(0.8))
        .frame(minWidth: 80)
    }
}

enum ActionFeedback {
    case play, pause, next, previous
    
    var iconName: String {
        switch self {
        case .play: "play.circle.fill"
        case .pause: "pause.circle.fill"
        case .next: "forward.circle.fill"
        case .previous: "backward.circle.fill"
        }
    }
    
    var title: String {
        switch self {
        case .play: "Play"
        case .pause: "Pause"
        case .next: "Next"
        case .previous: "Previous"
        }
    }
}

struct ActionFeedbackView: View {
    let feedback: ActionFeedback
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: feedback.iconName)
                .font(.system(size: 50, weight: .medium))
            Text(feedback.title)
                .font(.system(size: 20, weight: .semibold))
        }
        .foregroundColor(.white)
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.7))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.2), lineWidth: 1))
        )
        .transition(.scale.combined(with: .opacity))
    }
}

struct AppleStyleToast: View {
    let icon: String
    let message: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(.white)
            
            Text(message)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.8))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 4)
    }
}

// MARK: - Preview

class MockSlideshowService: ObservableObject {
    @Published var currentFile: (title: String, isLivePhoto: Bool)? = (title: "Sample Image", isLivePhoto: false)
    @Published var isPlaying: Bool = true
    @Published var isPaused: Bool = false
    @Published var livePhotoVideoData: Data? = nil
    
    func togglePlayPause() { isPaused.toggle() }
    func nextSlide() async {}
    func previousSlide() async {}
    func pause() { isPaused = true }
    func resume() { isPaused = false }
}

#Preview {
    struct PreviewWrapper: View {
        @StateObject private var slideshowService = MockSlideshowService()
        
        var body: some View {
            SlideshowView(
                imageData: nil,
                slideshowService: slideshowService as! RealSlideshowService
            )
        }
    }
    
    return PreviewWrapper()
}
