import SwiftUI
import AVFoundation
import AVKit
import UIKit

struct VideoPlayerView: View {
    let videoData: Data
    let suggestedFilename: String?
    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var playerItem: AVPlayerItem?
    @State private var showToast = false
    @State private var toastMessage = ""
    @State private var toastIcon = ""
    
    init(videoData: Data, suggestedFilename: String? = nil) {
        self.videoData = videoData
        self.suggestedFilename = suggestedFilename
    }
    
    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
            
            if let player = player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
                    .onAppear {
                        setupPlayer()
                    }
                    .onDisappear {
                        cleanup()
                    }
            } else {
                // Clean loading state
                VStack(spacing: 24) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: Color(red: 29/255, green: 185/255, blue: 84/255)))
                        .scaleEffect(2.0)
                    
                    Text("Loading video...")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                }
            }
        }
        .onAppear {
            setupVideoPlayer()
        }
        .onDisappear {
            cleanup()
        }
    }
    
    private func setupVideoPlayer() {
        Task {
            do {
                let suggestedExtension = suggestedFilename?.components(separatedBy: ".").last?.lowercased()
                
                let tempURL = try await createTemporaryVideoFile(from: videoData, suggestedExtension: suggestedExtension)
                
                await MainActor.run {
                    let asset = AVURLAsset(url: tempURL)
                    
                    Task {
                        let isPlayable = try await asset.load(.isPlayable)
                        let hasVideoTracks = try await !asset.loadTracks(withMediaType: .video).isEmpty
                        
                        await MainActor.run {
                            if isPlayable && hasVideoTracks {
                                let playerItem = AVPlayerItem(url: tempURL)
                                let player = AVPlayer(playerItem: playerItem)
                                
                                // Monitor player item status using modern async/await approach
                                self.monitorPlayerItemStatus(playerItem)
                                
                                self.playerItem = playerItem
                                self.player = player
                                
                                setupPlayer()
                            } else {
                                self.tryVideoFallback(originalURL: tempURL)
                            }
                        }
                    }
                }
            } catch {
                print("Failed to setup video player: \(error)")
                await MainActor.run {
                    self.showErrorState()
                }
            }
        }
    }
    
    private func tryVideoFallback(originalURL: URL) {
        // Try creating a new temp file with .mov extension as fallback
        Task {
            do {
                let fallbackURL = originalURL.deletingPathExtension().appendingPathExtension("mov")
                try FileManager.default.copyItem(at: originalURL, to: fallbackURL)
                
                await MainActor.run {
                    let playerItem = AVPlayerItem(url: fallbackURL)
                    let player = AVPlayer(playerItem: playerItem)
                    
                    self.playerItem = playerItem
                    self.player = player
                    
                    setupPlayer()
                }
            } catch {
                print("Video fallback also failed: \(error)")
                showErrorState()
            }
        }
    }
    
    private func showErrorState() {
        // Could show an error message or placeholder
    }
    
    private func monitorPlayerItemStatus(_ playerItem: AVPlayerItem) {
        // Monitor status using a timer-based approach since we can't use KVO in SwiftUI structs
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            switch playerItem.status {
            case .readyToPlay:
                timer.invalidate()
            case .failed:
                if let error = playerItem.error {
                    print("Video player failed with error: \(error)")
                    print("Error details: \(error.localizedDescription)")
                }
                timer.invalidate()
                Task { @MainActor in
                    self.showErrorState()
                }
            case .unknown:
                // Keep checking
                break
            @unknown default:
                timer.invalidate()
            }
        }
    }
    
    private func setupPlayer() {
        guard let player = player else { return }
        
        // Configure player for TV playback
        player.actionAtItemEnd = .none
        player.automaticallyWaitsToMinimizeStalling = true
        
        // Set audio session for proper audio handling
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to set audio session: \(error)")
        }
        
        setupPlayerObservers()
        
        player.play()
        isPlaying = true
    }
    
    private func setupPlayerObservers() {
        guard let player = player, let currentItem = player.currentItem else { return }
        
        // Add observer for when video ends
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: currentItem,
            queue: .main
        ) { _ in
            // Loop the video
            player.seek(to: .zero)
            player.play()
        }
        
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: currentItem,
            queue: .main
        ) { notification in
            if let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error {
                print("Video playback failed: \(error)")
            }
        }
        
        // Add observer for app lifecycle
        NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            player.pause()
        }
        
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            if self.isPlaying {
                player.play()
            }
        }
    }
    
    private func createTemporaryVideoFile(from data: Data, suggestedExtension: String? = nil) async throws -> URL {
        let tempDirectory = FileManager.default.temporaryDirectory
        let fileExtension = detectVideoExtension(from: data) ?? suggestedExtension ?? "mp4"
        let tempURL = tempDirectory.appendingPathComponent("cast_video_\(UUID().uuidString).\(fileExtension)")
        
        try data.write(to: tempURL)
        
        // Schedule cleanup of temp file after some time
        Task {
            try? await Task.sleep(nanoseconds: 60_000_000_000) // 60 seconds
            try? FileManager.default.removeItem(at: tempURL)
        }
        
        return tempURL
    }
    
    private func detectVideoExtension(from data: Data) -> String? {
        let headerBytes = data.prefix(32)  // Read more bytes for better detection
        
        if headerBytes.count >= 4 {
            let signature = headerBytes.prefix(4)
            
            // MP4/MOV formats (most compatible with AVPlayer)
            if headerBytes.count >= 12 {
                let ftyp = headerBytes.subdata(in: 4..<8)
                if ftyp == Data("ftyp".utf8) {
                    let brand = headerBytes.subdata(in: 8..<12)
                    if brand == Data("mp41".utf8) || brand == Data("mp42".utf8) || 
                       brand == Data("isom".utf8) || brand == Data("M4V ".utf8) {
                        return "mp4"
                    } else if brand == Data("qt  ".utf8) {
                        return "mov"
                    }
                }
            }
            
            // Check for H.264 NAL units (common in MP4)
            if headerBytes.count >= 4 {
                if signature[0] == 0x00 && signature[1] == 0x00 && signature[2] == 0x00 && signature[3] == 0x01 {
                    return "mp4"
                }
            }
            
            // AVI format (less compatible with tvOS)
            if signature == Data("RIFF".utf8) && headerBytes.count >= 12 {
                let aviSignature = headerBytes.subdata(in: 8..<12)
                if aviSignature == Data("AVI ".utf8) {
                    return "avi"
                }
            }
            
            // WebM format (limited support on tvOS)
            if signature == Data([0x1A, 0x45, 0xDF, 0xA3]) {
                return "webm"
            }
            
            // MKV format
            if signature == Data([0x1A, 0x45, 0xDF, 0xA3]) {
                return "mkv"
            }
        }
        
        return "mp4"
    }
    
    private func cleanup() {
        player?.pause()
        
        // KVO observer removal no longer needed as we use modern async/await approach
        
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemFailedToPlayToEndTime, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIApplication.didBecomeActiveNotification, object: nil)
        
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("Failed to deactivate audio session: \(error)")
        }
        
        player = nil
        playerItem = nil
        isPlaying = false
    }
}

#Preview {
    let mockData = Data()
    VideoPlayerView(videoData: mockData, suggestedFilename: "sample_video.mp4")
}
