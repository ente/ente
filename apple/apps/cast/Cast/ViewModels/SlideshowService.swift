import SwiftUI
import AVKit
import Foundation
import ZIPFoundation
import UIKit

@MainActor
class RealSlideshowService: ObservableObject {
    @Published var currentImageData: Data?
    @Published var currentVideoData: Data?
    @Published var currentVideoURL: URL?
    @Published var livePhotoVideoData: Data?
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
    private var prefetchCache: [Int: Data] = [:]
    private var videoTempFiles: [Int: URL] = [:]
    private let slideshowConfiguration = SlideConfiguration.tvOptimized
    private var slideTimeRemaining: TimeInterval = 0
    private var slidePauseTime: Date?
    private var slideStartTime: Date?
    
    private let fileCache = ThreadSafeFileCache(
        maxBytes: 4096 * 1024 * 1024,
        shrinkTargetBytes: 2048 * 1024 * 1024
    )
    
    private var didDisplayFirstFile: Bool = false
    
    private let baseURL = "https://api.ente.com"
    private let castDownloadURL = "https://cast-albums.ente.com/download"
    
    private let verboseFileLogging = false
    private let verboseDecryptionLogging = false
    
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
            if isPlaying && !isPaused {
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
        if isPlaying && !isPaused {
            startSlideTimer()
        }
    }
    
    func previousSlide() async {
        guard !allFiles.isEmpty else { return }
        currentFileIndex = currentFileIndex > 0 ? currentFileIndex - 1 : allFiles.count - 1
        await displaySlideAtCurrentIndex()
        if isPlaying && !isPaused {
            startSlideTimer()
        }
    }
    
    func start(castPayload: CastPayload) async {
        
        ScreenSaverManager.preventScreenSaver()
        
        await clearExpiredTokenState()
        storedCastPayload = castPayload
        await MainActor.run {
            if self.error != nil { self.error = nil }
        }
        
        do {
            
            await initializeFileList(castPayload: castPayload)
            
            let fileCount = await MainActor.run { allFiles.count }
            if fileCount == 0 {
                await MainActor.run {
                    self.error = "No media files available in this album"
                }
                return
            }
            
            print("Found \(fileCount) files total")
            
            let validFileIDs = Set(await MainActor.run { allFiles.map { $0.id } })
            await cleanupExpiredCache(validFileIDs: validFileIDs)
            
            await MainActor.run {
                self.totalSlides = fileCount
                self.currentFileIndex = 0
                self.currentSlideIndex = 0
                self.isPlaying = true
                self.isPaused = false
            }
            
            await displaySlideAtCurrentIndex()
            
            if fileCount == 1 {
                startSlideTimer()
            } else {
                startSlideTimer()
            }
            print("Enhanced slideshow started with \(fileCount) slide(s)")
            
        } catch {
            print("Failed to start slideshow: \(error)")
            await MainActor.run {
                self.error = "Failed to load slideshow: \(error.localizedDescription)"
            }
        }
    }
    
    func stop() async {
        
        ScreenSaverManager.allowScreenSaver()
        
        await MainActor.run {
            isStopping = true
            stopPeriodicDiffPolling()
        }
        
        // A late timer callback would surface a false empty state.
        slideTimer?.invalidate()
        slideTimer = nil

        await MainActor.run {
            currentFile = nil
            currentImageData = nil
            currentVideoData = nil
            currentVideoURL = nil
            livePhotoVideoData = nil
            error = nil
        }
        
        
        let stats = await getCacheStats()
        print("Final cache stats: \(stats.count) files, \(stats.totalSize) bytes")
        
        await MainActor.run {
            isStopping = false
        }
    }
    
    func clearExpiredTokenState() async {
        
        ScreenSaverManager.allowScreenSaver()
        
        await MainActor.run {
            // A late timer callback would surface a false empty state.
            slideTimer?.invalidate()
            slideTimer = nil
            storedCastPayload = nil
            lastUpdateTime = 0
            hasCompletedInitialFetch = false
            allFiles.removeAll()
            prefetchCache.removeAll()
            error = nil
            currentFile = nil
            currentImageData = nil
            currentVideoData = nil
            currentVideoURL = nil
            livePhotoVideoData = nil
        }
        // Preserve the cache across sessions.
    }
    
