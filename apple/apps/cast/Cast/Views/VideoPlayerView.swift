import AVFoundation
import AVKit
import OSLog
import SwiftUI
import UIKit

private let logger = Logger(subsystem: "io.ente.cast", category: "VideoPlayer")

struct VideoPlayerView: View {
    let videoURL: URL
    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var playerItem: AVPlayerItem?
    @State private var showToast = false
    @State private var toastMessage = ""
    @State private var toastIcon = ""
    @State private var playerObservers: [NSObjectProtocol] = []

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
                    .onAppear {
                        setupPlayer()
                    }
                    .onDisappear {
                        cleanup()
                    }
            } else {
                VStack(spacing: 24) {
                    ProgressView()
                        .progressViewStyle(
                            CircularProgressViewStyle(
                                tint: Color(
                                    red: 29 / 255,
                                    green: 185 / 255,
                                    blue: 84 / 255,
                                ))
                        )
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
                let asset = AVURLAsset(url: videoURL)
                let isPlayable = try await asset.load(.isPlayable)
                let tracks = try await asset.loadTracks(withMediaType: .video)
                guard isPlayable, !tracks.isEmpty else {
                    throw VideoPlayerError.invalidVideo
                }
                for track in tracks {
                    let naturalSize = try await track.load(.naturalSize)
                    let transform = try await track.load(.preferredTransform)
                    let displaySize = CGRect(origin: .zero, size: naturalSize)
                        .applying(transform)
                        .standardized
                        .size
                    guard validVideoDimensions(naturalSize),
                        validVideoDimensions(displaySize)
                    else {
                        throw VideoPlayerError.dimensionsTooLarge
                    }
                }

                let playerItem = AVPlayerItem(url: videoURL)
                let player = AVPlayer(playerItem: playerItem)
                monitorPlayerItemStatus(playerItem)
                self.playerItem = playerItem
                self.player = player
                setupPlayer()
            } catch {
                logger.error(
                    "Failed to set up video player: \(error.localizedDescription, privacy: .public)"
                )
                await MainActor.run {
                    showErrorState()
                }
            }
        }
    }

    private func validVideoDimensions(_ size: CGSize) -> Bool {
        let width = abs(size.width)
        let height = abs(size.height)
        return width.isFinite && height.isFinite && width > 0 && height > 0
            && width <= 8192 && height <= 8192 && width * height <= 35_000_000
    }

    private func showErrorState() {}

    private func monitorPlayerItemStatus(_ playerItem: AVPlayerItem) {
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            switch playerItem.status {
            case .readyToPlay:
                timer.invalidate()
            case .failed:
                if let error = playerItem.error {
                    logger.error(
                        "Video player failed: \(error.localizedDescription, privacy: .public)")
                }
                timer.invalidate()
                Task { @MainActor in
                    showErrorState()
                }
            case .unknown:
                break
            @unknown default:
                timer.invalidate()
            }
        }
    }

    private func setupPlayer() {
        guard let player else { return }

        player.actionAtItemEnd = .none
        player.automaticallyWaitsToMinimizeStalling = true

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            logger.error(
                "Failed to set up audio session: \(error.localizedDescription, privacy: .public)")
        }

        setupPlayerObservers()

        player.play()
        isPlaying = true
    }

    private func setupPlayerObservers() {
        guard let player, let currentItem = player.currentItem else { return }
        removePlayerObservers()

        let playbackEnded = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: currentItem,
            queue: .main,
        ) { _ in
            player.seek(to: .zero)
            player.play()
        }

        let playbackFailed = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: currentItem,
            queue: .main,
        ) { notification in
            if let error = notification
                .userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            {
                logger.error(
                    "Video playback failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        let willResignActive = NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main,
        ) { _ in
            player.pause()
        }

        let didBecomeActive = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main,
        ) { _ in
            MainActor.assumeIsolated {
                if isPlaying {
                    player.play()
                }
            }
        }
        playerObservers = [playbackEnded, playbackFailed, willResignActive, didBecomeActive]
    }

    private func removePlayerObservers() {
        for observer in playerObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        playerObservers.removeAll()
    }

    private func cleanup() {
        player?.pause()
        removePlayerObservers()

        do {
            try AVAudioSession.sharedInstance().setActive(
                false,
                options: .notifyOthersOnDeactivation,
            )
        } catch {
            logger.error(
                "Failed to deactivate audio session: \(error.localizedDescription, privacy: .public)"
            )
        }

        player = nil
        playerItem = nil
        isPlaying = false
    }
}

private enum VideoPlayerError: LocalizedError {
    case invalidVideo
    case dimensionsTooLarge

    var errorDescription: String? {
        switch self {
        case .invalidVideo:
            "The video is not playable"
        case .dimensionsTooLarge:
            "The video dimensions exceed the playback limit"
        }
    }
}

#Preview {
    VideoPlayerView(videoURL: URL(fileURLWithPath: "/dev/null"))
}
