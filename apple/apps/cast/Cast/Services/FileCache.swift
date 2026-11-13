import Foundation

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

        cacheDirectory = URL.cachesDirectory.appendingPathComponent("EnteFileCache")
        metadataURL = cacheDirectory.appendingPathComponent("cache_metadata.json")

        try? FileManager.default.createDirectory(
            at: cacheDirectory,
            withIntermediateDirectories: true,
        )

        guard let metadataData = try? Data(contentsOf: metadataURL),
            let metadata = try? JSONDecoder().decode(CacheMetadata.self, from: metadataData)
        else {
            return
        }

        var loadedBytes = 0
        var validFileIDs: [Int] = []

        for fileID in metadata.fileIDs {
            let fileURL = cacheDirectory.appendingPathComponent("\(fileID).cache")
            if FileManager.default.fileExists(atPath: fileURL.path) {
                if let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
                    let fileSize = attributes[.size] as? Int
                {
                    loadedBytes += fileSize
                    validFileIDs.append(fileID)
                }
            }
        }

        cacheOrder = validFileIDs
        totalBytes = loadedBytes

        if validFileIDs.count != metadata.fileIDs.count {
            let metadata = CacheMetadata(fileIDs: cacheOrder, totalBytes: totalBytes)
            if let data = try? JSONEncoder().encode(metadata) {
                try? data.write(to: metadataURL)
            }
        }
    }

    func get(_ fileID: Int) -> Data? {
        if let data = cache[fileID] {
            return data
        }

        let fileURL = cacheDirectory.appendingPathComponent("\(fileID).cache")
        if let data = try? Data(contentsOf: fileURL) {
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
    }

    func remove(_ fileID: Int) {
        if let removedData = cache.removeValue(forKey: fileID) {
            totalBytes -= removedData.count
            cacheOrder.removeAll { $0 == fileID }

            let fileURL = cacheDirectory.appendingPathComponent("\(fileID).cache")
            try? FileManager.default.removeItem(at: fileURL)

            saveCacheMetadata()
        }
    }

    func clear() {
        cache.removeAll()
        cacheOrder.removeAll()
        totalBytes = 0

        try? FileManager.default.removeItem(at: cacheDirectory)
        try? FileManager.default.createDirectory(
            at: cacheDirectory,
            withIntermediateDirectories: true,
        )

        try? FileManager.default.removeItem(at: metadataURL)
    }

    func getCachedFileIDs() -> [Int] {
        Array(cache.keys) + cacheOrder.filter { !cache.keys.contains($0) }
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
            }
        }
        totalBytes -= removedBytes

        saveCacheMetadata()
    }

    private func saveCacheMetadata() {
        let metadata = CacheMetadata(fileIDs: cacheOrder, totalBytes: totalBytes)
        if let data = try? JSONEncoder().encode(metadata) {
            try? data.write(to: metadataURL)
        }
    }
}