    @MainActor
    private func initializeFileList(castPayload: CastPayload) async {
        if hasCompletedInitialFetch && !allFiles.isEmpty {
            print("Using cached file list with \(allFiles.count) files")
            return
        }
        
        allFiles.removeAll()
        lastUpdateTime = 0
        currentFileIndex = 0
        hasCompletedInitialFetch = false
        
        do {
            try await fetchAllFiles(castPayload: castPayload)
            hasCompletedInitialFetch = true
            if !allFiles.isEmpty {
                allFiles.shuffle()
            }
            print("Initial diff fetch completed - \(allFiles.count) files cached (shuffled)")
        } catch {
            print("Failed to fetch files: \(error)")
            hasCompletedInitialFetch = false
            self.error = "Failed to load files: \(error.localizedDescription)"
        }
    }
    
    private func fetchAllFiles(castPayload: CastPayload) async throws {
        var hasMore = true
        var sinceTime = await MainActor.run { lastUpdateTime }
        
        while hasMore {
            if verboseFileLogging { print("Fetching files since time: \(sinceTime)") }
            let result = try await fetchFilesBatch(castPayload: castPayload, sinceTime: sinceTime)
            
            await processDiffBatch(result.files, collectionKey: castPayload.collectionKey)
            
            await MainActor.run {
                if result.latestUpdateTime > self.lastUpdateTime {
                    print("Initial fetch updating lastUpdateTime: \(self.lastUpdateTime) → \(result.latestUpdateTime)")
                    self.lastUpdateTime = result.latestUpdateTime
                }
            }
            
            hasMore = result.hasMore
            sinceTime = result.latestUpdateTime
            
        }
        
        print("Initial diff fetch complete - total files cached: \(await MainActor.run { allFiles.count })")
        
        await MainActor.run {
            startPeriodicDiffPolling()
        }
    }
    
    private func fetchFilesBatch(castPayload: CastPayload, sinceTime: Int64) async throws -> (files: [[String: Any]], hasMore: Bool, latestUpdateTime: Int64) {
        let url = URL(string: "\(baseURL)/cast/diff?sinceTime=\(sinceTime)")!
        
        
        var request = URLRequest(url: url)
        request.setValue(castPayload.castToken, forHTTPHeaderField: "X-Cast-Access-Token")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CastError.networkError("Invalid response")
        }
        
        
        if let responseString = String(data: data, encoding: .utf8) {
            
        }
        
        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 401 {
                await handleUnauthorizedError()
                throw CastError.serverError(401, "Authentication expired - resetting to pairing mode")
            }
            throw CastError.serverError(httpResponse.statusCode, String(data: data, encoding: .utf8))
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let diff = json["diff"] as? [[String: Any]] else {
            throw CastError.networkError("Invalid JSON response")
        }
        
        let hasMore = json["hasMore"] as? Bool ?? false
        
        var latestUpdateTime = sinceTime
        var foundAnyUpdates = false
        for item in diff {
            if let updateTime = item["updationTime"] as? Int64 {
                latestUpdateTime = max(latestUpdateTime, updateTime)
                foundAnyUpdates = true
            }
        }
        
        if !foundAnyUpdates {
            latestUpdateTime = sinceTime
        }
        
        
        
