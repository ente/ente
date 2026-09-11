// TODO: Audit this file
// TODO: Too many null assertions in this file. The types need reworking.
import { savedPublicCollectionFiles } from "@/public-album/data/storage/public-albums-fdb";
import {
    shouldDisableCFUploadProxy,
    type ClusteredUploadItem,
    type UploadPhase,
    type UploadResult,
    type UploadableUploadItem,
} from "@/public-album/upload/pipeline";
import {
    metadataJSONMapKeyForJSON,
    tryParseTakeoutMetadataJSON,
    type ParsedMetadataJSON,
} from "@/public-album/upload/pipeline/metadata-json";
import UploadService, {
    areLivePhotoAssets,
    isUploadCancelledError,
    upload,
    uploadCancelledErrorMessage,
    uploadItemFileName,
    type PotentialLivePhotoAsset,
    type UploadAsset,
} from "@/public-album/upload/pipeline/upload-service";
import { createComlinkCryptoWorker } from "ente-base/crypto";
import type { CryptoWorker } from "ente-base/crypto/worker";
import { lowercaseExtension, nameAndExtension } from "ente-base/file-name";
import type { PublicAlbumsCredentials } from "ente-base/http";
import log from "ente-base/log";
import { ComlinkWorker } from "ente-base/worker/comlink-worker";
import type { Collection } from "ente-media/collection";
import type { EnteFile } from "ente-media/file";
import { FileType } from "ente-media/file-type";
import { potentialFileTypeFromExtension } from "ente-media/live-photo";
import { wait } from "ente-utils/promise";

export type FileID = number;

export type PercentageUploaded = number;
export type UploadFileNames = Map<FileID, string>;

export interface UploadCounter {
    finished: number;
    total: number;
}

export interface InProgressUpload {
    localFileID: FileID;
    progress: PercentageUploaded;
}

export type FinishedUploadType = UploadResult["type"];

export type InProgressUploads = Map<FileID, PercentageUploaded>;

export type FinishedUploads = Map<FileID, FinishedUploadType>;

export type SegregatedFinishedUploads = Map<FinishedUploadType, FileID[]>;

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
    setUploadFileNames: React.Dispatch<React.SetStateAction<UploadFileNames>>;
    setHasLivePhotos: React.Dispatch<React.SetStateAction<boolean>>;
}

const maxConcurrentUploads = 4;

// A retried live photo has livePhotoAssets instead of uploadItem.
export type UploadItemWithCollection = UploadAsset & {
    localID: number;
    collectionID: number;
};

class UIService {
    private progressUpdater!: ProgressUpdater;

    private uploadPhase: UploadPhase = "preparing";
    private filenames = new Map<number, string>();
    private hasLivePhoto = false;

    private perFileProgress = 0;
    private filesUploadedCount = 0;
    private totalFilesCount = 0;
    private inProgressUploads: InProgressUploads = new Map();
    private finishedUploads: FinishedUploads = new Map();

    init(progressUpdater: ProgressUpdater) {
        this.progressUpdater = progressUpdater;
        this.progressUpdater.setUploadPhase(this.uploadPhase);
        this.progressUpdater.setUploadFileNames(this.filenames);
        this.progressUpdater.setHasLivePhotos(this.hasLivePhoto);
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
        this.progressUpdater.setUploadFileNames(filenames);
    }

    setHasLivePhoto(hasLivePhoto: boolean) {
        this.hasLivePhoto = hasLivePhoto;
        this.progressUpdater.setHasLivePhotos(hasLivePhoto);
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

        for (const progress of this.inProgressUploads.values()) {
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
    private comlinkCryptoWorkers: ComlinkWorker<typeof CryptoWorker>[] =
        new Array<ComlinkWorker<typeof CryptoWorker>>(maxConcurrentUploads);
    private parsedMetadataJSONMap = new Map<string, ParsedMetadataJSON>();
    private itemsToBeUploaded: ClusteredUploadItem[] = [];
    private failedItems: ClusteredUploadItem[] = [];
    private existingFiles: EnteFile[] = [];
    private onUploadFile: ((file: EnteFile) => void) | undefined;
    private collections = new Map<number, Collection>();
    private uploadInProgress = false;
    private publicAlbumsCredentials: PublicAlbumsCredentials | undefined;
    private uploaderName: string | undefined;
    private shouldUploadBeCancelled = false;

    private uiService = new UIService();

    public init(
        progressUpdater: ProgressUpdater,
        onUploadFile: (file: EnteFile) => void,
        publicAlbumsCredentials: PublicAlbumsCredentials | undefined,
    ) {
        this.uiService.init(progressUpdater);
        UploadService.init(publicAlbumsCredentials);
        this.onUploadFile = onUploadFile;
        this.publicAlbumsCredentials = publicAlbumsCredentials;
    }

    public isUploadRunning() {
        return this.uploadInProgress;
    }

    public prepareForNewUpload(
        parsedMetadataJSONMap?: Map<string, ParsedMetadataJSON>,
    ) {
        this.itemsToBeUploaded = [];
        this.failedItems = [];
        this.parsedMetadataJSONMap =
            parsedMetadataJSONMap ?? new Map<string, ParsedMetadataJSON>();
        this.uploaderName = undefined;
        this.shouldUploadBeCancelled = false;

        this.uiService.reset();
        this.uiService.setUploadPhase("preparing");
    }

    public async uploadItems(
        itemsWithCollection: UploadItemWithCollection[],
        collections: Collection[],
        uploaderName?: string,
    ) {
        if (this.uploadInProgress)
            throw new Error("Cannot run multiple uploads at once");

        log.info(`Uploading ${itemsWithCollection.length} files`);
        this.uploadInProgress = true;
        this.uploaderName = uploaderName;

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

                this.uiService.setFiles(clusteredMediaItems);

                this.uiService.setHasLivePhoto(
                    mediaItems.length != clusteredMediaItems.length,
                );

                await this.uploadMediaItems(clusteredMediaItems);
            }
        } catch (e) {
            if (!isUploadCancelledError(e)) {
                log.error("Upload failed", e);
                throw e;
            }
        } finally {
            this.uiService.setUploadPhase("done");
            for (let i = 0; i < maxConcurrentUploads; i++) {
                this.comlinkCryptoWorkers[i]?.terminate();
            }
            this.uploadInProgress = false;
        }

        return this.uiService.hasFilesInResultList();
    }

