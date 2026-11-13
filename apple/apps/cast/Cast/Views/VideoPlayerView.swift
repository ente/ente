import AVFoundation
import AVKit
import OSLog
import SwiftUI
import UIKit

private let logger = Logger(subsystem: "io.ente.cast", category: "VideoPlayer")

struct VideoPlayerView: View {
    let videoData: Data
    let suggestedFilename: String?
    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var playerItem: AVPlayerItem?
    @State private var showToast = false
    @State private var toastMessage = ""
    @State private var toastIcon = ""
    @State private var playerObservers: [NSObjectProtocol] = []

    init(videoData: Data, suggestedFilename: String? = nil) {
        self.videoData = videoData
        self.suggestedFilename = suggestedFilename
    }

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
                let suggestedExtension = suggestedFilename?.components(separatedBy: ".").last?
                    .lowercased()

                let tempURL = try await createTemporaryVideoFile(
                    from: videoData,
                    suggestedExtension: suggestedExtension,
                )

                let asset = AVURLAsset(url: tempURL)
                let isPlayable = try await asset.load(.isPlayable)
                let hasVideoTracks = try await !asset.loadTracks(withMediaType: .video).isEmpty

                if isPlayable, hasVideoTracks {
                    let playerItem = AVPlayerItem(url: tempURL)
                    let player = AVPlayer(playerItem: playerItem)

                    monitorPlayerItemStatus(playerItem)

                    self.playerItem = playerItem
                    self.player = player

                    setupPlayer()
                } else {
                    tryVideoFallback(originalURL: tempURL)
                }
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

    private func tryVideoFallback(originalURL: URL) {
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
                logger.error(
                    "Video fallback failed: \(error.localizedDescription, privacy: .public)")
                showErrorState()
            }
        }
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

    private func createTemporaryVideoFile(
        from data: Data,
        suggestedExtension: String? = nil
    ) async throws -> URL {
        let tempDirectory = FileManager.default.temporaryDirectory
        let fileExtension = detectVideoExtension(from: data) ?? suggestedExtension ?? "mp4"
        let tempURL =
            tempDirectory
            .appendingPathComponent("cast_video_\(UUID().uuidString).\(fileExtension)")

        try data.write(to: tempURL)

        Task {
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            try? FileManager.default.removeItem(at: tempURL)
        }

        return tempURL
    }

    private func detectVideoExtension(from data: Data) -> String? {
        let headerBytes = data.prefix(32)

        if headerBytes.count >= 4 {
            let signature = headerBytes.prefix(4)

            if headerBytes.count >= 12 {
                let ftyp = headerBytes.subdata(in: 4..<8)
                if ftyp == Data("ftyp".utf8) {
                    let brand = headerBytes.subdata(in: 8..<12)
                    if brand == Data("mp41".utf8) || brand == Data("mp42".utf8)
                        || brand == Data("isom".utf8) || brand == Data("M4V ".utf8)
                    {
                        return "mp4"
                    } else if brand == Data("qt  ".utf8) {
                        return "mov"
                    }
                }
            }

            if headerBytes.count >= 4 {
                if signature[0] == 0x00, signature[1] == 0x00, signature[2] == 0x00,
                    signature[3] == 0x01
                {
                    return "mp4"
                }
            }

            if signature == Data("RIFF".utf8), headerBytes.count >= 12 {
                let aviSignature = headerBytes.subdata(in: 8..<12)
                if aviSignature == Data("AVI ".utf8) {
                    return "avi"
                }
            }

            if signature == Data([0x1A, 0x45, 0xDF, 0xA3]) {
                return "webm"
            }

            if signature == Data([0x1A, 0x45, 0xDF, 0xA3]) {
                return "mkv"
            }
        }

        return "mp4"
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

#Preview {
    let mockData = Data()
    VideoPlayerView(videoData: mockData, suggestedFilename: "sample_video.mp4")
}
