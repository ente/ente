// TODO: Audit this file
// TODO: Too many null assertions in this file. The types need reworking.
import { ensureLocalUser } from "ente-accounts/services/user";
import { isDesktop } from "ente-base/app";
import { createComlinkCryptoWorker } from "ente-base/crypto";
import type { CryptoWorker } from "ente-base/crypto/worker";
import { isDevBuild } from "ente-base/env";
import { lowercaseExtension, nameAndExtension } from "ente-base/file-name";
import log from "ente-base/log";
import { ComlinkWorker } from "ente-base/worker/comlink-worker";
import type {
    FinishedUploadType,
    UploadProgressState,
} from "ente-gallery/components/upload-progress-stats";
import {
    markUploadedAndObtainProcessableItem,
    shouldDisableCFUploadProxy,
    uploadPathPrefix,
    type ClusteredUploadItem,
    type UploadItemAndPath,
    type UploadResult,
    type UploadableUploadItem,
} from "ente-gallery/services/upload";
import {
    matchJSONMetadata,
    metadataJSONMapKeyForJSON,
    metadataJSONMapKeyForXMP,
    tryParseTakeoutMetadataJSON,
    tryParseXMPSidecar,
    type ParsedMetadataJSON,
} from "ente-gallery/services/upload/metadata-json";
import UploadService, {
    areLivePhotoAssets,
    isUploadCancelledError,
    storageLimitExceededErrorMessage,
    upload,
    uploadCancelledErrorMessage,
    uploadItemFileName,
    uploadItemSize,
    type PotentialLivePhotoAsset,
    type UploadAsset,
} from "ente-gallery/services/upload/upload-service";
import { processVideoNewUpload } from "ente-gallery/services/video";
import type { Collection } from "ente-media/collection";
import type { EnteFile } from "ente-media/file";
import {
    fileCreationTime,
    fileLocation,
    type ParsedMetadata,
} from "ente-media/file-metadata";
import { FileType } from "ente-media/file-type";
import { potentialFileTypeFromExtension } from "ente-media/live-photo";
import { computeNormalCollectionFilesFromSaved } from "ente-new/photos/services/file";
import { indexNewUpload } from "ente-new/photos/services/ml";
import { settingsSnapshot } from "ente-new/photos/services/settings";
import { wait } from "ente-utils/promise";
import { UploadProgressTracker } from "./upload-progress";
import watcher from "./watch";

interface UploadBatchItemResult {
    localID: number;
    requestedCollectionID: number;
    result: UploadResult;
    takeoutFavorited?: true;
}

export interface UploadBatchResult {
    processedAny: boolean;
    itemResults: UploadBatchItemResult[];
}

interface UploadItemsOptions {
    skipDuplicateAddToUploadCollection?: boolean;
    includePartnerSharedFiles?: boolean;
}

export const successfulFilesFromUploadBatchResult = (
    batchResult: UploadBatchResult,
): EnteFile[] =>
    batchResult.itemResults.flatMap(({ result }) => {
        const file = successfulFileFromUploadResult(result);
        return file ? [file] : [];
    });

export const favoritedFilesFromUploadBatchResult = (
    batchResult: UploadBatchResult,
    hiddenCollectionIDs: Set<number>,
    postUploadTargetCollectionID?: number,
): EnteFile[] => {
    const filesByID = new Map<number, EnteFile>();

    for (const itemResult of batchResult.itemResults) {
        if (!itemResult.takeoutFavorited) continue;

        const finalCollectionID =
            postUploadTargetCollectionID ?? itemResult.requestedCollectionID;
        if (hiddenCollectionIDs.has(finalCollectionID)) continue;

        const file = successfulFileFromUploadResult(itemResult.result);
        if (!file || filesByID.has(file.id)) continue;

        filesByID.set(file.id, file);
    }

    return [...filesByID.values()];
};

const successfulFileFromUploadResult = (
    result: UploadResult,
): EnteFile | undefined => {
    switch (result.type) {
        case "alreadyUploaded":
        case "addedSymlink":
        case "uploaded":
        case "uploadedWithStaticThumbnail":
            return result.file;
        default:
            return undefined;
    }
};

const maxConcurrentUploads = 4;
const maxConcurrentSizeLookups = 4;

