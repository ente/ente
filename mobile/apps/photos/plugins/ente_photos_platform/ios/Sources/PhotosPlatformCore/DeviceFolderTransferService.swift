import Foundation
@preconcurrency import Photos

struct DeviceFolderTransferResult: Sendable {
    var destinations: [String: String] = [:]
    var failures: [String: String] = [:]
}

struct DeviceFolderTransferService: Sendable {
    func supportedOperations(sourceFolderID: String?) -> [String] {
        guard hasPhotoAccess else { return [] }
        var operations = ["add"]
        if let source = collection(sourceFolderID), canRemove(from: source) {
            operations.append("move")
        }
        return operations
    }

    func eligibleDestinationIDs(
        operation: String,
        sourceFolderID: String?,
        candidateIDs: [String]
    ) -> [String] {
        guard supportedOperations(sourceFolderID: sourceFolderID).contains(operation) else { return [] }
        let collections = PHAssetCollection.fetchAssetCollections(
            withLocalIdentifiers: candidateIDs,
            options: nil
        )
        var eligible: [String] = []
        collections.enumerateObjects { collection, _, _ in
            if collection.localIdentifier != sourceFolderID && canAdd(to: collection) {
                eligible.append(collection.localIdentifier)
            }
        }
        return eligible
    }

    func transfer(
        operation: String,
        sourceFolderID: String?,
        targetFolderID: String,
        sourceLocalIDs: [String]
    ) -> DeviceFolderTransferResult {
        let ids = Array(Set(sourceLocalIDs))
        func failed(_ reason: String) -> DeviceFolderTransferResult {
            DeviceFolderTransferResult(
                failures: Dictionary(uniqueKeysWithValues: ids.map { ($0, reason) })
            )
        }
        guard hasPhotoAccess else { return failed("permissionDenied") }
        guard operation == "add" || operation == "move" else { return failed("unsupported") }
        guard targetFolderID != sourceFolderID,
              let target = collection(targetFolderID), canAdd(to: target) else {
            return failed("ineligibleDestination")
        }
        let source = operation == "move" ? collection(sourceFolderID) : nil
        if operation == "move" {
            guard let source, canRemove(from: source) else { return failed("unsupported") }
        }

        let options = PHFetchOptions()
        options.includeAssetSourceTypes = .typeUserLibrary
        options.predicate = NSPredicate(
            format: "mediaType == %d OR mediaType == %d",
            PHAssetMediaType.image.rawValue,
            PHAssetMediaType.video.rawValue
        )
        let fetched = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: options)
        var assets: [PHAsset] = []
        fetched.enumerateObjects { asset, _, _ in assets.append(asset) }
        let sourceAssets = source.map { PHAsset.fetchAssets(in: $0, options: nil) }
        let targetAssets = PHAsset.fetchAssets(in: target, options: nil)
        let sourceMembers = sourceAssets.map { memberIDs(in: $0, among: assets) }
        let targetMembers = memberIDs(in: targetAssets, among: assets)
        let plan = DeviceFolderTransferPlan(
            requestedIDs: Set(ids),
            accessibleIDs: Set(assets.map(\.localIdentifier)),
            sourceMemberIDs: sourceMembers,
            targetMemberIDs: targetMembers
        )
        var result = DeviceFolderTransferResult(
            failures: Dictionary(uniqueKeysWithValues: plan.missingIDs.map { ($0, "missingSource") })
        )
        let additions = assets.filter { plan.addedIDs.contains($0.localIdentifier) }
        let removals = assets.filter { plan.removedIDs.contains($0.localIdentifier) }
        if additions.isEmpty && removals.isEmpty {
            result.destinations = Dictionary(uniqueKeysWithValues: plan.completedIDs.map { ($0, $0) })
            return result
        }

        var createdRequests = false
        do {
            try PHPhotoLibrary.shared().performChangesAndWait {
                guard let targetRequest = PHAssetCollectionChangeRequest(
                    for: target, assets: targetAssets
                ) else { return }
                var sourceRequest: PHAssetCollectionChangeRequest?
                if let source {
                    guard let request = PHAssetCollectionChangeRequest(
                        for: source, assets: sourceAssets
                    ) else { return }
                    sourceRequest = request
                }
                if !additions.isEmpty { targetRequest.addAssets(additions as NSArray) }
                if !removals.isEmpty { sourceRequest?.removeAssets(removals as NSArray) }
                createdRequests = true
            }
            guard createdRequests else {
                for id in plan.completedIDs { result.failures[id] = "failed" }
                return result
            }
            result.destinations = Dictionary(uniqueKeysWithValues: plan.completedIDs.map { ($0, $0) })
        } catch {
            let error = error as NSError
            let cancelled = error.domain == PHPhotosErrorDomain &&
                error.code == PHPhotosError.Code.userCancelled.rawValue
            NSLog("Device album transfer failed: %@", error)
            for id in plan.completedIDs { result.failures[id] = cancelled ? "cancelled" : "failed" }
        }
        return result
    }

    private var hasPhotoAccess: Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        return status == .authorized || status == .limited
    }

    private func collection(_ id: String?) -> PHAssetCollection? {
        guard let id, !id.isEmpty else { return nil }
        return PHAssetCollection.fetchAssetCollections(
            withLocalIdentifiers: [id],
            options: nil
        ).firstObject
    }

    private func canAdd(to collection: PHAssetCollection) -> Bool {
        collection.assetCollectionType == .album && collection.canPerform(.addContent)
    }

    private func canRemove(from collection: PHAssetCollection) -> Bool {
        collection.assetCollectionType == .album && collection.canPerform(.removeContent)
    }

    private func memberIDs(in members: PHFetchResult<PHAsset>, among assets: [PHAsset]) -> Set<String> {
        Set(assets.filter { members.contains($0) }.map(\.localIdentifier))
    }
}
