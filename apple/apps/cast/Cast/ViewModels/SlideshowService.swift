import AVKit
import Foundation
import OSLog
import SwiftUI
import UIKit

private let logger = Logger(subsystem: "io.ente.cast", category: "Slideshow")

@MainActor
class RealSlideshowService: ObservableObject {
    private struct MediaTask {
        let id: UUID
        let generation: UUID
        let file: CastFile
        let task: Task<CastMedia, Error>
    }

    @Published var currentImageData: Data?
    @Published var currentVideoData: Data?
    @Published var currentVideoURL: URL?
    @Published var livePhotoVideoURL: URL?
    @Published var videoPlayer: AVPlayer?
    @Published var isVideoPlaying: Bool = false
    @Published var videoCurrentTime: Double = 0
    @Published var videoDuration: Double = 0
    @Published var currentFile: CastFile?
    @Published var error: String?

    @Published var isPlaying: Bool = false
    @Published var isPaused: Bool = false
    @Published var slideLoadingProgress: Double = 0.0
    @Published var currentSlideIndex: Int = 0
    @Published var totalSlides: Int = 0

    private var allFiles: [CastFile] = []
    private var currentFileIndex: Int = 0
    private var lastUpdateTime: Int64 = 0
    private var isLoadingMore: Bool = false
    private var hasCompletedInitialFetch: Bool = false
    private var storedCastPayload: CastPayload?

    private var diffPollingTimer: Timer?
    private let diffPollingInterval: TimeInterval = 5.0
    private var isPeriodicPollingEnabled: Bool = true
    private var currentFileWasDeleted: Bool = false
    private var isStopping: Bool = false

    private var slideTimer: Timer?
    private var prefetchedFileIDs: Set<Int> = []
    private var mediaTasks: [Int: MediaTask] = [:]
    private var prefetchTask: Task<Void, Never>?
    private var mediaClient: CastMediaClient?
    private var mediaGeneration = UUID()
    private var videoEndObserver: NSObjectProtocol?
    private let slideshowConfiguration = SlideConfiguration.tvOptimized
    private var slideTimeRemaining: TimeInterval = 0
    private var slidePauseTime: Date?
    private var slideStartTime: Date?

    private let fileCache = ThreadSafeFileCache(
        maxBytes: 4096 * 1024 * 1024,
        shrinkTargetBytes: 2048 * 1024 * 1024,
    )

    private var didDisplayFirstFile: Bool = false

    private var baseURL = APIEndpoint.current
    private let castDownloadOrigin = "https://cast-albums.ente.com"

    private var isHandlingAuthExpiry: Bool = false

    func pause() {
        slideTimer?.invalidate()
        slideTimer = nil
        isPlaying = false
        isPaused = true

        if let startTime = slideStartTime {
            let elapsed = Date().timeIntervalSince(startTime)
            let totalDuration = currentFile.map { slideshowConfiguration.duration(for: $0) } ?? 0
            slideTimeRemaining = max(0, totalDuration - elapsed)
        }
        slidePauseTime = Date()
    }

    func resume() {
        guard !allFiles.isEmpty else { return }
        isPaused = false
        isPlaying = true
        slidePauseTime = nil

        if slideTimeRemaining > 0 {
            startSlideTimer(withDuration: slideTimeRemaining)
        } else {
            startSlideTimer()
        }
    }

    func togglePlayPause() {
        if isPaused || !isPlaying {
            resume()
        } else {
            pause()
        }
    }

    func nextSlide() async {
        // Ignore timer callbacks after the session has been reset.
        guard storedCastPayload != nil else { return }
        guard !allFiles.isEmpty else {
            await MainActor.run {
                self.error = "No media files available in this album"
            }
            return
        }

        if allFiles.count == 1 {
            if isPlaying, !isPaused {
                startSlideTimer()
            }
            return
        }

        if currentFileWasDeleted {
            currentFileWasDeleted = false
            // Removing this file already exposed the next item at this index.
            if currentFileIndex >= allFiles.count {
                currentFileIndex = 0
            }
        } else {
            currentFileIndex = (currentFileIndex + 1) % allFiles.count
        }

        await displaySlideAtCurrentIndex()
        if isPlaying, !isPaused {
            startSlideTimer()
        }
    }