export type UploadItemWithCollection = UploadAsset & {
    localID: number;
    collectionID: number;
};

class UploadManager {
    private comlinkCryptoWorkers = new Array<
        ComlinkWorker<typeof CryptoWorker>
    >(maxConcurrentUploads);
    private parsedMetadataJSONMap = new Map<string, ParsedMetadataJSON>();
    private itemsToBeUploaded: ClusteredUploadItem[] = [];
    private failedItems: ClusteredUploadItem[] = [];
    private existingFiles: EnteFile[] = [];
    private itemResults: UploadBatchItemResult[] = [];
    private onUploadFile: ((file: EnteFile) => void) | undefined;
    private collections = new Map<number, Collection>();
    private uploadInProgress = false;
    private fatalUploadError: Error | undefined;
    private shouldUploadBeCancelled = false;

    private progress = new UploadProgressTracker();
    private onProgress: ((progress: UploadProgressState) => void) | undefined;
    private uploadProgressView = false;
    private onUploadProgressView: ((open: boolean) => void) | undefined;
    private sizeDiscoveryController: AbortController | undefined;

    public init(
        onProgress: (progress: UploadProgressState) => void,
        onUploadFile: (file: EnteFile) => void,
        onUploadProgressView: (open: boolean) => void,
    ) {
        this.onProgress = onProgress;
        this.onUploadProgressView = onUploadProgressView;
        this.publishProgress();
        onUploadProgressView(this.uploadProgressView);
        UploadService.init(undefined);
        this.onUploadFile = onUploadFile;
    }

    private publishProgress(progress = this.progress) {
        if (progress !== this.progress) return;
        this.onProgress?.(progress.snapshot(performance.now()));
    }

    logout() {
        // TODO: Consolidate state in one place instead of spreading it.
        this.sizeDiscoveryController?.abort();
        UploadService.logout();
    }

    public isUploadRunning() {
        return this.uploadInProgress;
    }

    public prepareForNewUpload(
        parsedMetadataJSONMap?: Map<string, ParsedMetadataJSON>,
    ) {
        this.itemsToBeUploaded = [];
        this.failedItems = [];
        this.itemResults = [];
        this.parsedMetadataJSONMap =
            parsedMetadataJSONMap ?? new Map<string, ParsedMetadataJSON>();
        this.shouldUploadBeCancelled = false;
        this.fatalUploadError = undefined;

        this.sizeDiscoveryController?.abort();
        this.progress = new UploadProgressTracker();
        this.publishProgress();
    }

    showUploadProgressDialog() {
        this.uploadProgressView = true;
        this.onUploadProgressView?.(true);
    }

    hideUploadProgressDialog() {
        this.uploadProgressView = false;
        this.onUploadProgressView?.(false);
    }

    public async uploadItems(
        itemsWithCollection: UploadItemWithCollection[],
        collections: Collection[],
        options?: UploadItemsOptions,
    ): Promise<UploadBatchResult> {
        if (this.uploadInProgress)
            throw new Error("Cannot run multiple uploads at once");

        log.info(`Uploading ${itemsWithCollection.length} files`);
        this.uploadInProgress = true;

        const logInterval = setInterval(() => {
            logAboutMemoryPressureIfNeeded();
            this.publishProgress();
        }, 1000);

        try {
            await this.updateExistingFilesAndCollections(collections);

            const namedItems = itemsWithCollection.map(
                makeUploadItemWithCollectionIDAndName,
            );

            this.progress.filenames = new Map(
                namedItems.map(({ localID, fileName }) => [localID, fileName]),
            );
            this.publishProgress();

            const [metadataItems, mediaItems] =
                splitMetadataAndMediaItems(namedItems);

            if (metadataItems.length) {
                this.progress.phase = "readingMetadata";
                this.publishProgress();
                await this.parseMetadataJSONFiles(metadataItems);
            }

            if (mediaItems.length) {
                const clusteredMediaItems = await clusterLivePhotos(
                    mediaItems,
                    this.parsedMetadataJSONMap,
                );

                this.abortIfCancelled();

                this.progress.filenames = new Map(
                    clusteredMediaItems.map(({ localID, fileName }) => [
                        localID,
                        fileName,
                    ]),
                );
                this.progress.hasLivePhotos =
                    mediaItems.length != clusteredMediaItems.length;
                this.publishProgress();

                await this.uploadMediaItems(clusteredMediaItems, options);
            }
        } catch (e) {
            if (!isUploadCancelledError(e)) {
                log.error("Upload failed", e);
                throw e;
            }
        } finally {
            this.progress.phase = "done";
            this.publishProgress();
            void globalThis.electron?.clearPendingUploads();
            for (let i = 0; i < maxConcurrentUploads; i++) {
                this.comlinkCryptoWorkers[i]?.terminate();
            }
            this.uploadInProgress = false;
            clearInterval(logInterval);
        }

        const partnerSharedCount = this.itemResults.filter(
            ({ result }) => result.type == "partnerShared",
        ).length;
        if (partnerSharedCount) {
            log.info(`Skipped ${partnerSharedCount} partner shared files`);
        }

        return {
            processedAny: this.progress.finished.size > 0,
            itemResults: [...this.itemResults],
        };
    }

