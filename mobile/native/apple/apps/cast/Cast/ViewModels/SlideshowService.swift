import SwiftUI
import AVKit
import Foundation
import ZIPFoundation
import UIKit

@MainActor
class RealSlideshowService: ObservableObject {
    // MARK: - Published Properties
    @Published var currentImageData: Data?
    @Published var currentVideoData: Data? // Deprecated path (kept for compatibility)
    @Published var currentVideoURL: URL? // Temp file URL for AVPlayer playback
    @Published var livePhotoVideoData: Data? // Video component for live photos
    @Published var videoPlayer: AVPlayer?
    @Published var isVideoPlaying: Bool = false
    @Published var videoCurrentTime: Double = 0
    @Published var videoDuration: Double = 0
    @Published var currentFile: CastFile?
    @Published var error: String?
    
    // Enhanced state management
    @Published var isPlaying: Bool = false
    @Published var isPaused: Bool = false
    @Published var slideLoadingProgress: Double = 0.0
    @Published var currentSlideIndex: Int = 0
    @Published var totalSlides: Int = 0
    
    // MARK: - Private Properties
    
    // Global file list management
    private var allFiles: [CastFile] = []
    private var currentFileIndex: Int = 0
    private var lastUpdateTime: Int64 = 0
    private var isLoadingMore: Bool = false
    private var hasCompletedInitialFetch: Bool = false
    private var storedCastPayload: CastPayload?
    
    // Periodic diff polling
    private var diffPollingTimer: Timer?
    private let diffPollingInterval: TimeInterval = 5.0  // 5 seconds
    private var isPeriodicPollingEnabled: Bool = true
    private var currentFileWasDeleted: Bool = false
    private var isStopping: Bool = false  // Flag to indicate service is being stopped
    
    // Enhanced slideshow features
    private var slideTimer: Timer?
    private var prefetchCache: [Int: Data] = [:]
    private var videoTempFiles: [Int: URL] = [:]
    private let slideshowConfiguration = SlideConfiguration.tvOptimized
    private var slideTimeRemaining: TimeInterval = 0
    private var slidePauseTime: Date?
    private var slideStartTime: Date?
    
    // File content caching - prevent redundant downloads
    private let fileCache = ThreadSafeFileCache(
        maxBytes: 4096 * 1024 * 1024, // 4GB
        shrinkTargetBytes: 2048 * 1024 * 1024 // 2GB
    )
    
    // Simplified mode: only load first file (no slideshow navigation)
    private var didDisplayFirstFile: Bool = false
    
    private let baseURL = "https://api.ente.com"
    private let castDownloadURL = "https://cast-albums.ente.com/download"
    
    // Configuration Flags
    private let verboseFileLogging = false          // Reduces per-file spam unless true
    private let verboseDecryptionLogging = false    // Detailed size/key logs
    
    // 401 Error Handling
    private var isHandlingAuthExpiry: Bool = false
    
    // MARK: - Slideshow Controls
    
