import Foundation

// MARK: - Persistent Thread-Safe File Cache

actor ThreadSafeFileCache {
    private var cache: [Int: Data] = [:]
    private var cacheOrder: [Int] = []
    private var totalBytes: Int = 0
    private let maxBytes: Int
    private let shrinkTargetBytes: Int
    private let cacheDirectory: URL
    private let metadataURL: URL
    
    init(maxBytes: Int, shrinkTargetBytes: Int) {
        self.maxBytes = maxBytes
        self.shrinkTargetBytes = shrinkTargetBytes
        
        let documentsPath = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.cacheDirectory = documentsPath.appendingPathComponent("EnteFileCache")
        self.metadataURL = cacheDirectory.appendingPathComponent("cache_metadata.json")
        
        // Create cache directory if it doesn't exist
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        
        loadCacheFromDisk()
    }
    
    func get(_ fileID: Int) -> Data? {
        if let data = cache[fileID] {
            return data
        }
        
        let fileURL = cacheDirectory.appendingPathComponent("\(fileID).cache")
        if let data = try? Data(contentsOf: fileURL) {
            // Load into memory cache for faster future access
            cache[fileID] = data
            if !cacheOrder.contains(fileID) {
                cacheOrder.append(fileID)
            }
            totalBytes += data.count
            return data
        }
        
        return nil
    }
    
    func set(_ fileID: Int, data: Data) {
        if let existingData = cache[fileID] {
            totalBytes -= existingData.count
            cacheOrder.removeAll { $0 == fileID }
        }
        
        cache[fileID] = data
        cacheOrder.append(fileID)
        totalBytes += data.count
        
        let fileURL = cacheDirectory.appendingPathComponent("\(fileID).cache")
        try? data.write(to: fileURL)
        
        enforceLimits()
        
        saveCacheMetadata()
        
        print("Cached file \(fileID) content (\(data.count) bytes) - Cache size: \(cache.count) files")
    }
    
    func remove(_ fileID: Int) {
        if let removedData = cache.removeValue(forKey: fileID) {
            totalBytes -= removedData.count
            cacheOrder.removeAll { $0 == fileID }
            
            let fileURL = cacheDirectory.appendingPathComponent("\(fileID).cache")
            try? FileManager.default.removeItem(at: fileURL)
            
            saveCacheMetadata()
            
            print("Removed cached content for file \(fileID) (\(removedData.count) bytes)")
        }
    }
    
    func clear() {
        let clearedCount = cache.count
        cache.removeAll()
        cacheOrder.removeAll()
        totalBytes = 0
        
        try? FileManager.default.removeItem(at: cacheDirectory)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        
        try? FileManager.default.removeItem(at: metadataURL)
        
        print("Cleared file content cache (\(clearedCount) files)")
    }
    
    func getStats() -> (count: Int, totalSize: Int) {
        return (count: cache.count, totalSize: totalBytes)
    }
    
    func getCachedFileIDs() -> [Int] {
        return Array(cache.keys) + cacheOrder.filter { !cache.keys.contains($0) }
    }
    
    private func enforceLimits() {
        guard totalBytes > maxBytes else { return }
        
        var removedBytes = 0
        while totalBytes - removedBytes > shrinkTargetBytes, let oldest = cacheOrder.first {
            cacheOrder.removeFirst()
            if let data = cache.removeValue(forKey: oldest) {
                removedBytes += data.count
                
                let fileURL = cacheDirectory.appendingPathComponent("\(oldest).cache")
                try? FileManager.default.removeItem(at: fileURL)
                
                print("Evicted file \(oldest) (\(data.count) bytes) to control cache size")
            }
        }
        totalBytes -= removedBytes
        
        // Save updated metadata after eviction
        saveCacheMetadata()
        
        print("Cache GC complete: now \(cache.count) files, \(totalBytes) bytes")
    }
    
    private func loadCacheFromDisk() {
        guard let metadataData = try? Data(contentsOf: metadataURL),
              let metadata = try? JSONDecoder().decode(CacheMetadata.self, from: metadataData) else {
            return
        }
        
        print("Loading existing cache from disk - \(metadata.fileIDs.count) files")
        
        var loadedBytes = 0
        var validFileIDs: [Int] = []
        
        for fileID in metadata.fileIDs {
            let fileURL = cacheDirectory.appendingPathComponent("\(fileID).cache")
            if FileManager.default.fileExists(atPath: fileURL.path) {
                if let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
                   let fileSize = attributes[.size] as? Int {
                    loadedBytes += fileSize
                    validFileIDs.append(fileID)
                }
            }
        }
        
        cacheOrder = validFileIDs
        totalBytes = loadedBytes
        
        print("Loaded \(validFileIDs.count) cached files (\(loadedBytes) bytes) from disk")
        
        // Clean up any invalid entries
        if validFileIDs.count != metadata.fileIDs.count {
            saveCacheMetadata()
        }
    }
    
    private func saveCacheMetadata() {
        let metadata = CacheMetadata(fileIDs: cacheOrder, totalBytes: totalBytes)
        if let data = try? JSONEncoder().encode(metadata) {
            try? data.write(to: metadataURL)
        }
    }
}