    public async uploadFile(
        file: File,
        collection: Collection,
        sourceEnteFile: EnteFile,
    ): Promise<UploadBatchResult> {
        const timestamp = fileCreationTime(sourceEnteFile);
        const dateTime = sourceEnteFile.pubMagicMetadata?.data.dateTime;
        const offset = sourceEnteFile.pubMagicMetadata?.data.offsetTime;
        const location = fileLocation(sourceEnteFile);

        const creationDate: ParsedMetadata["creationDate"] = dateTime
            ? { timestamp, dateTime, offset }
            : undefined;

        // Canvas exports lose embedded metadata.
        // Preserve the source's local capture time and location.
        const externalParsedMetadata = {
            creationDate,
            creationTime: creationDate ? undefined : timestamp,
            location,
        };

        const item = {
            uploadItem: file,
            pathPrefix: undefined,
            localID: 1,
            collectionID: collection.id,
            externalParsedMetadata,
        };

        return this.uploadItems([item], [collection]);
    }

    private abortIfCancelled = () => {
        if (this.fatalUploadError) {
            throw this.fatalUploadError;
        }
        if (this.shouldUploadBeCancelled) {
            throw new Error(uploadCancelledErrorMessage);
        }
    };

    private async updateExistingFilesAndCollections(collections: Collection[]) {
        const files = await computeNormalCollectionFilesFromSaved();
        const userID = ensureLocalUser().id;
        this.existingFiles = files.filter((file) => file.ownerID == userID);
        this.collections = new Map(
            collections.map((collection) => [collection.id, collection]),
        );
    }

    private async parseMetadataJSONFiles(
        items: UploadItemWithCollectionIDAndName[],
    ) {
        this.progress.reset(items.length);
        this.publishProgress();

        for (const item of items) {
            this.abortIfCancelled();

            log.info(`Parsing metadata ${item.fileName}`);
            const parsedMetadata = await tryParseMetadataItem(item);
            if (parsedMetadata) {
                const [key, metadata, isJSON] = parsedMetadata;
                if (isJSON || !this.parsedMetadataJSONMap.has(key))
                    this.parsedMetadataJSONMap.set(key, metadata);
            }
            this.progress.uploadedCount++;
            this.publishProgress();
        }
    }

    private async uploadMediaItems(
        mediaItems: ClusteredUploadItem[],
        options?: UploadItemsOptions,
    ) {
        this.itemsToBeUploaded = [...this.itemsToBeUploaded, ...mediaItems];
        const progress = this.progress;
        progress.reset(mediaItems.length);
        await UploadService.setFileCount(mediaItems.length);
        progress.phase = "uploading";
        for (const { localID } of mediaItems)
            progress.bytes.set(localID, { total: undefined, uploaded: 0 });
        this.publishProgress(progress);

        const controller = new AbortController();
        this.sizeDiscoveryController = controller;
        void this.discoverUploadSizes(mediaItems, progress, controller.signal);
        try {
            const uploadProcesses = new Array<Promise<void>>();
            for (
                let i = 0;
                i < maxConcurrentUploads && this.itemsToBeUploaded.length > 0;
                i++
            ) {
                this.comlinkCryptoWorkers[i] = createComlinkCryptoWorker();
                const worker = await this.comlinkCryptoWorkers[i]!.remote;
                uploadProcesses.push(
                    this.uploadNextItemInQueue(worker, progress, options),
                );
            }
            await Promise.all(uploadProcesses);
        } finally {
            controller.abort();
            if (this.sizeDiscoveryController === controller)
                this.sizeDiscoveryController = undefined;
        }
    }

