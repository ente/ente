import Foundation
import AVKit

// MARK: - Notification Extensions
extension Notification.Name {
    static let authenticationExpired = Notification.Name("authenticationExpired")
    static let slideshowRestarted = Notification.Name("slideshowRestarted")
}

// MARK: - Slide Configuration
struct SlideConfiguration {
    let imageDuration: TimeInterval
    let videoDuration: TimeInterval
    let useThumbnails: Bool
    let shuffle: Bool
    let maxImageSize: Int64
    let maxVideoSize: Int64
    let includeVideos: Bool
    
    // Enhanced prefetch settings
    let prefetchCount: Int
    let maxCacheSize: Int
    let prefetchDelay: TimeInterval
    let enablePrefetching: Bool
    
    init(
        imageDuration: TimeInterval = 12.0,
        videoDuration: TimeInterval = 30.0,
        useThumbnails: Bool = false,
        shuffle: Bool = true,
        maxImageSize: Int64 = 100 * 1024 * 1024, // 100MB
        maxVideoSize: Int64 = 500 * 1024 * 1024, // 500MB
        includeVideos: Bool = true,
        prefetchCount: Int = 3,
        maxCacheSize: Int = 5,
        prefetchDelay: TimeInterval = 0.5,
        enablePrefetching: Bool = true
    ) {
        self.imageDuration = imageDuration
        self.videoDuration = videoDuration
        self.useThumbnails = useThumbnails
        self.shuffle = shuffle
        self.maxImageSize = maxImageSize
        self.maxVideoSize = maxVideoSize
        self.includeVideos = includeVideos
        self.prefetchCount = prefetchCount
        self.maxCacheSize = maxCacheSize
        self.prefetchDelay = prefetchDelay
        self.enablePrefetching = enablePrefetching
    }
    
    func duration(for file: CastFile) -> TimeInterval {
        return file.isVideo ? videoDuration : imageDuration
    }
    
    static let `default` = SlideConfiguration()
    
    // TV-optimized configuration (use thumbnails for better performance)
    static let tvOptimized = SlideConfiguration(
        imageDuration: 8.0,     // Faster progression for TV viewing
        videoDuration: 25.0,
        useThumbnails: true,    // Better performance on Apple TV
        shuffle: true,
        maxImageSize: 50 * 1024 * 1024, // 50MB for TV
        maxVideoSize: 200 * 1024 * 1024, // 200MB for TV
        includeVideos: true,
        prefetchCount: 3,       // Prefetch next 3 slides
        maxCacheSize: 5,        // Keep 5 slides in cache
        prefetchDelay: 0.5,     // 500ms delay between prefetch operations
        enablePrefetching: true // Enable prefetching for smooth transitions
    )
}

// MARK: - Data Models
struct CastFile: Codable, Equatable {
    let id: Int
    let title: String
    let isVideo: Bool
    let isLivePhoto: Bool
    let encryptedKey: String
    let keyDecryptionNonce: String
    let fileDecryptionHeader: String
    let hash: String?      // BLAKE2b hash for file content verification
    
    var isImage: Bool { !isVideo && !isLivePhoto }
}

struct FileMetadata {
    let fileType: Int       // 0 = image, 1 = video, 2 = livePhoto
    let title: String       // filename with extension
    let creationTime: Int64 // microseconds since epoch
    let modificationTime: Int64
    let hash: String?       // BLAKE2b hash for file content verification
    
    var isImage: Bool { fileType == 0 }
    var isVideo: Bool { fileType == 1 }
    var isLivePhoto: Bool { fileType == 2 }
}

enum CastSessionState: Equatable {
    case idle
    case registering
    case waitingForPairing(deviceCode: String)
    case connected(CastPayload)
    case error(String)
}

struct CastPayload: Codable, Equatable {
    let collectionID: Int
    let collectionKey: String
    let castToken: String
}

struct CastDevice {
    let deviceCode: String
    let publicKey: Data
    let privateKey: Data
}

// MARK: - Server Response Models
struct DeviceRegistrationResponse: Codable {
    let deviceCode: String
}

struct CastDataResponse: Codable {
    let encCastData: String?
}

// MARK: - Errors
enum CastError: Error, LocalizedError {
    case networkError(String)
    case serverError(Int, String?)
    case decryptionError(String)
    
    var errorDescription: String? {
        switch self {
        case .networkError(let message):
            return "Network error: \(message)"
        case .serverError(let code, let message):
            return "Server error \(code): \(message ?? "Unknown error")"
        case .decryptionError(let message):
            return "Decryption error: \(message)"
        }
    }
}

// MARK: - Live Photo Models
struct LivePhotoComponents {
    let imageData: Data?
    let videoData: Data?
    let imagePath: URL?
    let videoPath: URL?
}

// MARK: - Cache Metadata
struct CacheMetadata: Codable {
    let fileIDs: [Int]
    let totalBytes: Int
}
