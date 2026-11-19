import Foundation

struct CacheReservation {
    let id: UUID
    let fileID: Int
    let directory: URL
}

enum FileCacheError: Error {
    case entryTooLarge
    case reservationExists
    case reservationInvalidated
    case reservationMissing
    case invalidEntry
}

actor ThreadSafeFileCache {
    private struct ReservationState {
        let id: UUID
        let maximumBytes: Int
        var isInvalidated: Bool
    }

    private var cacheOrder: [Int] = []
    private var entryBytes: [Int: Int] = [:]
    private var reservations: [Int: ReservationState] = [:]
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

        let metadata: CacheMetadata?
        if let metadataData = try? Data(contentsOf: metadataURL) {
            metadata = try? JSONDecoder().decode(CacheMetadata.self, from: metadataData)
        } else {
            metadata = nil
        }
        let preferredOrder = metadata?.fileIDs ?? []
        let contents =
            (try? FileManager.default.contentsOfDirectory(
                at: cacheDirectory,
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            )) ?? []

        var discovered: [Int] = []
        for url in contents where url != metadataURL {
            guard let fileID = Int(url.lastPathComponent), Self.isDirectory(url) else {
                try? FileManager.default.removeItem(at: url)
                continue
            }
            guard let bytes = Self.directorySize(url), bytes <= maxBytes else {
                try? FileManager.default.removeItem(at: url)
                continue
            }
            discovered.append(fileID)
            entryBytes[fileID] = bytes
            totalBytes += bytes
        }

        var order = preferredOrder.filter(discovered.contains)
        order.append(contentsOf: discovered.filter { !order.contains($0) })
        while totalBytes > maxBytes, let oldest = order.first {
            order.removeFirst()
            totalBytes -= entryBytes.removeValue(forKey: oldest) ?? 0
            try? FileManager.default.removeItem(at: Self.entryURL(cacheDirectory, oldest))
        }
        cacheOrder = order
        Self.saveMetadata(metadataURL, order, totalBytes)
    }

    func get(_ fileID: Int) -> URL? {
        guard entryBytes[fileID] != nil else { return nil }
        let directory = Self.entryURL(cacheDirectory, fileID)
        guard Self.isDirectory(directory) else {
            remove(fileID)
            return nil
        }
        cacheOrder.removeAll { $0 == fileID }
        cacheOrder.append(fileID)
        saveCacheMetadata()
        return directory
    }

    func reserve(_ fileID: Int, maximumBytes: Int) throws -> CacheReservation {
        guard maximumBytes > 0, maximumBytes <= maxBytes else {
            throw FileCacheError.entryTooLarge
        }
        guard reservations[fileID] == nil else {
            throw FileCacheError.reservationExists
        }

        remove(fileID)
        let reservedBytes = reservations.values.reduce(0) { $0 + $1.maximumBytes }
        if totalBytes + reservedBytes + maximumBytes > maxBytes {
            while totalBytes + reservedBytes + maximumBytes > shrinkTargetBytes,
                let oldest = cacheOrder.first
            {
                remove(oldest)
            }
        }
        guard totalBytes + reservedBytes + maximumBytes <= maxBytes else {
            throw FileCacheError.entryTooLarge
        }

        let id = UUID()
        reservations[fileID] = ReservationState(
            id: id,
            maximumBytes: maximumBytes,
            isInvalidated: false,
        )
        return CacheReservation(
            id: id,
            fileID: fileID,
            directory: Self.entryURL(cacheDirectory, fileID),
        )
    }

    func commit(_ reservation: CacheReservation, maximumEntryBytes: Int) throws {
        guard let state = reservations[reservation.fileID], state.id == reservation.id else {
            throw FileCacheError.reservationMissing
        }
        reservations.removeValue(forKey: reservation.fileID)
        guard !state.isInvalidated else {
            try? FileManager.default.removeItem(at: reservation.directory)
            throw FileCacheError.reservationInvalidated
        }
        guard let bytes = Self.directorySize(reservation.directory),
            bytes <= state.maximumBytes,
            bytes <= maximumEntryBytes
        else {
            try? FileManager.default.removeItem(at: reservation.directory)
            throw FileCacheError.invalidEntry
        }

        entryBytes[reservation.fileID] = bytes
        cacheOrder.removeAll { $0 == reservation.fileID }
        cacheOrder.append(reservation.fileID)
        totalBytes += bytes
        saveCacheMetadata()
    }

    func cancel(_ reservation: CacheReservation) {
        guard reservations[reservation.fileID]?.id == reservation.id else { return }
        reservations.removeValue(forKey: reservation.fileID)
        try? FileManager.default.removeItem(at: reservation.directory)
    }

    func remove(_ fileID: Int) {
        if var reservation = reservations[fileID] {
            reservation.isInvalidated = true
            reservations[fileID] = reservation
        }
        totalBytes -= entryBytes.removeValue(forKey: fileID) ?? 0
        cacheOrder.removeAll { $0 == fileID }
        try? FileManager.default.removeItem(at: Self.entryURL(cacheDirectory, fileID))
        saveCacheMetadata()
    }

    func clear() {
        cacheOrder.removeAll()
        entryBytes.removeAll()
        totalBytes = 0

        for fileID in Array(reservations.keys) {
            if var reservation = reservations[fileID] {
                reservation.isInvalidated = true
                reservations[fileID] = reservation
            }
        }
        let contents =
            (try? FileManager.default.contentsOfDirectory(
                at: cacheDirectory,
                includingPropertiesForKeys: [.isDirectoryKey],
            )) ?? []
        for url in contents where Int(url.lastPathComponent) != nil {
            try? FileManager.default.removeItem(at: url)
        }
        saveCacheMetadata()
    }

    func getCachedFileIDs() -> [Int] {
        cacheOrder
    }

    private func saveCacheMetadata() {
        Self.saveMetadata(metadataURL, cacheOrder, totalBytes)
    }

    private static func saveMetadata(_ metadataURL: URL, _ fileIDs: [Int], _ totalBytes: Int) {
        let metadata = CacheMetadata(fileIDs: fileIDs, totalBytes: totalBytes)
        if let data = try? JSONEncoder().encode(metadata) {
            try? data.write(to: metadataURL, options: .atomic)
        }
    }

    private static func entryURL(_ cacheDirectory: URL, _ fileID: Int) -> URL {
        cacheDirectory.appendingPathComponent(String(fileID), isDirectory: true)
    }

    private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    private static func directorySize(_ directory: URL) -> Int? {
        guard isDirectory(directory),
            let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            )
        else { return nil }

        var bytes = 0
        while let url = enumerator.nextObject() as? URL {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                values.isRegularFile == true,
                let fileBytes = values.fileSize,
                bytes <= Int.max - fileBytes
            else { return nil }
            bytes += fileBytes
        }
        return bytes
    }
}