    private async discoverUploadSizes(
        items: ClusteredUploadItem[],
        progress: UploadProgressTracker,
        signal: AbortSignal,
    ) {
        const remainingItems = items.values();
        await Promise.all(
            Array.from({ length: maxConcurrentSizeLookups }, async () => {
                for (const item of remainingItems) {
                    if (signal.aborted) return;
                    const entry = progress.bytes.get(item.localID);
                    if (!entry || entry.total !== undefined) continue;
                    const assets = item.isLivePhoto
                        ? [
                              item.livePhotoAssets!.image,
                              item.livePhotoAssets!.video,
                          ]
                        : [item.uploadItem!];
                    try {
                        const sizes = await Promise.all(
                            assets.map(uploadItemSize),
                        );
                        signal.throwIfAborted();
                        if (progress.bytes.get(item.localID) === entry)
                            entry.total = sizes.reduce(
                                (sum, size) => sum + size,
                                0,
                            );
                    } catch {
                        continue;
                    }
                }
            }),
        );
    }

    private async uploadNextItemInQueue(
        worker: CryptoWorker,
        progress: UploadProgressTracker,
        options?: UploadItemsOptions,
    ) {
        const settings = settingsSnapshot();
        const uploadContext = {
            isCFUploadProxyDisabled: shouldDisableCFUploadProxy(),
            deferMultipartChecksums:
                settings.deferredMultipartChecksumsEnabled &&
                (settings.isInternalUser || isDevBuild),
            isInternalUser: settings.isInternalUser,
            skipDuplicateAddToUploadCollection:
                options?.skipDuplicateAddToUploadCollection,
            includePartnerSharedFiles: options?.includePartnerSharedFiles,
            abortIfCancelled: this.abortIfCancelled.bind(this),
            updateUploadProgress: (localID: number, percentage: number) => {
                if (progress.phase != "uploading") return;
                progress.inProgress.set(localID, Math.round(percentage));
                this.publishProgress(progress);
            },
            updateUploadBytes: (
                localID: number,
                uploaded: number,
                total: number,
                reset: boolean,
            ) => {
                progress.updateBytes(
                    localID,
                    uploaded,
                    total,
                    reset,
                    performance.now(),
                );
            },
        };

        while (this.itemsToBeUploaded.length > 0) {
            this.abortIfCancelled();
            logAboutMemoryPressureIfNeeded();

            const clusteredItem = this.itemsToBeUploaded.pop()!;
            const { localID, collectionID } = clusteredItem;
            const collection = this.collections.get(collectionID)!;
            const uploadableItem = { ...clusteredItem, collection };

            progress.inProgress.set(localID, 0);
            this.publishProgress(progress);
            await wait(0);

            let uploadResult: UploadResult;
            try {
                uploadResult = await upload(
                    uploadableItem,
                    undefined,
                    this.existingFiles,
                    this.parsedMetadataJSONMap,
                    worker,
                    uploadContext,
                );
            } catch (e) {
                if (
                    e instanceof Error &&
                    e.message == storageLimitExceededErrorMessage
                ) {
                    this.fatalUploadError = e;
                    this.itemsToBeUploaded = [];
                }
                throw e;
            }
            const takeoutFavorited = matchJSONMetadata(
                uploadableItem.pathPrefix,
                collectionID,
                uploadableItem.fileName,
                this.parsedMetadataJSONMap,
            )?.favorited;
            this.itemResults.push({
                localID,
                requestedCollectionID: collectionID,
                result: uploadResult,
                ...(takeoutFavorited ? { takeoutFavorited } : {}),
            });

            const finishedUploadType = await this.postUploadTask(
                uploadableItem,
                uploadResult,
            );

            progress.finish(localID, finishedUploadType);
            this.publishProgress(progress);
            UploadService.reducePendingUploadCount();
        }
    }