    func previousSlide() async {
        guard !allFiles.isEmpty else { return }
        currentFileIndex = currentFileIndex > 0 ? currentFileIndex - 1 : allFiles.count - 1
        await displaySlideAtCurrentIndex()
        if isPlaying, !isPaused {
            startSlideTimer()
        }
    }

    func start(castPayload: CastPayload) async {
        ScreenSaverManager.preventScreenSaver()

        await clearExpiredTokenState()
        baseURL = APIEndpoint.current
        storedCastPayload = castPayload
        mediaGeneration = UUID()
        do {
            mediaClient = try CastMediaClient(
                apiOrigin: baseURL.absoluteString,
                directDownloadOrigin: baseURL == APIEndpoint.production
                    ? castDownloadOrigin : nil,
                castToken: castPayload.castToken,
            )
        } catch {
            self.error = "Failed to initialize media downloads: \(error.localizedDescription)"
            return
        }
        if error != nil {
            error = nil
        }

        await initializeFileList(castPayload: castPayload)
        guard storedCastPayload == castPayload else { return }

        let fileCount = await MainActor.run { allFiles.count }
        if fileCount == 0 {
            error = "No media files available in this album"
            return
        }

        let validFileIDs = await Set(MainActor.run { allFiles.map(\.id) })
        await cleanupExpiredCache(validFileIDs: validFileIDs, castPayload: castPayload)
        guard storedCastPayload == castPayload else { return }

        totalSlides = fileCount
        currentFileIndex = 0
        currentSlideIndex = 0
        isPlaying = true
        isPaused = false

        await displaySlideAtCurrentIndex()
        guard storedCastPayload == castPayload else { return }

        startSlideTimer()
        logger.info("Slideshow started with \(fileCount) slides")
    }

    func stop() async {
        ScreenSaverManager.allowScreenSaver()
        removeVideoEndObserver()
        prefetchTask?.cancel()
        mediaTasks.values.forEach { $0.task.cancel() }

        await MainActor.run {
            isStopping = true
            stopPeriodicDiffPolling()
        }

        slideTimer?.invalidate()
        slideTimer = nil

        await MainActor.run {
            currentFile = nil
            currentImageData = nil
            currentVideoData = nil
            currentVideoURL = nil
            livePhotoVideoURL = nil
            error = nil
        }

        logger.info("Slideshow stopped")

        await MainActor.run {
            isStopping = false
        }
    }

    func clearExpiredTokenState() async {
        ScreenSaverManager.allowScreenSaver()
        removeVideoEndObserver()
        prefetchTask?.cancel()
        mediaTasks.values.forEach { $0.task.cancel() }

        await MainActor.run {
            slideTimer?.invalidate()
            slideTimer = nil
            storedCastPayload = nil
            mediaClient = nil
            mediaGeneration = UUID()
            lastUpdateTime = 0
            hasCompletedInitialFetch = false
            allFiles.removeAll()
            prefetchedFileIDs.removeAll()
            error = nil
            currentFile = nil
            currentImageData = nil
            currentVideoData = nil
            currentVideoURL = nil
            livePhotoVideoURL = nil
        }
        // Preserve the cache across sessions.
    }