    private abortIfCancelled = () => {
        if (this.shouldUploadBeCancelled) {
            throw new Error(uploadCancelledErrorMessage);
        }
    };

    private async updateExistingFilesAndCollections(collections: Collection[]) {
        const credentials = this.publicAlbumsCredentials;
        if (!credentials) {
            throw new Error("Missing public album credentials");
        }

        this.existingFiles = await savedPublicCollectionFiles(
            credentials.accessToken,
        );
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

    private async uploadMediaItems(mediaItems: ClusteredUploadItem[]) {
        this.itemsToBeUploaded = [...this.itemsToBeUploaded, ...mediaItems];
        this.uiService.reset(mediaItems.length);
        UploadService.setFileCount(mediaItems.length);
        this.uiService.setUploadPhase("uploading");

        const uploadProcesses = new Array<Promise<void>>();
        for (
            let i = 0;
            i < maxConcurrentUploads && this.itemsToBeUploaded.length > 0;
            i++
        ) {
            this.comlinkCryptoWorkers[i] = createComlinkCryptoWorker();
            const worker = await this.comlinkCryptoWorkers[i]!.remote;
            uploadProcesses.push(this.uploadNextItemInQueue(worker));
        }
        await Promise.all(uploadProcesses);
    }

    private async uploadNextItemInQueue(worker: CryptoWorker) {
        const uiService = this.uiService;
        const uploadContext = {
            isCFUploadProxyDisabled: shouldDisableCFUploadProxy(),
            publicAlbumsCredentials: this.publicAlbumsCredentials,
            abortIfCancelled: this.abortIfCancelled.bind(this),
            updateUploadProgress:
                uiService.updateUploadProgress.bind(uiService),
        };

        while (this.itemsToBeUploaded.length > 0) {
            this.abortIfCancelled();

            const clusteredItem = this.itemsToBeUploaded.pop()!;
            const { localID, collectionID } = clusteredItem;
            const collection = this.collections.get(collectionID)!;
            const uploadableItem = { ...clusteredItem, collection };

            uiService.setFileProgress(localID, 0);
            await wait(0);

            const uploadResult = await upload(
                uploadableItem,
                this.uploaderName,
                this.existingFiles,
                this.parsedMetadataJSONMap,
                worker,
                uploadContext,
            );

            const finishedUploadType = this.postUploadTask(
                uploadableItem,
                uploadResult,
            );

            uiService.moveFileToResultList(localID, finishedUploadType);
            uiService.increaseFileUploaded();
            UploadService.reducePendingUploadCount();
        }
    }

    private postUploadTask(
        uploadableItem: UploadableUploadItem,
        uploadResult: UploadResult,
    ): FinishedUploadType {
        const type = uploadResult.type;
        log.info(`Upload ${uploadableItem.fileName} | ${type}`);

        switch (uploadResult.type) {
            case "failed":
            case "blocked":
                this.failedItems.push(uploadableItem);
                break;

            case "uploaded":
            case "uploadedWithStaticThumbnail":
                this.updateExistingFiles(uploadResult.file);
                break;
        }

        return type;
    }

    public cancelRunningUpload() {
        log.info("User cancelled upload");
        this.uiService.setUploadPhase("cancelling");
        this.shouldUploadBeCancelled = true;
    }

    public failedItemState() {
        return {
            items: [...this.failedItems],
            collections: [...this.collections.values()],
            parsedMetadataJSONMap: this.parsedMetadataJSONMap,
        };
    }

    public getUploaderName() {
        return this.uploaderName;
    }

    private updateExistingFiles(file: EnteFile) {
        this.existingFiles.push(file);
        this.onUploadFile!(file);
    }

    public isUploadInProgress = () => {
        return this.uploadInProgress;
    };
}

export const uploadManager = new UploadManager();

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

const clusterLivePhotos = async (
    _items: UploadItemWithCollectionIDAndName[],
    parsedMetadataJSONMap: Map<string, ParsedMetadataJSON>,
) => {
    const result: ClusteredUploadItem[] = [];
    type ItemAsset = PotentialLivePhotoAsset & {
        localID: number;
        isLivePhoto?: boolean;
    };
    const items: ItemAsset[] = _items.map((item) => ({
        localID: item.localID,
        isLivePhoto: item.isLivePhoto,
        fileName: item.fileName,
        fileType: potentialFileTypeFromExtension(item.fileName) ?? -1,
        collectionID: item.collectionID,
        uploadItem: item.uploadItem!,
        pathPrefix: item.pathPrefix,
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
                livePhotoAssets: {
                    image: image.uploadItem,
                    video: video.uploadItem,
                },
            });
            index += 2;
        } else {
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
