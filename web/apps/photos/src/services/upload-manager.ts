// TODO: Audit this file
// TODO: Too many null assertions in this file. The types need reworking.
import { ensureLocalUser } from "ente-accounts/services/user";
import { isDesktop } from "ente-base/app";
import { createComlinkCryptoWorker } from "ente-base/crypto";
import type { CryptoWorker } from "ente-base/crypto/worker";
import { lowercaseExtension, nameAndExtension } from "ente-base/file-name";
import log from "ente-base/log";
import { ComlinkWorker } from "ente-base/worker/comlink-worker";
import {
    markUploadedAndObtainProcessableItem,
    shouldDisableCFUploadProxy,
    uploadPathPrefix,
    type ClusteredUploadItem,
    type UploadItemAndPath,
    type UploadPhase,
    type UploadResult,
    type UploadableUploadItem,
} from "ente-gallery/services/upload";
import {
    matchJSONMetadata,
    metadataJSONMapKeyForJSON,
    tryParseTakeoutMetadataJSON,
    type ParsedMetadataJSON,
} from "ente-gallery/services/upload/metadata-json";
import UploadService, {
    areLivePhotoAssets,
    isUploadCancelledError,
    storageLimitExceededErrorMessage,
    upload,
    uploadCancelledErrorMessage,
    uploadItemFileName,
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
import { wait } from "ente-utils/promise";
import watcher from "./watch";

export type FileID = number;

export type PercentageUploaded = number;
/* localID => fileName */
export type UploadFileNames = Map<FileID, string>;

export interface UploadCounter {
    finished: number;
    total: number;
}

export interface InProgressUpload {
    localFileID: FileID;
    progress: PercentageUploaded;
}

/**
 * A variant of {@link UploadResult}'s {@link type} values used when segregating
 * finished uploads in the UI. "addedSymlink" is treated as "uploaded",
 * everything else remains as it were.
 */
export type FinishedUploadType = Exclude<UploadResult["type"], "addedSymlink">;

export type InProgressUploads = Map<FileID, PercentageUploaded>;

export type FinishedUploads = Map<FileID, FinishedUploadType>;

export type SegregatedFinishedUploads = Map<FinishedUploadType, FileID[]>;

export interface UploadBatchItemResult {
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

    /**
     * Filters items with takeoutFavorited set to true, checks if their final upload
     * target collection is not hidden, and collects successfully uploaded files
     * and returns them to be added to the Favorites collection of the user after
     * de-dupe check by fileID.
     */
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

export interface ProgressUpdater {
    setPercentComplete: React.Dispatch<React.SetStateAction<number>>;
    setUploadCounter: React.Dispatch<React.SetStateAction<UploadCounter>>;
    setUploadPhase: (phase: UploadPhase) => void;
    setInProgressUploads: React.Dispatch<
        React.SetStateAction<InProgressUpload[]>
    >;
    setFinishedUploads: React.Dispatch<
        React.SetStateAction<SegregatedFinishedUploads>
    >;
    setUploadFilenames: React.Dispatch<React.SetStateAction<UploadFileNames>>;
    setHasLivePhotos: React.Dispatch<React.SetStateAction<boolean>>;
    setUploadProgressView: React.Dispatch<React.SetStateAction<boolean>>;
}

/** The number of uploads to process in parallel. */
const maxConcurrentUploads = 4;

export type UploadItemWithCollection = UploadAsset & {
    localID: number;
    collectionID: number;
};

class UIService {
    // eslint-disable-next-line @typescript-eslint/ban-ts-comment
    // @ts-ignore
    private progressUpdater: ProgressUpdater;

    // UPLOAD LEVEL STATES
    private uploadPhase: UploadPhase = "preparing";
    private filenames = new Map<number, string>();
    private hasLivePhoto = false;
    private uploadProgressView = false;

    // STAGE LEVEL STATES
    private perFileProgress = 0;
    private filesUploadedCount = 0;
    private totalFilesCount = 0;
    private inProgressUploads: InProgressUploads = new Map();
    private finishedUploads: FinishedUploads = new Map();

    init(progressUpdater: ProgressUpdater) {
        this.progressUpdater = progressUpdater;
        this.progressUpdater.setUploadPhase(this.uploadPhase);
        this.progressUpdater.setUploadFilenames(this.filenames);
        this.progressUpdater.setHasLivePhotos(this.hasLivePhoto);
        this.progressUpdater.setUploadProgressView(this.uploadProgressView);
        this.progressUpdater.setUploadCounter({
            finished: this.filesUploadedCount,
            total: this.totalFilesCount,
        });
        this.progressUpdater.setInProgressUploads(
            convertInProgressUploadsToList(this.inProgressUploads),
        );
        this.progressUpdater.setFinishedUploads(
            groupByResult(this.finishedUploads),
        );
    }

    reset(count = 0) {
        this.setTotalFileCount(count);
        this.filesUploadedCount = 0;
        this.inProgressUploads = new Map<number, number>();
        this.finishedUploads = new Map<number, FinishedUploadType>();
        this.updateProgressBarUI();
    }

    setTotalFileCount(count: number) {
        this.totalFilesCount = count;
        if (count > 0) {
            this.perFileProgress = 100 / this.totalFilesCount;
        } else {
            this.perFileProgress = 0;
        }
    }

    setFileProgress(key: number, progress: number) {
        this.inProgressUploads.set(key, progress);
        this.updateProgressBarUI();
    }

    setUploadPhase(phase: UploadPhase) {
        this.uploadPhase = phase;
        this.progressUpdater.setUploadPhase(phase);
    }

    setFiles(files: { localID: number; fileName: string }[]) {
        const filenames = new Map(files.map((f) => [f.localID, f.fileName]));
        this.filenames = filenames;
        this.progressUpdater.setUploadFilenames(filenames);
    }

    setHasLivePhoto(hasLivePhoto: boolean) {
        this.hasLivePhoto = hasLivePhoto;
        this.progressUpdater.setHasLivePhotos(hasLivePhoto);
    }

    setUploadProgressView(uploadProgressView: boolean) {
        this.uploadProgressView = uploadProgressView;
        this.progressUpdater.setUploadProgressView(uploadProgressView);
    }

    increaseFileUploaded() {
        this.filesUploadedCount++;
        this.updateProgressBarUI();
    }

    moveFileToResultList(key: number, type: FinishedUploadType) {
        this.finishedUploads.set(key, type);
        this.inProgressUploads.delete(key);
        this.updateProgressBarUI();
    }

    hasFilesInResultList() {
        return this.finishedUploads.size > 0;
    }

    private updateProgressBarUI() {
        const {
            setPercentComplete,
            setUploadCounter,
            setInProgressUploads,
            setFinishedUploads,
        } = this.progressUpdater;
        setUploadCounter({
            finished: this.filesUploadedCount,
            total: this.totalFilesCount,
        });
        let percentComplete =
            this.perFileProgress *
            (this.finishedUploads.size || this.filesUploadedCount);

        // eslint-disable-next-line @typescript-eslint/no-unused-vars
        for (const [_, progress] of this.inProgressUploads) {
            // filter  negative indicator values during percentComplete calculation
            if (progress < 0) {
                continue;
            }
            percentComplete += (this.perFileProgress * progress) / 100;
        }

        setPercentComplete(percentComplete);
        setInProgressUploads(
            convertInProgressUploadsToList(this.inProgressUploads),
        );
        setFinishedUploads(groupByResult(this.finishedUploads));
    }

    /**
     * Update the upload progress shown in the UI to {@link percentage} for the
     * file with the given {@link fileLocalID}.
     *
     * @param percentage The upload completion percentage. It should be a value
     * between 0 and 100 (inclusive).
     */
    updateUploadProgress(fileLocalID: number, percentage: number) {
        this.inProgressUploads.set(fileLocalID, Math.round(percentage));
        this.updateProgressBarUI();
    }
}

function convertInProgressUploadsToList(inProgressUploads: InProgressUploads) {
    return [...inProgressUploads.entries()].map(([localFileID, progress]) => ({
        localFileID,
        progress,
    }));
}

const groupByResult = (finishedUploads: FinishedUploads) => {
    const groups: SegregatedFinishedUploads = new Map();
    for (const [localID, result] of finishedUploads) {
        if (!groups.has(result)) groups.set(result, []);
        groups.get(result)!.push(localID);
    }
    return groups;
};

class UploadManager {
    // eslint-disable-next-line @typescript-eslint/no-unsafe-assignment
    private comlinkCryptoWorkers: ComlinkWorker<typeof CryptoWorker>[] =
        new Array(maxConcurrentUploads);
    private parsedMetadataJSONMap = new Map<string, ParsedMetadataJSON>();
    private itemsToBeUploaded: ClusteredUploadItem[] = [];
    private failedItems: ClusteredUploadItem[] = [];
    private existingFiles: EnteFile[] = [];
    private itemResults: UploadBatchItemResult[] = [];
    private onUploadFile: ((file: EnteFile) => void) | undefined;
    private collections = new Map<number, Collection>();
    private uploadInProgress = false;
    private fatalUploadError: Error | undefined;
    /**
     * When `true`, then the next call to {@link abortIfCancelled} will throw.
     *
     * See: [Note: Upload cancellation].
     */
    private shouldUploadBeCancelled = false;

    private uiService = new UIService();

    public init(
        progressUpdater: ProgressUpdater,
        onUploadFile: (file: EnteFile) => void,
    ) {
        this.uiService.init(progressUpdater);
        UploadService.init(undefined);
        this.onUploadFile = onUploadFile;
    }

    logout() {
        // TODO: Consolidate state in one place instead of spreading it.
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
        // eslint-disable-next-line @typescript-eslint/no-unsafe-assignment
        this.parsedMetadataJSONMap = parsedMetadataJSONMap ?? new Map();
        this.shouldUploadBeCancelled = false;
        this.fatalUploadError = undefined;

        this.uiService.reset();
        this.uiService.setUploadPhase("preparing");
    }

    showUploadProgressDialog() {
        this.uiService.setUploadProgressView(true);
    }

    hideUploadProgressDialog() {
        this.uiService.setUploadProgressView(false);
    }

    /**
     * Upload files
     *
     * This method waits for all the files to get uploaded (successfully or
     * unsuccessfully) before returning.
     *
     * It is an error to call this method when there is already an in-progress
     * upload.
     *
     * @param itemsWithCollection The items to upload, each paired with the id
     * of the collection that they should be uploaded into.
     *
     * @param collections The collections to which the files are being uploaded.
     *
     * These are not all the user's collections - these are just the collections
     * mentioned by one or more {@link itemsWithCollection}.
     *
     * @returns A summary of the completed batch and the per-item upload
     * results for the files that were attempted.
     */
    public async uploadItems(
        itemsWithCollection: UploadItemWithCollection[],
        collections: Collection[],
        options?: UploadItemsOptions,
    ): Promise<UploadBatchResult> {
        if (this.uploadInProgress)
            throw new Error("Cannot run multiple uploads at once");

        log.info(`Uploading ${itemsWithCollection.length} files`);
        this.uploadInProgress = true;

        const logInterval = setInterval(logAboutMemoryPressureIfNeeded, 1000);

        try {
            await this.updateExistingFilesAndCollections(collections);

            const namedItems = itemsWithCollection.map(
                makeUploadItemWithCollectionIDAndName,
            );

            this.uiService.setFiles(namedItems);

            const [metadataItems, mediaItems] =
                splitMetadataAndMediaItems(namedItems);

            if (metadataItems.length) {
                this.uiService.setUploadPhase("readingMetadata");
                await this.parseMetadataJSONFiles(metadataItems);
            }

            if (mediaItems.length) {
                const clusteredMediaItems = await clusterLivePhotos(
                    mediaItems,
                    this.parsedMetadataJSONMap,
                );

                this.abortIfCancelled();

                // Live photos might've been clustered together, reset the list
                // of files to reflect that.
                this.uiService.setFiles(clusteredMediaItems);

                this.uiService.setHasLivePhoto(
                    mediaItems.length != clusteredMediaItems.length,
                );

                await this.uploadMediaItems(clusteredMediaItems, options);
            }
        } catch (e) {
            if (!isUploadCancelledError(e)) {
                log.error("Upload failed", e);
                throw e;
            }
        } finally {
            this.uiService.setUploadPhase("done");
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
            processedAny: this.uiService.hasFilesInResultList(),
            itemResults: [...this.itemResults],
        };
    }

    /**
     * Upload a single file to the given collection.
     *
     * @param file A web {@link File} object representing the file to upload.
     *
     * @param collection The {@link Collection} in which the file should be
     * added.
     *
     * @param sourceEnteFile The {@link EnteFile} from which the file being
     * uploaded has been derived. This is used to extract and reassociated
     * relevant metadata to the newly uploaded file.
     */
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

        // Canvas exports do not retain the original file's embedded metadata, so
        // preserve the metadata Ente already knows about the source file.
        //
        // Preserve the richer creationDate when available so the edited copy
        // retains the original photo's local capture date/time semantics (and
        // optional offset), not just the raw UTC timestamp.
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
        this.uiService.reset(items.length);

        for (const item of items) {
            this.abortIfCancelled();

            const { uploadItem, pathPrefix, fileName, collectionID } = item;
            log.info(`Parsing metadata JSON ${fileName}`);
            const metadataJSON = await tryParseTakeoutMetadataJSON(uploadItem!);
            if (metadataJSON) {
                const key = metadataJSONMapKeyForJSON(
                    pathPrefix,
                    collectionID,
                    fileName,
                );
                this.parsedMetadataJSONMap.set(key, metadataJSON);
                this.uiService.increaseFileUploaded();
            }
        }
    }

    private async uploadMediaItems(
        mediaItems: ClusteredUploadItem[],
        options?: UploadItemsOptions,
    ) {
        this.itemsToBeUploaded = [...this.itemsToBeUploaded, ...mediaItems];
        this.uiService.reset(mediaItems.length);
        await UploadService.setFileCount(mediaItems.length);
        this.uiService.setUploadPhase("uploading");

        const uploadProcesses = new Array<Promise<void>>();
        for (
            let i = 0;
            i < maxConcurrentUploads && this.itemsToBeUploaded.length > 0;
            i++
        ) {
            this.comlinkCryptoWorkers[i] = createComlinkCryptoWorker();
            const worker = await this.comlinkCryptoWorkers[i]!.remote;
            uploadProcesses.push(this.uploadNextItemInQueue(worker, options));
        }
        await Promise.all(uploadProcesses);
    }

    private async uploadNextItemInQueue(
        worker: CryptoWorker,
        options?: UploadItemsOptions,
    ) {
        const uiService = this.uiService;
        const uploadContext = {
            isCFUploadProxyDisabled: shouldDisableCFUploadProxy(),
            skipDuplicateAddToUploadCollection:
                options?.skipDuplicateAddToUploadCollection,
            includePartnerSharedFiles: options?.includePartnerSharedFiles,
            abortIfCancelled: this.abortIfCancelled.bind(this),
            updateUploadProgress:
                uiService.updateUploadProgress.bind(uiService),
        };

        while (this.itemsToBeUploaded.length > 0) {
            this.abortIfCancelled();
            logAboutMemoryPressureIfNeeded();

            const clusteredItem = this.itemsToBeUploaded.pop()!;
            const { localID, collectionID } = clusteredItem;
            const collection = this.collections.get(collectionID)!;
            const uploadableItem = { ...clusteredItem, collection };

            uiService.setFileProgress(localID, 0);
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

            uiService.moveFileToResultList(localID, finishedUploadType);
            uiService.increaseFileUploaded();
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
                    // Retriable error.
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
        this.uiService.setUploadPhase("cancelling");
        this.shouldUploadBeCancelled = true;
    }

    /**
     * Return the list of failed items from the last upload, along with other
     * state needed to attempt to reupload them.
     */
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

    /**
     * `true` if an upload is currently in-progress (either a bunch of files
     * directly uploaded by the user, or files being uploaded by the folder
     * watch functionality).
     */
    public isUploadInProgress = () => {
        return this.uploadInProgress || watcher.isUploadRunning();
    };
}

/**
 * Singleton instance of {@link UploadManager}.
 */
export const uploadManager = new UploadManager();

/**
 * The data operated on by the intermediate stages of the upload.
 *
 * [Note: Intermediate file types during upload]
 *
 * As files progress through stages, they get more and more bits tacked on to
 * them. These types document the journey.
 *
 * - The input is {@link UploadItemWithCollection}. This can either be a new
 *   {@link UploadItemWithCollection}, in which case it'll only have a
 *   {@link localID}, {@link collectionID} and a {@link uploadItem}. Or it could
 *   be a retry, in which case it'll not have a {@link uploadItem} but instead
 *   will have data from a previous stage (concretely, it'll just be a
 *   relabelled {@link ClusteredUploadItem}), like a snake eating its tail.
 *
 * - Immediately we convert it to {@link UploadItemWithCollectionIDAndName}.
 *   This is to mostly systematize what we have, and also attach a
 *   {@link fileName}.
 *
 * - These then get converted to "assets", whereby both parts of a live photo
 *   are combined. This is a {@link ClusteredUploadItem}.
 *
 * - On to the {@link ClusteredUploadItem} we attach the corresponding
 *   {@link collection}, giving us {@link UploadableUploadItem}. This is what
 *   gets queued and then passed to the {@link upload}.
 */
type UploadItemWithCollectionIDAndName = UploadAsset & {
    /** A unique ID for the duration of the upload */
    localID: number;
    /** The ID of the collection to which this file should be uploaded. */
    collectionID: number;
    /**
     * The name of the file.
     *
     * In case of live photos, this'll be the name of the image part.
     */
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

const splitMetadataAndMediaItems = (
    items: UploadItemWithCollectionIDAndName[],
): [
    metadata: UploadItemWithCollectionIDAndName[],
    media: UploadItemWithCollectionIDAndName[],
] =>
    items.reduce(
        ([metadata, media], f) => {
            if (lowercaseExtension(f.fileName) == "json") metadata.push(f);
            else media.push(f);
            return [metadata, media];
        },
        [
            new Array<UploadItemWithCollectionIDAndName>(),
            new Array<UploadItemWithCollectionIDAndName>(),
        ],
    );

/**
 * Go through the given files, combining any sibling image + video assets into a
 * single live photo when appropriate.
 */
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
            // They may already be a live photo (we might be retrying a
            // previously failed upload).
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

export const uploadableMediaCount = async (
    itemGroups: UploadItemAndPath[][],
): Promise<{ count: number; isTakeout: boolean }> => {
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

    for (const {
        uploadItem,
        pathPrefix,
        collectionID,
        fileName,
    } of metadataItems) {
        const metadataJSON = await tryParseTakeoutMetadataJSON(uploadItem!);
        if (metadataJSON) {
            parsedMetadataJSONMap.set(
                metadataJSONMapKeyForJSON(pathPrefix, collectionID, fileName),
                metadataJSON,
            );
        }
    }

    return {
        count: (await clusterLivePhotos(mediaItems, parsedMetadataJSONMap))
            .length,
        // The presence of Takeout metadata JSONs amongst the uploaded items
        // indicates that this is a Google Takeout import.
        isTakeout: parsedMetadataJSONMap.size > 0,
    };
};

/**
 * Add logs if our usage increases some high water mark. This is solely so that
 * we have some indication in the logs if we get a user report of OOM crashes.
 */
const logAboutMemoryPressureIfNeeded = () => {
    if (!globalThis.electron) return;

    // performance.memory is deprecated in general as a Web standard, and is
    // also not available in the DOM types provided by TypeScript. However, it
    // is the method recommended by the Electron team (see the link about the V8
    // memory cage). The embedded Chromium supports it fine though, we just need
    // to goad TypeScript to accept the type.

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