    func pause() {
        slideTimer?.invalidate()
        slideTimer = nil
        isPlaying = false
        isPaused = true
        
        // Calculate remaining time when pausing
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
        
        // Resume with remaining time if we have it, otherwise start fresh
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
        // If we no longer have an active payload (e.g. after auth expiry reset) just ignore any stray timer fires
        guard storedCastPayload != nil else { return }
        guard !allFiles.isEmpty else {
            // Only surface empty-state error if we're in an active slideshow session (payload present)
            await MainActor.run {
                self.error = "No media files available in this album"
            }
            return
        }
        
        // For single photo, just restart the timer without changing index
        if allFiles.count == 1 {
            if isPlaying && !isPaused {
                startSlideTimer()
            }
            return
        }
        
        // Check if current file was deleted and handle accordingly
        if currentFileWasDeleted {
            currentFileWasDeleted = false
            // Current index already adjusted in processDiffBatch
            if currentFileIndex >= allFiles.count {
                currentFileIndex = 0
            }
        } else {
            // Normal progression to next slide
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
    
    // MARK: - Main Entry Points
    
    func start(castPayload: CastPayload) async {
        
        // Enable screen saver prevention for slideshow
        ScreenSaverManager.preventScreenSaver()
        
        // Clear any expired state first, then store new payload
        await clearExpiredTokenState()
        storedCastPayload = castPayload
        await MainActor.run {
            // Don't blindly nuke existing UI state until we actually know file list status
            // Just mark as loading; CastViewModel controls high-level view transitions.
            if self.error != nil { self.error = nil }
        }
        
        do {
            
            // Initialize file list and fetch all files with pagination
            await initializeFileList(castPayload: castPayload)
            
            let fileCount = await MainActor.run { allFiles.count }
            if fileCount == 0 {
                await MainActor.run {
                    self.error = "No media files available in this album"
                }
                return
            }
            
            print("Found \(fileCount) files total")
            
            // Clean up cache for files no longer in the collection
            let validFileIDs = Set(await MainActor.run { allFiles.map { $0.id } })
            await cleanupExpiredCache(validFileIDs: validFileIDs)
            
            await MainActor.run {
                self.totalSlides = fileCount
                self.currentFileIndex = 0
                self.currentSlideIndex = 0
                self.isPlaying = true
                self.isPaused = false
            }
            
            // Display first file and start slideshow
            await displaySlideAtCurrentIndex()
            
            // For single photo, ensure timer is started even if it's an image
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
        
        // Disable screen saver prevention when stopping slideshow
        ScreenSaverManager.allowScreenSaver()
        
        // Set stopping flag to cancel ongoing operations
        await MainActor.run {
            isStopping = true
            stopPeriodicDiffPolling()
        }
        
    // Invalidate slide timer to avoid post-reset nextSlide() firing that could trigger false empty-state UI
    slideTimer?.invalidate()
    slideTimer = nil

    // Clear navigation state
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
        
        // Reset stopping flag for next session
        await MainActor.run {
            isStopping = false
        }
    }
    
    func clearExpiredTokenState() async {
        
        // Ensure screen saver prevention is disabled when clearing expired state
        ScreenSaverManager.allowScreenSaver()
        
        await MainActor.run {
            // Ensure any existing slide timer from previous session is cancelled to prevent spurious empty-state errors
            slideTimer?.invalidate()
            slideTimer = nil
            storedCastPayload = nil
            lastUpdateTime = 0
            hasCompletedInitialFetch = false
            allFiles.removeAll()
            prefetchCache.removeAll()
            // Clear any error state that might trigger empty view
            error = nil
            currentFile = nil
            currentImageData = nil
            currentVideoData = nil
            currentVideoURL = nil
            livePhotoVideoData = nil
        }
        // Don't clear cache automatically - preserve across sessions
    }
    
    // MARK: - File List Management
    
    @MainActor
    private func initializeFileList(castPayload: CastPayload) async {
        // Check if we've already completed the initial fetch
        if hasCompletedInitialFetch && !allFiles.isEmpty {
            print("Using cached file list with \(allFiles.count) files")
            return
        }
        
        // Reset state for fresh fetch
        allFiles.removeAll()
        lastUpdateTime = 0
        currentFileIndex = 0
        hasCompletedInitialFetch = false
        
        // Fetch all pages until hasMore is false
        do {
            try await fetchAllFiles(castPayload: castPayload)
            // Mark as completed only after successfully fetching all pages
            hasCompletedInitialFetch = true
            // Shuffle order to randomize slideshow similar to web experience
            if !allFiles.isEmpty {
                allFiles.shuffle()
            }
            print("Initial diff fetch completed - \(allFiles.count) files cached (shuffled)")
        } catch {
            print("Failed to fetch files: \(error)")
            hasCompletedInitialFetch = false // Ensure we retry on next attempt
            self.error = "Failed to load files: \(error.localizedDescription)"
        }
    }
    
    private func fetchAllFiles(castPayload: CastPayload) async throws {
        var hasMore = true
        var sinceTime = await MainActor.run { lastUpdateTime }
        
        while hasMore {
            if verboseFileLogging { print("Fetching files since time: \(sinceTime)") }
            let result = try await fetchFilesBatch(castPayload: castPayload, sinceTime: sinceTime)
            
            // Process the batch on MainActor
            await processDiffBatch(result.files, collectionKey: castPayload.collectionKey)
            
            // Update pagination state on MainActor
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
        
        // Start periodic polling after initial fetch completes
        await MainActor.run {
            startPeriodicDiffPolling()
        }
    }
    
    private func fetchFilesBatch(castPayload: CastPayload, sinceTime: Int64) async throws -> (files: [[String: Any]], hasMore: Bool, latestUpdateTime: Int64) {
        let url = URL(string: "\(baseURL)/cast/diff?collectionID=\(castPayload.collectionID)&sinceTime=\(sinceTime)")!
        
        
        var request = URLRequest(url: url)
        request.setValue(castPayload.castToken, forHTTPHeaderField: "X-Cast-Access-Token")
        // Include collection key in headers for server-side decryption if needed
        request.setValue(castPayload.collectionKey, forHTTPHeaderField: "X-Collection-Key")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CastError.networkError("Invalid response")
        }
        
        
        if let responseString = String(data: data, encoding: .utf8) {
            
        }
        
        guard httpResponse.statusCode == 200 else {
            // Handle 401 specially - this means token expired, need to reset to pairing
            if httpResponse.statusCode == 401 {
                await handleUnauthorizedError()
                throw CastError.serverError(401, "Authentication expired - resetting to pairing mode")
            }
            throw CastError.serverError(httpResponse.statusCode, String(data: data, encoding: .utf8))
        }
        
        // Parse the diff response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let diff = json["diff"] as? [[String: Any]] else {
            throw CastError.networkError("Invalid JSON response")
        }
        
        let hasMore = json["hasMore"] as? Bool ?? false
        
        // Find the latest update time from this batch
        var latestUpdateTime = sinceTime
        var foundAnyUpdates = false
        for item in diff {
            if let updateTime = item["updationTime"] as? Int64 {
                latestUpdateTime = max(latestUpdateTime, updateTime)
                foundAnyUpdates = true
            }
        }
        
        // If no items had updationTime, keep the original sinceTime
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
                // Remove file from list if it exists
                if let index = allFiles.firstIndex(where: { $0.id == id }) {
                    let removedFile = allFiles.remove(at: index)
                    print("Removed deleted file: \(removedFile.title) (ID: \(id))")
                    
                    // Check if deleted file was the currently playing one
                    if originalCurrentFile?.id == id {
                        currentFileWasDeleted = true
                        
                        // Immediately move to next slide if current was deleted
                        Task {
                            await self.nextSlide()
                        }
                    }
                    
                    // Adjust current index if necessary
                    if index < currentFileIndex && currentFileIndex > 0 {
                        currentFileIndex -= 1
                    } else if index == currentFileIndex && currentFileIndex >= allFiles.count && !allFiles.isEmpty {
                        currentFileIndex = 0 // Wrap around to beginning
                    }
                    
                    prefetchCache.removeValue(forKey: id)
                    await removeCachedFileContent(fileID: id)
                    
                } else {
                    print("Skipping deleted file \(id) (not in list)")
                }
            } else {
                // Add or update file
                do {
                    // Only decrypt metadata here, not file content
                    if let file = try await decryptFileMetadata(item: item, collectionKey: collectionKey) {
                        // Skip pure videos (we only want images + live photos)
                        if file.isVideo && !file.isLivePhoto {
                            if verboseFileLogging { print("Skipping video file: \(file.title) (ID: \(id))") }
                            continue
                        }
                        // Check if file already exists
                        if let existingIndex = allFiles.firstIndex(where: { $0.id == id }) {
                            let oldFile = allFiles[existingIndex]
                            allFiles[existingIndex] = file
                            print("Updated file: \(file.title) (ID: \(id))")
                            
                            // Check if hash changed - clear cache if so
                            if oldFile.hash != file.hash && file.hash != nil {
                                print("Hash changed for file \(id) - clearing cache")
                                prefetchCache.removeValue(forKey: id)
                                await removeCachedFileContent(fileID: id)
                            }
                            
                            // Track if current file was modified
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
        
        // Handle state transitions
        if allFiles.isEmpty {
            // Transition to empty state
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
            // Transition from empty to having files
            currentFileIndex = 0
            currentSlideIndex = 0
            totalSlides = allFiles.count
            
            // Restart slideshow if we have a stored payload
            if let payload = storedCastPayload {
                print("Restarting slideshow with \(allFiles.count) files")
                error = nil // Clear error first to avoid UI flicker
                
                // Display first slide and start slideshow
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
            // Normal update - just update count
            totalSlides = allFiles.count
            
            // Ensure current index is valid
            if currentFileIndex >= allFiles.count {
                currentFileIndex = 0
            }
            
            // If current file was modified, reload it
            if currentFileChanged && !allFiles.isEmpty {
                Task {
                    await displaySlideAtCurrentIndex()
                }
            }
        }
        
        // Clean up expired cache entries after processing batch
        let currentValidFileIDs = Set(allFiles.map { $0.id })
        Task {
            await cleanupExpiredCache(validFileIDs: currentValidFileIDs)
        }
    }
    
    // MARK: - Slide Display & Navigation
    
    private func displaySlideAtCurrentIndex() async {
        guard currentFileIndex >= 0, currentFileIndex < allFiles.count,
              let payload = storedCastPayload else { return }
        
        await MainActor.run {
            currentSlideIndex = currentFileIndex
            slideLoadingProgress = 0.0
        }
        
        // Check cache first
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
            
            // Start prefetching next few slides
            startPrefetching()
            
        } catch {
            let file = allFiles[currentFileIndex]
            print("Failed to load file \(file.id): \(file.title) at index \(currentFileIndex) - \(error)")
            
            // Auto-skip problematic files and continue slideshow
            await MainActor.run {
                slideLoadingProgress = 0.0
            }
            
            // Try next slide automatically after a brief delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                Task {
                    await self.skipToNextSlide()
                }
            }
        }
    }
    
    @MainActor
    private func updateCurrentSlide(with data: Data, file: CastFile) {
    // Seamless transition: don't nuke existing image until replacement assigned
    let wasEmpty = error == "No media files available in this album"
    error = nil
    currentFile = file
        
        if file.isLivePhoto {
            // Handle live photo: extract image component only, store video separately
            do {
                let components = try extractLivePhotoComponents(from: data)
                
                // For live photos, only set the image component for display
                if let imageData = components.imageData {
                    currentImageData = imageData
                    print("Live photo image component loaded: \(imageData.count) bytes")
                } else {
                    currentImageData = data
                }
                
                // Store video component separately for long-press playback
                if let videoData = components.videoData {
                    livePhotoVideoData = videoData
                    print("Live photo video component stored: \(videoData.count) bytes")
                } else {
                    livePhotoVideoData = nil
                }
                
                // Clear video properties to ensure image display
                currentVideoData = nil
                currentVideoURL = nil
                
                // Start timer for live photo (show as image)
                startSlideTimer()
                
            } catch {
                print("Failed to extract live photo components: \(error)")
                // Fallback to treating as regular image
                currentImageData = data
                currentVideoData = nil
                currentVideoURL = nil
                livePhotoVideoData = nil
                startSlideTimer()
            }
            
        } else if file.isVideo {
            // Switching to video: clear image state now
            currentImageData = nil
            livePhotoVideoData = nil
            // Write decrypted data to a temp file to preserve original color space & avoid brightness shifts
            do {
                let url: URL
                if let existing = videoTempFiles[file.id] {
                    url = existing
                } else {
                    // Extract proper file extension from filename
                    let fileExtension = file.title.components(separatedBy: ".").last?.lowercased() ?? "mp4"
                    let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("cast_video_\(file.id)_\(UUID().uuidString).\(fileExtension)")
                    try data.write(to: tmpURL, options: .atomic)
                    videoTempFiles[file.id] = tmpURL
                    url = tmpURL
                }
                currentVideoURL = url
                currentVideoData = nil // release raw data memory
                prepareVideoPlayer(url: url)
            } catch {
                print("Failed to persist video temp file: \(error)")
                currentVideoURL = nil
            }
        } else {
            // Regular image
            currentVideoData = nil
            currentVideoURL = nil
            livePhotoVideoData = nil
            currentImageData = data // assign image last for minimal black gap
            // Start timer for image slide immediately
            startSlideTimer()
        }
        error = nil
        
        // If we just transitioned from empty to having content, notify the UI
        if wasEmpty {
            NotificationCenter.default.post(name: .slideshowRestarted, object: nil)
        }
    }
    
    private func startSlideTimer(withDuration customDuration: TimeInterval? = nil) {
        guard let currentFile = currentFile else { return }
        // For video slides we rely on actual playback end rather than a fixed timer
        if currentFile.isVideo { 
            slideTimeRemaining = 0
            slideStartTime = nil
            return 
        }
        
        slideTimer?.invalidate()
        let duration = customDuration ?? slideshowConfiguration.duration(for: currentFile)
        slideStartTime = Date()
        slideTimeRemaining = duration
        
        // For single photo albums, we still want the timer to fire to maintain the slideshow loop
        slideTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, self.isPlaying, !self.isPaused else { return }
                self.slideTimeRemaining = 0
                self.slideStartTime = nil
                
                // For single photos, nextSlide will just restart the timer
                await self.nextSlide()
            }
        }
    }
    
    private func skipToNextSlide() async {
        guard !allFiles.isEmpty else { return }
        
        currentFileIndex = (currentFileIndex + 1) % allFiles.count
        
        // If we've gone through all files and still have errors, stop the slideshow
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
                
                // Success! Update the slide
                prefetchCache[currentFileIndex] = decryptedData
                await updateCurrentSlide(with: decryptedData, file: file)
                
                await MainActor.run {
                    currentSlideIndex = currentFileIndex
                    slideLoadingProgress = 1.0
                }
                
                print("Successfully loaded file \(file.id): \(file.title)")
                
                // Restart timer if playing
                if isPlaying && !isPaused {
                    startSlideTimer()
                }
                
                // Start prefetching again
                startPrefetching()
                return
                
            } catch {
                let file = allFiles[currentFileIndex]
                print("Failed to load file \(file.id): \(file.title) - \(error)")
                currentFileIndex = (currentFileIndex + 1) % allFiles.count
                retryCount += 1
            }
        }
        