    @MainActor
    private func initializeFileList(castPayload: CastPayload) async {
        if hasCompletedInitialFetch, !allFiles.isEmpty {
            return
        }

        allFiles.removeAll()
        lastUpdateTime = 0
        currentFileIndex = 0
        hasCompletedInitialFetch = false

        do {
            try await fetchAllFiles(castPayload: castPayload)
            guard storedCastPayload == castPayload else { return }
            hasCompletedInitialFetch = true
            if !allFiles.isEmpty {
                allFiles.shuffle()
            }
        } catch {
            guard storedCastPayload == castPayload else { return }
            logger.error("Failed to fetch files: \(error.localizedDescription, privacy: .public)")
            hasCompletedInitialFetch = false
            self.error = "Failed to load files: \(error.localizedDescription)"
        }
    }

    private func fetchAllFiles(castPayload: CastPayload) async throws {
        var hasMore = true
        var sinceTime = await MainActor.run { lastUpdateTime }

        while hasMore {
            let result = try await fetchFilesBatch(castPayload: castPayload, sinceTime: sinceTime)
            guard storedCastPayload == castPayload else { return }

            await processDiffBatch(result.files, castPayload: castPayload)
            guard storedCastPayload == castPayload else { return }

            await MainActor.run {
                if result.latestUpdateTime > self.lastUpdateTime {
                    self.lastUpdateTime = result.latestUpdateTime
                }
            }

            hasMore = result.hasMore
            sinceTime = result.latestUpdateTime
        }

        guard storedCastPayload == castPayload else { return }
        startPeriodicDiffPolling()
    }

    private func fetchFilesBatch(
        castPayload: CastPayload,
        sinceTime: Int64
    ) async throws
        -> (files: [[String: Any]], hasMore: Bool, latestUpdateTime: Int64)
    {
        guard storedCastPayload == castPayload else { throw CancellationError() }
        let url = baseURL.appendingPathComponent("cast/diff").appending(queryItems: [
            URLQueryItem(name: "sinceTime", value: String(sinceTime))
        ])

        var request = URLRequest(url: url)
        request.setValue(castPayload.castToken, forHTTPHeaderField: "X-Cast-Access-Token")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard storedCastPayload == castPayload else { throw CancellationError() }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CastError.networkError("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 401 {
                handleUnauthorizedError()
                throw CastError.serverError(
                    401,
                    "Authentication expired - resetting to pairing mode",
                )
            }
            throw CastError.serverError(
                httpResponse.statusCode,
                String(data: data, encoding: .utf8),
            )
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let diff = json["diff"] as? [[String: Any]]
        else {
            throw CastError.networkError("Invalid JSON response")
        }

        let hasMore = json["hasMore"] as? Bool ?? false

        var latestUpdateTime = sinceTime
        for item in diff {
            if let updateTime = item["updationTime"] as? Int64 {
                latestUpdateTime = max(latestUpdateTime, updateTime)
            }
        }

        return (files: diff, hasMore: hasMore, latestUpdateTime: latestUpdateTime)
    }