        return (files: diff, hasMore: hasMore, latestUpdateTime: latestUpdateTime)
    }
    
    @MainActor
    private func processDiffBatch(_ items: [[String: Any]], collectionKey: String) async {
        let wasEmpty = allFiles.isEmpty
        var currentFileChanged = false
        let originalCurrentFile = currentFileIndex < allFiles.count ? allFiles[currentFileIndex] : nil
        
        for item in items {
            guard let id = item["id"] as? Int else {
                continue
            }
            
            let isDeleted = item["isDeleted"] as? Bool ?? false
            
            if isDeleted {
                if let index = allFiles.firstIndex(where: { $0.id == id }) {
                    let removedFile = allFiles.remove(at: index)
                    print("Removed deleted file: \(removedFile.title) (ID: \(id))")
                    
                    if originalCurrentFile?.id == id {
                        currentFileWasDeleted = true
                        
                        Task {
                            await self.nextSlide()
                        }
                    }
                    
                    if index < currentFileIndex && currentFileIndex > 0 {
                        currentFileIndex -= 1
                    } else if index == currentFileIndex && currentFileIndex >= allFiles.count && !allFiles.isEmpty {
                        currentFileIndex = 0
                    }
                    
                    prefetchCache.removeValue(forKey: id)
                    await removeCachedFileContent(fileID: id)
                    
                } else {
                    print("Skipping deleted file \(id) (not in list)")
                }
            } else {
                do {
                    if let file = try await decryptFileMetadata(item: item, collectionKey: collectionKey) {
                        // Cast images and Live Photos, not standalone videos.
                        if file.isVideo && !file.isLivePhoto {
                            if verboseFileLogging { print("Skipping video file: \(file.title) (ID: \(id))") }
                            continue
                        }
                        if let existingIndex = allFiles.firstIndex(where: { $0.id == id }) {
                            let oldFile = allFiles[existingIndex]
                            allFiles[existingIndex] = file
                            print("Updated file: \(file.title) (ID: \(id))")
                            
                            if oldFile.hash != file.hash && file.hash != nil {
                                print("Hash changed for file \(id) - clearing cache")
                                prefetchCache.removeValue(forKey: id)
                                await removeCachedFileContent(fileID: id)
                            }
                            
                            if existingIndex == currentFileIndex {
                                currentFileChanged = true
                            }
                        } else {
                            allFiles.append(file)
                            print("Added file: \(file.title) (ID: \(id))")
                        }
                    }
                } catch {
                    print("Error processing file \(id): \(error)")
                }
            }
        }
        
        print("File list now contains \(allFiles.count) files")
        
        if allFiles.isEmpty {
            slideTimer?.invalidate()
            slideTimer = nil
            isPlaying = false
            isPaused = false
            currentImageData = nil
            currentVideoData = nil
            currentVideoURL = nil
            livePhotoVideoData = nil
            totalSlides = 0
            currentSlideIndex = 0
            currentFileIndex = 0
            error = "No media files available in this album"
        } else if wasEmpty {
            currentFileIndex = 0
            currentSlideIndex = 0
            totalSlides = allFiles.count
            
            if let payload = storedCastPayload {
                print("Restarting slideshow with \(allFiles.count) files")
                // Clear before loading to avoid an empty-state flash.
                error = nil
                
                Task {
                    await displaySlideAtCurrentIndex()
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
            
            if currentFileChanged && !allFiles.isEmpty {
                Task {
                    await displaySlideAtCurrentIndex()
                }
            }
        }
        
        let currentValidFileIDs = Set(allFiles.map { $0.id })
        Task {
            await cleanupExpiredCache(validFileIDs: currentValidFileIDs)
        }
    }
    
    private func displaySlideAtCurrentIndex() async {
        guard currentFileIndex >= 0, currentFileIndex < allFiles.count,
              let payload = storedCastPayload else { return }
        
        await MainActor.run {
            currentSlideIndex = currentFileIndex
            slideLoadingProgress = 0.0
        }
        
        if let cachedData = prefetchCache[currentFileIndex] {
            await updateCurrentSlide(with: cachedData, file: allFiles[currentFileIndex])
            await MainActor.run { slideLoadingProgress = 1.0 }
            return
        }
        
        do {
            let file = allFiles[currentFileIndex]
            print("Loading file \(file.id): \(file.title) at index \(currentFileIndex)")
            await MainActor.run { slideLoadingProgress = 0.5 }
            
            let decryptedData = try await downloadAndDecryptFileContent(
                castPayload: payload,
                file: file
            )
            
            print("Successfully loaded file \(file.id): \(file.title) (\(decryptedData.count) bytes)")
            
            prefetchCache[currentFileIndex] = decryptedData
            
            await updateCurrentSlide(with: decryptedData, file: file)
            await MainActor.run { slideLoadingProgress = 1.0 }
            
            startPrefetching()
            
        } catch {
            let file = allFiles[currentFileIndex]
            print("Failed to load file \(file.id): \(file.title) at index \(currentFileIndex) - \(error)")
            
            await MainActor.run {
                slideLoadingProgress = 0.0
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                Task {
                    await self.skipToNextSlide()
                }
            }
        }
    }
    
    @MainActor
    private func updateCurrentSlide(with data: Data, file: CastFile) {
        // Keep the old image until its replacement is ready.
        let wasEmpty = error == "No media files available in this album"
        error = nil
        currentFile = file
        
        if file.isLivePhoto {
            do {
                let components = try extractLivePhotoComponents(from: data)
                
                if let imageData = components.imageData {
                    currentImageData = imageData
                    print("Live photo image component loaded: \(imageData.count) bytes")
                } else {
                    currentImageData = data
                }
                
                if let videoData = components.videoData {
                    livePhotoVideoData = videoData
                    print("Live photo video component stored: \(videoData.count) bytes")
                } else {
                    livePhotoVideoData = nil
                }
                
                currentVideoData = nil
                currentVideoURL = nil
                
                startSlideTimer()
                
            } catch {
                print("Failed to extract live photo components: \(error)")
                currentImageData = data
                currentVideoData = nil
                currentVideoURL = nil
                livePhotoVideoData = nil
                startSlideTimer()
            }

        } else if file.isVideo {
            currentImageData = nil
            livePhotoVideoData = nil
            // A temp file preserves the color space and avoids brightness shifts.
            do {
                let url: URL
                if let existing = videoTempFiles[file.id] {
                    url = existing
                } else {
                    let fileExtension = file.title.components(separatedBy: ".").last?.lowercased() ?? "mp4"
                    let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("cast_video_\(file.id)_\(UUID().uuidString).\(fileExtension)")
                    try data.write(to: tmpURL, options: .atomic)
                    videoTempFiles[file.id] = tmpURL
                    url = tmpURL
                }
                currentVideoURL = url
                currentVideoData = nil
                prepareVideoPlayer(url: url)
            } catch {
                print("Failed to persist video temp file: \(error)")
                currentVideoURL = nil
            }
        } else {
            currentVideoData = nil
            currentVideoURL = nil
            livePhotoVideoData = nil
            // Assign the image last to avoid a black frame.
            currentImageData = data
            startSlideTimer()
        }
        error = nil
        
        if wasEmpty {
            NotificationCenter.default.post(name: .slideshowRestarted, object: nil)
        }
    }
    
    private func startSlideTimer(withDuration customDuration: TimeInterval? = nil) {
        guard let currentFile = currentFile else { return }
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
        
        slideTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, self.isPlaying, !self.isPaused else { return }
                self.slideTimeRemaining = 0
                self.slideStartTime = nil
                
                await self.nextSlide()
            }
        }
    }
    
    private func skipToNextSlide() async {
        guard !allFiles.isEmpty else { return }
        
        currentFileIndex = (currentFileIndex + 1) % allFiles.count
        
        let maxRetries = allFiles.count
        var retryCount = 0
        
        while retryCount < maxRetries {
            do {
                guard let payload = storedCastPayload else { return }
                let file = allFiles[currentFileIndex]
                
                print("Attempting to load file \(file.id): \(file.title) at index \(currentFileIndex)")
                
                let decryptedData = try await downloadAndDecryptFileContent(
                    castPayload: payload,
                    file: file
                )
                
                prefetchCache[currentFileIndex] = decryptedData
                await updateCurrentSlide(with: decryptedData, file: file)
                
                await MainActor.run {
                    currentSlideIndex = currentFileIndex
                    slideLoadingProgress = 1.0
                }
                
                print("Successfully loaded file \(file.id): \(file.title)")
                
                if isPlaying && !isPaused {
                    startSlideTimer()
                }
                
                startPrefetching()
                return
                
            } catch {
                let file = allFiles[currentFileIndex]
                print("Failed to load file \(file.id): \(file.title) - \(error)")
                currentFileIndex = (currentFileIndex + 1) % allFiles.count
                retryCount += 1
            }
        }
        
        await MainActor.run {
            self.error = "Unable to load any slides. All files may be corrupted or have decryption issues."
        }
    }
    
    private func startPrefetching() {
        Task {
            let prefetchCount = min(3, allFiles.count)
            for i in 1...prefetchCount {
                let prefetchIndex = (currentFileIndex + i) % allFiles.count
                
                if prefetchCache[prefetchIndex] != nil { continue }
                
                guard let payload = storedCastPayload else { continue }
                
                do {
                    let file = allFiles[prefetchIndex]
                    let data = try await downloadAndDecryptFileContent(
                        castPayload: payload,
                        file: file
                    )
                    prefetchCache[prefetchIndex] = data
                    
                    if prefetchCache.count > 5 {
                        let oldKeys = Array(prefetchCache.keys.sorted().prefix(prefetchCache.count - 5))
                        for key in oldKeys {
                            prefetchCache.removeValue(forKey: key)
                        }
                    }
                    
                } catch {
                    // Silently skip problematic files during prefetching
                    print("Prefetch failed for file \(prefetchIndex), will try on-demand")
                    continue
                }
                
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }
    
    private func prepareVideoPlayer(url: URL) {
        let playerItem = AVPlayerItem(url: url)
        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: playerItem, queue: .main) { [weak self] _ in
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
    
    private func startVideoProgressUpdates() {
        videoPlayer?.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self = self else { return }
                self.videoCurrentTime = CMTimeGetSeconds(time)
                if let duration = self.videoPlayer?.currentItem?.duration.seconds, duration.isFinite { 
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
        guard isPeriodicPollingEnabled && storedCastPayload != nil else { return }
        
        stopPeriodicDiffPolling()
        
        print("Starting periodic diff polling (every \(diffPollingInterval)s)")
        
        diffPollingTimer = Timer.scheduledTimer(withTimeInterval: diffPollingInterval, repeats: true) { [weak self] _ in
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
        
        guard let payload = payload, isEnabled else { return }
        
        do {
            let currentTime = await MainActor.run { lastUpdateTime }
            let result = try await fetchFilesBatch(castPayload: payload, sinceTime: currentTime)
            
            if !result.files.isEmpty {
                print("Periodic poll found \(result.files.count) changes")
                
                await processDiffBatch(result.files, collectionKey: payload.collectionKey)
                
                await MainActor.run {
                    if result.latestUpdateTime > self.lastUpdateTime {
                        print("Updating lastUpdateTime: \(self.lastUpdateTime) → \(result.latestUpdateTime)")
                        self.lastUpdateTime = result.latestUpdateTime
                    }
                }
            } else {
                print("Periodic poll found no changes since \(currentTime)")
            }
            
        } catch {
            if let castError = error as? CastError,
               case .serverError(401, _) = castError {
                // fetchFilesBatch already handled this error.
            } else {
                print("Periodic diff check failed: \(error)")
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
    
    private func downloadEncryptedFile(castPayload: CastPayload, fileID: Int) async throws -> Data {
        let url = URL(string: "\(castDownloadURL)/?fileID=\(fileID)")!
        
        var request = URLRequest(url: url)
        request.setValue(castPayload.castToken, forHTTPHeaderField: "X-Cast-Access-Token")
        
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CastError.networkError("Invalid response")
        }
        
        guard httpResponse.statusCode == 200 else {
            let snippet = (String(data: data, encoding: .utf8) ?? "").prefix(160)
            print("Download error [\(httpResponse.statusCode)] fileID=\(fileID): \(snippet)")
            if httpResponse.statusCode == 401 {
                await handleUnauthorizedError()
                throw CastError.serverError(401, "Authentication expired - resetting to pairing mode")
            } else {
                throw CastError.serverError(httpResponse.statusCode, String(snippet))
            }
        }
        if verboseFileLogging { print("Successfully downloaded \(data.count) bytes for file \(fileID)") }
        return data
    }
    
    private func downloadAndDecryptFileContent(castPayload: CastPayload, file: CastFile) async throws -> Data {
        let stopping = await MainActor.run { isStopping }
        if stopping {
            throw CastError.networkError("Service is stopping")
        }
        
        if let cachedData = await getCachedFileContent(fileID: file.id) {
            if verboseFileLogging { print("Using cached content for file \(file.id): \(file.title) (\(cachedData.count) bytes)") }
            return cachedData
        }
        
            if verboseFileLogging { print("Downloading and decrypting file \(file.id): \(file.title)") }
        
        let encryptedData = try await downloadEncryptedFile(castPayload: castPayload, fileID: file.id)
            if verboseFileLogging { print("Downloaded \(encryptedData.count) bytes") }
        
        let fileKey = try decryptFileKey(
            encryptedKey: file.encryptedKey,
            nonce: file.keyDecryptionNonce,
            collectionKey: castPayload.collectionKey
        )
            
        
        let decryptedData = try decryptFileContent(
            encryptedData: encryptedData,
            fileKey: fileKey,
            decryptionHeader: file.fileDecryptionHeader
        )
            
        
        await cacheFileContent(fileID: file.id, data: decryptedData)
        
        return decryptedData
    }
    
    private func decryptFileMetadata(item: [String: Any], collectionKey: String) async throws -> CastFile? {
        guard let id = item["id"] as? Int,
              let encryptedKey = item["encryptedKey"] as? String,
              let keyDecryptionNonce = item["keyDecryptionNonce"] as? String,
              let metadataDict = item["metadata"] as? [String: Any],
              let encryptedMetadata = metadataDict["encryptedData"] as? String,
              let metadataHeader = metadataDict["decryptionHeader"] as? String,
              let fileDict = item["file"] as? [String: Any],
              let fileDecryptionHeader = fileDict["decryptionHeader"] as? String else {
            print("Missing required fields for file \(item["id"] ?? "unknown")")
            return nil
        }
        
        do {
            let fileKey = try decryptFileKey(
                encryptedKey: encryptedKey,
                nonce: keyDecryptionNonce,
                collectionKey: collectionKey
            )
            if verboseDecryptionLogging { print("File key decrypted successfully") }
            
            let metadata = try decryptMetadata(
                encryptedData: encryptedMetadata,
                decryptionHeader: metadataHeader,
                fileKey: fileKey
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
                hash: fileMetadata.hash
            )
            
        } catch {
            print("Decryption failed: \(error)")
            throw error
        }
    }
    
    private func decryptFileKey(encryptedKey: String, nonce: String, collectionKey: String) throws -> Data {
        guard let encryptedKeyData = Data(base64Encoded: encryptedKey),
              let nonceData = Data(base64Encoded: nonce),
              let collectionKeyData = Data(base64Encoded: collectionKey) else {
            throw CastError.decryptionError("Invalid base64 in file key decryption")
        }
        
        do {
            let decryptedFileKey = try openSecretBox(ciphertext: encryptedKeyData, nonce: nonceData, key: collectionKeyData)
            return decryptedFileKey
        } catch {
            throw CastError.decryptionError("SecretBox decryption failed for file key: \(error)")
        }
    }
    
    private func decryptMetadata(encryptedData: String, decryptionHeader: String, fileKey: Data) throws -> Data {
        guard let encryptedBytes = Data(base64Encoded: encryptedData),
              let headerBytes = Data(base64Encoded: decryptionHeader) else {
            throw CastError.decryptionError("Invalid base64 in metadata decryption")
        }
        
        print("XChaCha20: encrypted=\(encryptedBytes.count)b, header=\(headerBytes.count)b, key=\(fileKey.count)b")
        
        do {
            let decryptedData = try decryptSecretStream(encryptedData: encryptedBytes, header: headerBytes, key: fileKey)
            print("Metadata decrypted using Rust crypto: \(decryptedData.count) bytes")
            return decryptedData
        } catch {
            throw CastError.decryptionError("XChaCha20-Poly1305 decryption failed for metadata: \(error)")
        }
    }
    
    private func decryptFileContent(encryptedData: Data, fileKey: Data, decryptionHeader: String) throws -> Data {
        guard let headerBytes = Data(base64Encoded: decryptionHeader) else {
            throw CastError.decryptionError("Invalid base64 in file decryption header")
        }
        
    if verboseDecryptionLogging { print("File decryption: encrypted=\(encryptedData.count)b, header=\(headerBytes.count)b, key=\(fileKey.count)b") }
        
        do {
            return try decryptSecretStream(encryptedData: encryptedData, header: headerBytes, key: fileKey)
        } catch {
            throw CastError.decryptionError("file content decryption failed: \(error)")
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
            hash: hash
        )
    }
    
    private func getCachedFileContent(fileID: Int) async -> Data? {
        return await fileCache.get(fileID)
    }
    
    private func cacheFileContent(fileID: Int, data: Data) async {
        await fileCache.set(fileID, data: data)
    }
    
    private func cleanupExpiredCache(validFileIDs: Set<Int>) async {
        let stats = await getCacheStats()
        print("Starting cache cleanup - current cache has \(stats.count) files")
        
        let cachedFileIDs = await fileCache.getCachedFileIDs()
        
        var removedCount = 0
        for cachedFileID in cachedFileIDs {
            if !validFileIDs.contains(cachedFileID) {
                await removeCachedFileContent(fileID: cachedFileID)
                removedCount += 1
            }
        }
        
        if removedCount > 0 {
            let newStats = await getCacheStats()
            print("Cache cleanup complete - removed \(removedCount) expired files, now \(newStats.count) files (\(newStats.totalSize) bytes)")
        }
    }
    
    private func removeCachedFileContent(fileID: Int) async {
        await fileCache.remove(fileID)
    }
    
    private func clearCache() async {
        await fileCache.clear()
    }
    
    private func getCacheStats() async -> (count: Int, totalSize: Int) {
        return await fileCache.getStats()
    }
}

func extractZipUsingFoundation(zipURL: URL, to destinationURL: URL) throws {
    do {
        try FileManager.default.unzipItem(at: zipURL, to: destinationURL)
    } catch {
        throw CastError.decryptionError("ZipFoundation extraction failed: \(error)")
    }
}

func extractLivePhotoComponents(from zipData: Data) throws -> LivePhotoComponents {
    let tempDirectory = FileManager.default.temporaryDirectory
    let zipURL = tempDirectory.appendingPathComponent("livephoto_\(UUID().uuidString).zip")
    let extractDirectory = tempDirectory.appendingPathComponent("livephoto_extract_\(UUID().uuidString)")
    
    defer {
        try? FileManager.default.removeItem(at: zipURL)
        try? FileManager.default.removeItem(at: extractDirectory)
    }
    
    try zipData.write(to: zipURL)
    try FileManager.default.createDirectory(at: extractDirectory, withIntermediateDirectories: true)
    
    var imageData: Data?
    var videoData: Data?
    var imagePath: URL?
    var videoPath: URL?
    
    do {
        try extractZipUsingFoundation(zipURL: zipURL, to: extractDirectory)
        
        // Live Photo zips may nest their assets.
        let resourceKeys: [URLResourceKey] = [.isDirectoryKey]
        let enumerator = FileManager.default.enumerator(at: extractDirectory, includingPropertiesForKeys: resourceKeys)
        
        func isLikelyImage(_ url: URL) -> Bool {
            let ext = url.pathExtension.lowercased()
            return ["jpg", "jpeg", "png", "heic", "heif"].contains(ext)
        }
        
        func isLikelyVideo(_ url: URL) -> Bool {
            let ext = url.pathExtension.lowercased()
            return ["mov", "mp4", "m4v", "hevc"].contains(ext)
        }
        
    while let fileURL = enumerator?.nextObject() as? URL {
            if (try? fileURL.resourceValues(forKeys: Set(resourceKeys)).isDirectory) == true { continue }
            let filename = fileURL.lastPathComponent
            
            if imageData == nil && isLikelyImage(fileURL) {
                imageData = try Data(contentsOf: fileURL)
                imagePath = fileURL
                print("Extracted live photo image: \(filename) (\(imageData?.count ?? 0) bytes)")
            } else if videoData == nil && isLikelyVideo(fileURL) {
                videoData = try Data(contentsOf: fileURL)
                videoPath = fileURL
                print("Extracted live photo video: \(filename) (\(videoData?.count ?? 0) bytes)")
            } else {
                if imageData == nil || videoData == nil {
                    print("Ignoring non-component file in live photo zip: \(filename)")
                }
            }
        }
        
        // Some packages use extensionless or generic asset names.
        if imageData == nil || videoData == nil {
            let contents = try FileManager.default.contentsOfDirectory(at: extractDirectory, includingPropertiesForKeys: nil)
            if imageData == nil {
                if let guessImage = contents.first(where: { $0.pathExtension.isEmpty }) {
                    imageData = try? Data(contentsOf: guessImage)
                    imagePath = guessImage
                    if imageData != nil { print("Heuristic image pick: \(guessImage.lastPathComponent)") }
                }
            }
            if videoData == nil {
                if let guessVideo = contents.first(where: { ["bin", "dat"].contains($0.pathExtension.lowercased()) }) {
                    videoData = try? Data(contentsOf: guessVideo)
                    videoPath = guessVideo
                    if videoData != nil { print("Heuristic video pick: \(guessVideo.lastPathComponent)") }
                }
            }
        }
        
        if imageData == nil && videoData == nil {
            throw CastError.decryptionError("No valid image or video components found in live photo zip")
        }
        
        return LivePhotoComponents(
            imageData: imageData,
            videoData: videoData,
            imagePath: imagePath,
            videoPath: videoPath
        )
        
    } catch {
        print("Failed to extract live photo components: \(error)")
        throw CastError.decryptionError("Failed to extract live photo zip: \(error)")
    }
}