    private async postUploadTask(
        uploadableItem: UploadableUploadItem,
        uploadResult: UploadResult,
    ): Promise<FinishedUploadType> {
        const type = uploadResult.type;
        log.info(`Upload ${uploadableItem.fileName} | ${type}`);
        try {
            const processableUploadItem =
                await markUploadedAndObtainProcessableItem(uploadableItem);

            switch (uploadResult.type) {
                case "failed":
                case "blocked":
                    // Failed and blocked items can be retried.
                    this.failedItems.push(uploadableItem);
                    break;

                case "addedSymlink":
                    this.updateExistingFiles(uploadResult.file);
                    break;

                case "uploaded":
                case "uploadedWithStaticThumbnail":
                    {
                        const { file } = uploadResult;

                        indexNewUpload(file, processableUploadItem);
                        processVideoNewUpload(file, processableUploadItem);

                        this.updateExistingFiles(file);
                    }
                    break;
            }

            if (isDesktop && watcher.isUploadRunning()) {
                watcher.onFileUpload(uploadableItem, uploadResult);
            }

            return type == "addedSymlink" ? "uploaded" : type;
        } catch (e) {
            log.error("Post file upload action failed", e);
            return "failed";
        }
    }

    public cancelRunningUpload() {
        log.info("User cancelled upload");
        this.sizeDiscoveryController?.abort();
        this.progress.phase = "cancelling";
        this.publishProgress();
        this.shouldUploadBeCancelled = true;
    }

    public failedItemState() {
        return {
            items: [...this.failedItems],
            collections: [...this.collections.values()],
            parsedMetadataJSONMap: this.parsedMetadataJSONMap,
        };
    }

    private updateExistingFiles(file: EnteFile) {
        this.existingFiles.push(file);
        this.onUploadFile!(file);
    }

    public isUploadInProgress = () => {
        return this.uploadInProgress || watcher.isUploadRunning();
    };
}

export const uploadManager = new UploadManager();

// Retry items may already be clustered and omit uploadItem.
type UploadItemWithCollectionIDAndName = UploadAsset & {
    localID: number;
    collectionID: number;
    fileName: string;
};

const makeUploadItemWithCollectionIDAndName = (
    f: UploadItemWithCollection,
): UploadItemWithCollectionIDAndName => ({
    localID: f.localID,
    collectionID: f.collectionID,
    fileName: f.isLivePhoto
        ? uploadItemFileName(f.livePhotoAssets!.image)
        : uploadItemFileName(f.uploadItem!),
    isLivePhoto: f.isLivePhoto,
    uploadItem: f.uploadItem,
    pathPrefix: f.pathPrefix,
    livePhotoAssets: f.livePhotoAssets,
    externalParsedMetadata: f.externalParsedMetadata,
});

const tryParseMetadataItem = async (
    item: UploadItemWithCollectionIDAndName,
) => {
    const { uploadItem, pathPrefix, collectionID, fileName } = item;
    const extension = lowercaseExtension(fileName);
    const metadata =
        extension == "json"
            ? await tryParseTakeoutMetadataJSON(uploadItem!)
            : extension == "xmp" && settingsSnapshot().isInternalUser
              ? await tryParseXMPSidecar(uploadItem!)
              : undefined;
    if (!metadata) return undefined;

    const key =
        extension == "json"
            ? metadataJSONMapKeyForJSON(pathPrefix, collectionID, fileName)
            : metadataJSONMapKeyForXMP(pathPrefix, collectionID, fileName);
    return [key, metadata, extension == "json"] as const;
};

const splitMetadataAndMediaItems = (
    items: UploadItemWithCollectionIDAndName[],
): [
    metadata: UploadItemWithCollectionIDAndName[],
    media: UploadItemWithCollectionIDAndName[],
] =>
    items.reduce(
        ([metadata, media], f) => {
            if (["json", "xmp"].includes(lowercaseExtension(f.fileName) ?? ""))
                metadata.push(f);
            else media.push(f);
            return [metadata, media];
        },
        [
            new Array<UploadItemWithCollectionIDAndName>(),
            new Array<UploadItemWithCollectionIDAndName>(),
        ],
    );