    @MainActor
    private func processDiffBatch(_ items: [[String: Any]], castPayload: CastPayload) async {
        let wasEmpty = allFiles.isEmpty
        var currentFileChanged = false
        let originalCurrentFile =
            currentFileIndex
                < allFiles
                .count ? allFiles[currentFileIndex] : nil

        for item in items {
            guard storedCastPayload == castPayload else { return }
            guard let id = item["id"] as? Int else {
                continue
            }

            let isDeleted = item["isDeleted"] as? Bool ?? false

            if isDeleted {
                if let index = allFiles.firstIndex(where: { $0.id == id }) {
                    allFiles.remove(at: index)

                    if originalCurrentFile?.id == id {
                        currentFileWasDeleted = true

                        Task {
                            guard self.storedCastPayload == castPayload else { return }
                            await self.nextSlide()
                        }
                    }

                    if index < currentFileIndex, currentFileIndex > 0 {
                        currentFileIndex -= 1
                    } else if index == currentFileIndex, currentFileIndex >= allFiles.count,
                        !allFiles.isEmpty
                    {
                        currentFileIndex = 0
                    }

                    prefetchedFileIDs.remove(id)
                    mediaTasks[id]?.task.cancel()
                    await removeCachedFileContent(fileID: id)
                }
            } else {
                do {
                    if let file = try await decryptFileMetadata(
                        item: item,
                        collectionKey: castPayload.collectionKey,
                    ) {
                        guard storedCastPayload == castPayload else { return }
                        // Cast images and Live Photos, not standalone videos.
                        if file.isVideo, !file.isLivePhoto {
                            continue
                        }
                        if let existingIndex = allFiles.firstIndex(where: { $0.id == id }) {
                            let oldFile = allFiles[existingIndex]
                            allFiles[existingIndex] = file

                            if oldFile.hash != file.hash, file.hash != nil {
                                prefetchedFileIDs.remove(id)
                                mediaTasks[id]?.task.cancel()
                                await removeCachedFileContent(fileID: id)
                            }

                            if existingIndex == currentFileIndex {
                                currentFileChanged = true
                            }
                        } else {
                            allFiles.append(file)
                        }
                    }
                } catch {
                    logger.error(
                        "Failed to process file metadata: \(error.localizedDescription, privacy: .public)"
                    )
                }
            }
        }
        guard storedCastPayload == castPayload else { return }

        if allFiles.isEmpty {
            slideTimer?.invalidate()
            slideTimer = nil
            isPlaying = false
            isPaused = false
            currentImageData = nil
            currentVideoData = nil
            currentVideoURL = nil
            livePhotoVideoURL = nil
            totalSlides = 0
            currentSlideIndex = 0
            currentFileIndex = 0
            error = "No media files available in this album"
        } else if wasEmpty {
            currentFileIndex = 0
            currentSlideIndex = 0
            totalSlides = allFiles.count

            if storedCastPayload != nil {
                logger.info("Restarting slideshow with \(self.allFiles.count) files")
                // Clear before loading to avoid an empty-state flash.
                error = nil

                Task {
                    guard storedCastPayload == castPayload else { return }
                    await displaySlideAtCurrentIndex()
                    guard storedCastPayload == castPayload else { return }
                    await MainActor.run {
                        self.isPlaying = true
                        self.isPaused = false
                        NotificationCenter.default.post(name: .slideshowRestarted, object: nil)
                    }
                    startSlideTimer()
                }
            }
        } else {
            totalSlides = allFiles.count

            if currentFileIndex >= allFiles.count {
                currentFileIndex = 0
            }

            if currentFileChanged, !allFiles.isEmpty {
                Task {
                    guard storedCastPayload == castPayload else { return }
                    await displaySlideAtCurrentIndex()
                }
            }
        }

        let currentValidFileIDs = Set(allFiles.map(\.id))
        Task {
            await cleanupExpiredCache(validFileIDs: currentValidFileIDs, castPayload: castPayload)
        }
    }

    private func displaySlideAtCurrentIndex() async {
        guard currentFileIndex >= 0, currentFileIndex < allFiles.count,
            let payload = storedCastPayload
        else { return }

        await MainActor.run {
            currentSlideIndex = currentFileIndex
            slideLoadingProgress = 0.0
        }

        do {
            let file = allFiles[currentFileIndex]
            await MainActor.run { slideLoadingProgress = 0.5 }

            let media = try await downloadAndDecryptFileContent(
                castPayload: payload,
                file: file,
            )
            guard storedCastPayload == payload else { return }

            prefetchedFileIDs.insert(file.id)

            try updateCurrentSlide(with: media, file: file)
            await MainActor.run { slideLoadingProgress = 1.0 }

            startPrefetching()

        } catch {
            guard storedCastPayload == payload else { return }
            logger.error(
                "Failed to load slideshow item: \(error.localizedDescription, privacy: .public)")

            await MainActor.run {
                slideLoadingProgress = 0.0
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                Task {
                    guard self.storedCastPayload == payload else { return }
                    await self.skipToNextSlide()
                }
            }
        }
    }