        // If we reach here, all files have issues
        await MainActor.run {
            self.error = "Unable to load any slides. All files may be corrupted or have decryption issues."
        }
    }
    
    private func startPrefetching() {
        Task {
            let prefetchCount = min(3, allFiles.count)
            for i in 1...prefetchCount {
                let prefetchIndex = (currentFileIndex + i) % allFiles.count
                
                // Skip if already cached
                if prefetchCache[prefetchIndex] != nil { continue }
                
                guard let payload = storedCastPayload else { continue }
                
                do {
                    let file = allFiles[prefetchIndex]
                    let data = try await downloadAndDecryptFileContent(
                        castPayload: payload,
                        file: file
                    )
                    prefetchCache[prefetchIndex] = data
                    
                    // Clean up old cache entries
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
                
                // Add delay between prefetch operations
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            }
        }
    }
    
    // MARK: - Video Playback Management
    
    private func prepareVideoPlayer(url: URL) {
        let playerItem = AVPlayerItem(url: url)
        // Observe duration once ready
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
        // Get duration asynchronously for iOS 16+
        Task { @MainActor in
            if let duration = try? await playerItem.asset.load(.duration) {
                self.videoDuration = CMTimeGetSeconds(duration)
            }
        }
        // Auto-play
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
        // Ensure slideshow timer paused during video playback
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
    
    // MARK: - Periodic Diff Polling
    
    @MainActor
    private func startPeriodicDiffPolling() {
        guard isPeriodicPollingEnabled && storedCastPayload != nil else { return }
        
        stopPeriodicDiffPolling() // Stop any existing timer
        
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
                
                // Only update lastUpdateTime if we actually found items with valid updationTime
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
                // handleUnauthorizedError already called in fetchFilesBatch
            } else {
                print("Periodic diff check failed: \(error)")
                // Continue polling on other errors
            }
        }
    }
    
    // MARK: - 401 Error Handling
    
    @MainActor
    private func handleUnauthorizedError() {
        // Prevent multiple concurrent auth expiry handling
        guard !isHandlingAuthExpiry else {
            return
        }
        
        isHandlingAuthExpiry = true
        
        // Stop screen saver prevention immediately before any UI transitions
        ScreenSaverManager.allowScreenSaver()
        
        // Stop all ongoing operations
        isPeriodicPollingEnabled = false
        stopPeriodicDiffPolling()
        
        // Notify the view model to reset session
        NotificationCenter.default.post(name: .authenticationExpired, object: nil)
        
        // Reset flag after a delay to allow reset to complete
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            await MainActor.run {
                self.isHandlingAuthExpiry = false
            }
        }
    }
    
    // MARK: - Network & Download

    private func downloadEncryptedFile(castPayload: CastPayload, fileID: Int) async throws -> Data {
        // Use the file download endpoint with cast-specific headers
        let url = URL(string: "\(castDownloadURL)/?fileID=\(fileID)")!
        
        var request = URLRequest(url: url)
        // Use cast-specific headers like in the diff endpoint
        request.setValue(castPayload.castToken, forHTTPHeaderField: "X-Cast-Access-Token")
        request.setValue(castPayload.collectionKey, forHTTPHeaderField: "X-Collection-Key")
        
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CastError.networkError("Invalid response")
        }
        
        guard httpResponse.statusCode == 200 else {
            // Condensed error log
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
        // Check if service is stopping
        let stopping = await MainActor.run { isStopping }
        if stopping {
            throw CastError.networkError("Service is stopping")
        }
        
        // Check cache first
        if let cachedData = await getCachedFileContent(fileID: file.id) {
            if verboseFileLogging { print("Using cached content for file \(file.id): \(file.title) (\(cachedData.count) bytes)") }
            return cachedData
        }
        
            if verboseFileLogging { print("Downloading and decrypting file \(file.id): \(file.title)") }
        
        // Step 1: Download encrypted file
        let encryptedData = try await downloadEncryptedFile(castPayload: castPayload, fileID: file.id)
            if verboseFileLogging { print("Downloaded \(encryptedData.count) bytes") }
        
        // Step 2: Decrypt file key using collection key
        let fileKey = try decryptFileKey(
            encryptedKey: file.encryptedKey,
            nonce: file.keyDecryptionNonce,
            collectionKey: castPayload.collectionKey
        )
            
        
        // Step 3: Decrypt file content using file key and decryption header
        let decryptedData = try decryptFileContent(
            encryptedData: encryptedData,
            fileKey: fileKey,
            decryptionHeader: file.fileDecryptionHeader
        )
            
        
        // Step 4: Cache the decrypted content
        await cacheFileContent(fileID: file.id, data: decryptedData)
        
        return decryptedData
    }
    
    // MARK: - File Decryption Functions
    
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
            // Step 1: Decrypt file key using collection key (SecretBox)
            let fileKey = try decryptFileKey(
                encryptedKey: encryptedKey,
                nonce: keyDecryptionNonce,
                collectionKey: collectionKey
            )
            if verboseDecryptionLogging { print("File key decrypted successfully") }
            
            // Step 2: Decrypt metadata using file key (XChaCha20-Poly1305)
            let metadata = try decryptMetadata(
                encryptedData: encryptedMetadata,
                decryptionHeader: metadataHeader,
                fileKey: fileKey
            )
            
            
            // Step 3: Parse decrypted metadata JSON
            let fileMetadata = try parseFileMetadata(data: metadata)
            
            
            // Create CastFile with decrypted metadata and decryption info
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
        // Convert base64 inputs to data
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
        // Convert base64 inputs to data
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
        // Convert base64 header to data
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
        // Parse the decrypted JSON metadata
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
    
    // MARK: - Cache Management Helpers
    
    private func getCachedFileContent(fileID: Int) async -> Data? {
        return await fileCache.get(fileID)
    }
    
    private func cacheFileContent(fileID: Int, data: Data) async {
        await fileCache.set(fileID, data: data)
    }
    
    private func cleanupExpiredCache(validFileIDs: Set<Int>) async {
        let stats = await getCacheStats()
        print("Starting cache cleanup - current cache has \(stats.count) files")
        
        // Get all currently cached file IDs
        let cachedFileIDs = await fileCache.getCachedFileIDs()
        
        // Remove files that are no longer valid
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

// MARK: - Live Photo Utilities

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
        // For tvOS, we'll implement a simple zip reader using Foundation
        try extractZipUsingFoundation(zipURL: zipURL, to: extractDirectory)
        
        // Enumerate all extracted files (including nested) because zips may contain a folder structure.
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
            // Skip directories
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
                // Only log unexpected files once both components missing to avoid noise
                if imageData == nil || videoData == nil {
                    print("Ignoring non-component file in live photo zip: \(filename)")
                }
            }
        }
        
        // Fallback heuristics: Some live photo packages may store assets without extensions or with generic names.
        if imageData == nil || videoData == nil {
            let contents = try FileManager.default.contentsOfDirectory(at: extractDirectory, includingPropertiesForKeys: nil)
            if imageData == nil {
                if let guessImage = contents.first(where: { $0.pathExtension.isEmpty }) { // pick first extension-less file as possible image
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