const clusterLivePhotos = async (
    _items: UploadItemWithCollectionIDAndName[],
    parsedMetadataJSONMap: Map<string, ParsedMetadataJSON>,
) => {
    const result: ClusteredUploadItem[] = [];
    type ItemAsset = PotentialLivePhotoAsset & {
        localID: number;
        isLivePhoto?: boolean;
        externalParsedMetadata?: UploadItemWithCollectionIDAndName["externalParsedMetadata"];
    };
    const items: ItemAsset[] = _items.map((item) => ({
        localID: item.localID,
        isLivePhoto: item.isLivePhoto,
        fileName: item.fileName,
        fileType: potentialFileTypeFromExtension(item.fileName) ?? -1,
        collectionID: item.collectionID,
        uploadItem: item.uploadItem!,
        pathPrefix: item.pathPrefix,
        externalParsedMetadata: item.externalParsedMetadata,
    }));
    items
        .sort((f, g) => {
            const cmp = nameAndExtension(f.fileName)[0].localeCompare(
                nameAndExtension(g.fileName)[0],
            );
            return cmp == 0 ? f.fileType - g.fileType : cmp;
        })
        .sort((f, g) => f.collectionID - g.collectionID);
    let index = 0;
    while (index < items.length - 1) {
        const fa = items[index]!;
        const ga = items[index + 1]!;
        if (await areLivePhotoAssets(fa, ga, parsedMetadataJSONMap)) {
            const [image, video] =
                fa.fileType == FileType.image ? [fa, ga] : [ga, fa];
            result.push({
                localID: fa.localID,
                collectionID: fa.collectionID,
                fileName: image.fileName,
                isLivePhoto: true,
                pathPrefix: image.pathPrefix,
                externalParsedMetadata: image.externalParsedMetadata,
                livePhotoAssets: {
                    image: image.uploadItem,
                    video: video.uploadItem,
                },
            });
            index += 2;
        } else {
            // Retry items may already be clustered live photos.
            result.push({ ...fa, isLivePhoto: fa.isLivePhoto ?? false });
            index += 1;
        }
    }
    if (index == items.length - 1) {
        const f = items[index]!;
        result.push({ ...f, isLivePhoto: f.isLivePhoto ?? false });
    }
    return result;
};

export type ImportSource = "generic" | "google-takeout" | "apple-photos";

export const uploadableMediaCount = async (
    itemGroups: UploadItemAndPath[][],
): Promise<{ count: number; importSource: ImportSource }> => {
    let localID = 0;
    const namedItems = itemGroups.flatMap((items, collectionID) =>
        items.map(([uploadItem, path]) =>
            makeUploadItemWithCollectionIDAndName({
                localID: localID++,
                collectionID,
                uploadItem,
                pathPrefix: uploadPathPrefix(path),
            }),
        ),
    );
    const [metadataItems, mediaItems] = splitMetadataAndMediaItems(namedItems);
    const parsedMetadataJSONMap = new Map<string, ParsedMetadataJSON>();
    let parsedJSONCount = 0;
    let parsedXMPCount = 0;

    for (const item of metadataItems) {
        const parsedMetadata = await tryParseMetadataItem(item);
        if (parsedMetadata) {
            const [key, metadata, isJSON] = parsedMetadata;
            if (isJSON || !parsedMetadataJSONMap.has(key))
                parsedMetadataJSONMap.set(key, metadata);
            if (isJSON) parsedJSONCount++;
            else parsedXMPCount++;
        }
    }

    return {
        count: (await clusterLivePhotos(mediaItems, parsedMetadataJSONMap))
            .length,
        importSource:
            parsedJSONCount > 0
                ? "google-takeout"
                : parsedXMPCount > 0
                  ? "apple-photos"
                  : "generic",
    };
};

const logAboutMemoryPressureIfNeeded = () => {
    if (!globalThis.electron) return;

    // Electron recommends this deprecated API, and Chromium still supports it.
    const { memory } = performance as unknown as {
        memory: { totalJSHeapSize: number; jsHeapSizeLimit: number };
    };

    const heapSize = memory.totalJSHeapSize;
    const heapLimit = memory.jsHeapSizeLimit;
    if (heapSize / heapLimit > 0.7) {
        log.info(
            `Memory usage (${heapSize} bytes of ${heapLimit} bytes) exceeds the high water mark`,
        );
    }
};