    @MainActor
    private func updateCurrentSlide(with media: CastMedia, file: CastFile) throws {
        let wasEmpty = error == "No media files available in this album"
        error = nil
        currentFile = file

        if file.isLivePhoto {
            guard let imagePath = media.imagePath, let videoPath = media.videoPath else {
                throw CastError.decryptionError("Live Photo components are missing")
            }
            currentImageData = try Data(
                contentsOf: URL(fileURLWithPath: imagePath),
                options: .mappedIfSafe,
            )
            livePhotoVideoURL = URL(fileURLWithPath: videoPath)
            currentVideoData = nil
            currentVideoURL = nil
            startSlideTimer()
        } else if file.isVideo {
            currentImageData = nil
            livePhotoVideoURL = nil
            guard let videoPath = media.videoPath else {
                throw CastError.decryptionError("Video component is missing")
            }
            let url = URL(fileURLWithPath: videoPath)
            currentVideoURL = url
            currentVideoData = nil
            prepareVideoPlayer(url: url)
        } else {
            guard let imagePath = media.imagePath else {
                throw CastError.decryptionError("Image component is missing")
            }
            currentVideoData = nil
            currentVideoURL = nil
            livePhotoVideoURL = nil
            currentImageData = try Data(
                contentsOf: URL(fileURLWithPath: imagePath),
                options: .mappedIfSafe,
            )
            startSlideTimer()
        }
        error = nil

        if wasEmpty {
            NotificationCenter.default.post(name: .slideshowRestarted, object: nil)
        }
    }

    private func startSlideTimer(withDuration customDuration: TimeInterval? = nil) {
        guard let currentFile else { return }
        // Video playback advances the slideshow when it ends.
        if currentFile.isVideo {
            slideTimeRemaining = 0
            slideStartTime = nil
            return
        }

        slideTimer?.invalidate()
        let duration = customDuration ?? slideshowConfiguration.duration(for: currentFile)
        slideStartTime = Date()
        slideTimeRemaining = duration

        slideTimer =
            Timer
            .scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.isPlaying, !self.isPaused else { return }
                    self.slideTimeRemaining = 0
                    self.slideStartTime = nil

                    await self.nextSlide()
                }
            }
    }

    private func skipToNextSlide() async {
        guard !allFiles.isEmpty, let payload = storedCastPayload else { return }

        currentFileIndex = (currentFileIndex + 1) % allFiles.count

        let maxRetries = allFiles.count
        var retryCount = 0

        while retryCount < maxRetries {
            do {
                let file = allFiles[currentFileIndex]

                let media = try await downloadAndDecryptFileContent(
                    castPayload: payload,
                    file: file,
                )
                guard storedCastPayload == payload else { return }

                prefetchedFileIDs.insert(file.id)
                try updateCurrentSlide(with: media, file: file)

                await MainActor.run {
                    currentSlideIndex = currentFileIndex
                    slideLoadingProgress = 1.0
                }

                if isPlaying, !isPaused {
                    startSlideTimer()
                }

                startPrefetching()
                return

            } catch {
                guard storedCastPayload == payload else { return }
                logger.error(
                    "Failed to load next slideshow item: \(error.localizedDescription, privacy: .public)"
                )
                currentFileIndex = (currentFileIndex + 1) % allFiles.count
                retryCount += 1
            }
        }

        await MainActor.run {
            self.error =
                "Unable to load any slides. All files may be corrupted or have decryption issues."
        }
    }

    private func startPrefetching() {
        guard let payload = storedCastPayload else { return }
        let previousTask = prefetchTask
        previousTask?.cancel()
        let files = allFiles
        let startIndex = currentFileIndex
        prefetchTask = Task { [weak self] in
            _ = await previousTask?.value
            guard let self, !Task.isCancelled else { return }
            let prefetchCount = min(slideshowConfiguration.prefetchCount, max(0, files.count - 1))
            guard slideshowConfiguration.enablePrefetching, prefetchCount > 0 else { return }
            for i in 1...prefetchCount {
                guard !Task.isCancelled else { return }
                guard storedCastPayload == payload else { return }
                let file = files[(startIndex + i) % files.count]

                if prefetchedFileIDs.contains(file.id) {
                    continue
                }

                do {
                    _ = try await downloadAndDecryptFileContent(
                        castPayload: payload,
                        file: file,
                    )
                    guard storedCastPayload == payload else { return }
                    prefetchedFileIDs.insert(file.id)

                    while prefetchedFileIDs.count > slideshowConfiguration.maxCacheSize {
                        guard let id = prefetchedFileIDs.first(where: { $0 != currentFile?.id })
                        else { break }
                        prefetchedFileIDs.remove(id)
                    }

                } catch {
                    guard storedCastPayload == payload else { return }
                    continue
                }

                try? await Task.sleep(
                    nanoseconds: UInt64(slideshowConfiguration.prefetchDelay * 1_000_000_000),
                )
            }
        }
    }

    private func prepareVideoPlayer(url: URL) {
        removeVideoEndObserver()
        let playerItem = AVPlayerItem(url: url)
        videoEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main,
        ) { [weak self] _ in
            Task { @MainActor in
                self?.videoDidFinish()
            }
        }
        let player = AVPlayer(playerItem: playerItem)
        player.automaticallyWaitsToMinimizeStalling = true
        videoPlayer = player
        isVideoPlaying = false
        videoCurrentTime = 0
        Task { @MainActor in
            if let duration = try? await playerItem.asset.load(.duration) {
                self.videoDuration = CMTimeGetSeconds(duration)
            }
        }
        playVideo()
        startVideoProgressUpdates()
    }

    private func removeVideoEndObserver() {
        if let videoEndObserver {
            NotificationCenter.default.removeObserver(videoEndObserver)
        }
        videoEndObserver = nil
    }

    private func startVideoProgressUpdates() {
        videoPlayer?.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main,
        ) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                self.videoCurrentTime = CMTimeGetSeconds(time)
                if let duration = self.videoPlayer?.currentItem?.duration.seconds,
                    duration.isFinite
                {
                    self.videoDuration = duration
                }
            }
        }
    }

    func playVideo() {
        guard let player = videoPlayer else { return }
        player.play()
        isVideoPlaying = true
        slideTimer?.invalidate()
    }

    @MainActor
    private func videoDidFinish() {
        isVideoPlaying = false
        videoPlayer?.seek(to: .zero)
        Task {
            await self.nextSlide()
        }
    }

    @MainActor
    private func startPeriodicDiffPolling() {
        guard isPeriodicPollingEnabled, storedCastPayload != nil else { return }

        stopPeriodicDiffPolling()

        diffPollingTimer = Timer.scheduledTimer(
            withTimeInterval: diffPollingInterval,
            repeats: true,
        ) { [weak self] _ in
            Task {
                await self?.performPeriodicDiffCheck()
            }
        }
    }

    @MainActor
    private func stopPeriodicDiffPolling() {
        diffPollingTimer?.invalidate()
        diffPollingTimer = nil
    }

    private func performPeriodicDiffCheck() async {
        let payload = await MainActor.run { storedCastPayload }
        let isEnabled = await MainActor.run { isPeriodicPollingEnabled }

        guard let payload, isEnabled else { return }

        do {
            let currentTime = await MainActor.run { lastUpdateTime }
            let result = try await fetchFilesBatch(castPayload: payload, sinceTime: currentTime)
            guard storedCastPayload == payload else { return }

            if !result.files.isEmpty {
                await processDiffBatch(result.files, castPayload: payload)
                guard storedCastPayload == payload else { return }

                if result.latestUpdateTime > lastUpdateTime {
                    lastUpdateTime = result.latestUpdateTime
                }
            }

        } catch {
            if let castError = error as? CastError,
                case .serverError(401, _) = castError
            {
                // fetchFilesBatch already handled this error.
            } else {
                logger.error(
                    "Periodic diff check failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    @MainActor
    private func handleUnauthorizedError() {
        guard !isHandlingAuthExpiry else {
            return
        }

        isHandlingAuthExpiry = true

        ScreenSaverManager.allowScreenSaver()

        isPeriodicPollingEnabled = false
        stopPeriodicDiffPolling()

        NotificationCenter.default.post(name: .authenticationExpired, object: nil)

        // Keep the guard set while the session resets.
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                self.isHandlingAuthExpiry = false
            }
        }
    }

    private func downloadAndDecryptFileContent(
        castPayload: CastPayload,
        file: CastFile
    ) async throws -> CastMedia {
        if isStopping {
            throw CastError.networkError("Service is stopping")
        }
        guard let mediaClient else {
            throw CastError.networkError("Media client is unavailable")
        }
        let kind = mediaKind(for: file)
        let maximumBytes = maximumBytes(for: file)
        if let directory = await fileCache.get(file.id) {
            do {
                return try mediaClient.openCached(
                    directory: directory.path,
                    kind: kind,
                    maximumBytes: maximumBytes,
                )
            } catch {
                await fileCache.remove(file.id)
            }
        }
        while let existing = mediaTasks[file.id] {
            if existing.generation == mediaGeneration, existing.file == file {
                return try await existing.task.value
            }
            existing.task.cancel()
            _ = try? await existing.task.value
            if mediaTasks[file.id]?.id == existing.id {
                mediaTasks.removeValue(forKey: file.id)
            }
        }

        let reservationBytes = file.isLivePhoto ? maximumBytes * 2 : maximumBytes
        let taskID = UUID()
        let generation = mediaGeneration
        let task = Task<CastMedia, Error> {
            let reservation = try await fileCache.reserve(
                file.id,
                maximumBytes: Int(reservationBytes),
            )
            do {
                let media = try await mediaClient.download(
                    request: CastMediaDownloadRequest(
                        fileId: Int64(file.id),
                        title: file.title,
                        kind: kind,
                        encryptedKey: file.encryptedKey,
                        keyDecryptionNonce: file.keyDecryptionNonce,
                        collectionKey: castPayload.collectionKey,
                        decryptionHeader: file.fileDecryptionHeader,
                        outputDirectory: reservation.directory.path,
                        maximumBytes: maximumBytes,
                    ),
                )
                try Task.checkCancellation()
                try await fileCache.commit(
                    reservation,
                    maximumEntryBytes: Int(maximumBytes),
                )
                return media
            } catch {
                await fileCache.cancel(reservation)
                throw error
            }
        }
        mediaTasks[file.id] = MediaTask(
            id: taskID,
            generation: generation,
            file: file,
            task: task,
        )
        defer {
            if mediaTasks[file.id]?.id == taskID {
                mediaTasks.removeValue(forKey: file.id)
            }
        }
        do {
            let media = try await task.value
            guard storedCastPayload == castPayload else { throw CancellationError() }
            return media
        } catch let mediaError as CastMediaError {
            if case .Unauthorized = mediaError {
                handleUnauthorizedError()
            }
            throw mediaError
        }
    }

    private func mediaKind(for file: CastFile) -> CastMediaKind {
        if file.isLivePhoto {
            .livePhoto
        } else if file.isVideo {
            .video
        } else {
            .image
        }
    }

    private func maximumBytes(for file: CastFile) -> UInt64 {
        UInt64(
            file.isLivePhoto || file.isVideo
                ? slideshowConfiguration.maxVideoSize
                : slideshowConfiguration.maxImageSize,
        )
    }

    private func decryptFileMetadata(
        item: [String: Any],
        collectionKey: String
    ) async throws -> CastFile? {
        guard let id = item["id"] as? Int,
            let encryptedKey = item["encryptedKey"] as? String,
            let keyDecryptionNonce = item["keyDecryptionNonce"] as? String,
            let metadataDict = item["metadata"] as? [String: Any],
            let encryptedMetadata = metadataDict["encryptedData"] as? String,
            let metadataHeader = metadataDict["decryptionHeader"] as? String,
            let fileDict = item["file"] as? [String: Any],
            let fileDecryptionHeader = fileDict["decryptionHeader"] as? String
        else {
            logger.warning("Skipping file with incomplete metadata")
            return nil
        }

        let fileKey = try decryptFileKey(
            encryptedKey: encryptedKey,
            nonce: keyDecryptionNonce,
            collectionKey: collectionKey,
        )

        let metadata = try decryptMetadata(
            encryptedData: encryptedMetadata,
            decryptionHeader: metadataHeader,
            fileKey: fileKey,
        )

        let fileMetadata = try parseFileMetadata(data: metadata)

        let isVideo = fileMetadata.fileType == 1
        let isLivePhoto = fileMetadata.fileType == 2
        return CastFile(
            id: id,
            title: fileMetadata.title,
            isVideo: isVideo,
            isLivePhoto: isLivePhoto,
            encryptedKey: encryptedKey,
            keyDecryptionNonce: keyDecryptionNonce,
            fileDecryptionHeader: fileDecryptionHeader,
            hash: fileMetadata.hash,
        )
    }

    private func decryptFileKey(
        encryptedKey: String, nonce: String,
        collectionKey: String
    ) throws -> Data {
        guard let encryptedKeyData = Data(base64Encoded: encryptedKey),
            let nonceData = Data(base64Encoded: nonce),
            let collectionKeyData = Data(base64Encoded: collectionKey)
        else {
            throw CastError.decryptionError("Invalid base64 in file key decryption")
        }

        do {
            return try openSecretBox(
                ciphertext: encryptedKeyData,
                nonce: nonceData,
                key: collectionKeyData,
            )
        } catch {
            throw CastError.decryptionError("SecretBox decryption failed for file key: \(error)")
        }
    }

    private func decryptMetadata(
        encryptedData: String, decryptionHeader: String,
        fileKey: Data
    ) throws -> Data {
        guard let encryptedBytes = Data(base64Encoded: encryptedData),
            let headerBytes = Data(base64Encoded: decryptionHeader)
        else {
            throw CastError.decryptionError("Invalid base64 in metadata decryption")
        }

        do {
            return try decryptSecretStream(
                encryptedData: encryptedBytes,
                header: headerBytes,
                key: fileKey,
            )
        } catch {
            throw
                CastError
                .decryptionError("XChaCha20-Poly1305 decryption failed for metadata: \(error)")
        }
    }

    private func parseFileMetadata(data: Data) throws -> FileMetadata {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CastError.decryptionError("Invalid JSON in decrypted metadata")
        }

        let fileType = json["fileType"] as? Int ?? 0
        let title = json["title"] as? String ?? "Unknown"
        let creationTime = json["creationTime"] as? Int64 ?? 0
        let modificationTime = json["modificationTime"] as? Int64 ?? 0
        let hash = json["hash"] as? String

        return FileMetadata(
            fileType: fileType,
            title: title,
            creationTime: creationTime,
            modificationTime: modificationTime,
            hash: hash,
        )
    }

    private func cleanupExpiredCache(validFileIDs: Set<Int>, castPayload: CastPayload) async {
        guard storedCastPayload == castPayload else { return }

        let cachedFileIDs = await fileCache.getCachedFileIDs()

        for cachedFileID in cachedFileIDs {
            guard storedCastPayload == castPayload else { return }
            if !validFileIDs.contains(cachedFileID) {
                await removeCachedFileContent(fileID: cachedFileID)
            }
        }
    }

    private func removeCachedFileContent(fileID: Int) async {
        await fileCache.remove(fileID)
    }

    func clearCache() async {
        await fileCache.clear()
    }
}
