import { expose, wrap } from "comlink";
import { clientIdentifier } from "ente-base/app";
import { assertionFailed } from "ente-base/assert";
import { isNamedError, namedError } from "ente-base/error";
import { lowercaseExtension } from "ente-base/file-name";
import { isHTTP4xxError, isHTTPErrorWithStatus } from "ente-base/http";
import log from "ente-base/log";
import { logUnhandledErrorsAndRejectionsInWorker } from "ente-base/log-web";
import type {
    ElectronMLWorker,
    MLWorkerAnalyzeImageRequest,
    MLWorkerAnalyzeImageResult,
} from "ente-base/types/ipc";
import { isNetworkDownloadError } from "ente-gallery/services/download";
import type { ProcessableUploadItem } from "ente-gallery/services/upload";
import { fileLogID, type EnteFile } from "ente-media/file";
import { fileFileName } from "ente-media/file-metadata";
import { FileType } from "ente-media/file-type";
import { needsJPEGConversion } from "ente-media/formats";
import { savedTrashItemFileIDs } from "ente-new/photos/services/trash";
import { wait } from "ente-utils/promise";
import { savedCollectionFiles } from "../photos-fdb";
import {
    fetchIndexableImageSource,
    renderableImageBytes,
    type IndexableImageSource,
} from "./blob";
import {
    _clipMatches,
    clearCachedCLIPIndexes,
    clipIndexingVersion,
    type CLIPIndex,
} from "./clip";
import {
    _clusterFaces,
    reconcileClusters,
    type ClusterFacesReason,
    type ClusteringProgress,
} from "./cluster";
import { saveFaceCropBlobs } from "./crop";
import {
    markIndexingFailed,
    readNextIndexableFileIDs,
    savedFaceIndexes,
    saveIndexes,
    updateAssumingLocalFiles,
} from "./db";
import { faceIndexingVersion, type FaceIndex } from "./face";
import { mlIndexFlagsForRustResult } from "./index-flags";
import {
    fetchMLData,
    putMLData,
    type RawRemoteMLData,
    type RemoteMLData,
} from "./ml-data";
import { _suggestionsAndChoicesForPerson, type CGroupPerson } from "./people";
import type { CLIPMatches, MLWorkerDelegate } from "./worker-types";

export type WorkerState = "init" | "idle" | "tick" | "indexing" | "fetching";

const idleDurationStart = 5;
const idleDurationMax = 16 * 60;

interface IndexableItem {
    file: EnteFile;
    processableUploadItem: ProcessableUploadItem | undefined;
    remoteMLData: RemoteMLData | undefined;
}

export class MLWorker {
    public state: WorkerState = "init";
    public clusteringProgress: ClusteringProgress | undefined;

    private electron: ElectronMLWorker | undefined;
    private delegate: MLWorkerDelegate | undefined;
    private liveQ: IndexableItem[] = [];
    private idleTimeout: ReturnType<typeof setTimeout> | undefined;
    private idleDuration = idleDurationStart;
    private onNextIdles: {
        resolve: (count: number) => void;
        reject: (e: Error) => void;
    }[] = [];
    private countSinceLastIdle = 0;

    init(port: MessagePort, delegate: MLWorkerDelegate) {
        this.electron = wrap<ElectronMLWorker>(port);
        this.delegate = delegate;
        port.addEventListener("close", () => this.electronPortDidClose(), {
            once: true,
        });
    }

    private electronPortDidClose() {
        // Reject waiters or the main sync would hang forever.
        const onNextIdles = this.onNextIdles;
        this.onNextIdles = [];
        onNextIdles.forEach(({ reject }) =>
            reject(new Error("The ML utility process exited")),
        );
        this.delegate?.workerDidLoseElectronPort();
    }

    index() {
        if (_blockingMLInitError) return Promise.resolve(0);

        const nextIdle = new Promise<number>((resolve, reject) =>
            this.onNextIdles.push({ resolve, reject }),
        );
        this.wakeUp();
        return nextIdle;
    }

    private wakeUp() {
        if (this.state == "init" || this.state == "idle") {
            if (this.idleTimeout) clearTimeout(this.idleTimeout);
            this.idleTimeout = undefined;
            // Claim the transition before another wakeUp can schedule a tick.
            this.state = "tick";
            void this.tick();
        } else {
            // The current tick schedules the next one.
        }
    }

    onUpload(file: EnteFile, processableUploadItem: ProcessableUploadItem) {
        if (_blockingMLInitError) return;

        this.liveQ.push({
            file,
            processableUploadItem,
            remoteMLData: undefined,
        });
        this.wakeUp();
    }

    async clipMatches(searchPhrase: string): Promise<CLIPMatches | undefined> {
        return _clipMatches(searchPhrase, this.electron!);
    }

    private async tick() {
        log.debug(() => [
            "ml/tick",
            {
                state: this.state,
                liveQ: this.liveQ,
                idleDuration: this.idleDuration,
            },
        ]);

        const scheduleTick = () => void setTimeout(() => this.tick(), 0);

        const liveQ = this.liveQ;
        this.liveQ = [];

        if (this.state != "fetching" && this.state != "indexing")
            this.state = "indexing";

        const items = liveQ.length
            ? liveQ
            : await this.backfillQ().catch((e: unknown) => {
                  log.warn("Ignoring error when determining backfillQ", e);
                  return [];
              });

        if (items.length > 0) {
            const { indexedCount, blockingInitError } = await indexNextBatch(
                items,
                this.electron!,
                this.delegate,
            );
            if (blockingInitError) {
                this.suspendForMLInitError(blockingInitError);
                return;
            }

            this.countSinceLastIdle += items.length;
            if (indexedCount > 0) {
                this.idleDuration = idleDurationStart;
                scheduleTick();
                return;
            }
        }

        this.state = "idle";
        this.idleDuration = Math.min(this.idleDuration * 2, idleDurationMax);
        this.idleTimeout = setTimeout(scheduleTick, this.idleDuration * 1000);
        this.delegate?.workerDidUpdateStatus();

        // Native sessions retain the model memory while idle.
        void this.electron?.releaseMLRuntime().catch((e: unknown) => {
            log.warn("Failed to release the native ML runtime", e);
        });

        this.resolvePendingIndexRequests();
    }

    private suspendForMLInitError(error: Error) {
        log.error(
            "Suspending ML indexing because the native runtime failed to initialize",
            error,
        );
        this.liveQ = [];
        this.state = "idle";
        this.idleTimeout = undefined;
        this.delegate?.workerDidUpdateStatus();
        this.resolvePendingIndexRequests();
    }

    private resolvePendingIndexRequests() {
        const onNextIdles = this.onNextIdles;
        const countSinceLastIdle = this.countSinceLastIdle;
        this.onNextIdles = [];
        this.countSinceLastIdle = 0;
        onNextIdles.forEach(({ resolve }) => resolve(countSinceLastIdle));

        if (onNextIdles.length == 0 && countSinceLastIdle > 0) {
            this.delegate?.workerDidUnawaitedIndex();
        }
    }

    private async backfillQ() {
        const fileByID = await syncWithLocalFilesAndGetFilesToIndex(200);
        if (!fileByID.size) return [];

        const mlDataByID = await fetchMLData(fileByID);

        if (this.state != "indexing" && this.state != "fetching")
            assertionFailed(`Unexpected state ${this.state}`);
        this.state =
            mlDataByID.size * 2 > fileByID.size ? "fetching" : "indexing";

        return Array.from(fileByID, ([id, file]) => ({
            file,
            processableUploadItem: undefined,
            remoteMLData: mlDataByID.get(id),
        }));
    }

    async clusterFaces(masterKey: string, reason: ClusterFacesReason) {
        // Face indexing must be complete and cgroups current before this runs.
        const { clusters, modifiedClusterIDs } = await _clusterFaces(
            await savedFaceIndexes(),
            await savedCollectionFiles(),
            (progress) => this.updateClusteringProgress(progress),
            reason,
        );
        await reconcileClusters(clusters, modifiedClusterIDs, masterKey);
        this.updateClusteringProgress(undefined);
    }

    private updateClusteringProgress(progress: ClusteringProgress | undefined) {
        this.clusteringProgress = progress;
        this.delegate?.workerDidUpdateStatus();
    }

    async suggestionsAndChoicesForPerson(
        person: CGroupPerson,
        currentUserID: number,
    ) {
        return _suggestionsAndChoicesForPerson(person, currentUserID);
    }
}

expose(MLWorker);

logUnhandledErrorsAndRejectionsInWorker();

const indexNextBatch = async (
    items: IndexableItem[],
    electron: ElectronMLWorker,
    delegate: MLWorkerDelegate | undefined,
) => {
    if (!self.navigator.onLine) {
        log.info("Skipping ML indexing since we are not online");
        return { indexedCount: 0 };
    }

    let failureCount = 0;

    // Parallelize fetch/decrypt, while native inference remains serialized below.
    const tasks = new Array<Promise<void> | undefined>(4).fill(undefined);

    let i = 0;
    while (i < items.length && !_blockingMLInitError) {
        for (let j = 0; j < tasks.length; j++) {
            if (i < items.length && !tasks[j]) {
                tasks[j] = ((item: IndexableItem, j: number) =>
                    index(item, electron)
                        .then(() => {
                            tasks[j] = undefined;
                        })
                        .catch((e: unknown) => {
                            const f = fileLogID(item.file);
                            log.error(`Failed to index ${f}`, e);
                            if (isMLInitError(e)) {
                                _blockingMLInitError ??= e;
                            }
                            failureCount++;
                            tasks[j] = undefined;
                        }))(items[i++]!, j);
            }
        }

        await Promise.race(tasks.filter((task) => task !== undefined));

        delegate?.workerDidUpdateStatus();

        await wait(0);
    }

    await Promise.all(tasks.filter((task) => task !== undefined));

    clearCachedCLIPIndexes();

    const attemptedCount = i;
    const indexedCount = attemptedCount - failureCount;

    log.info(
        failureCount > 0
            ? `Indexed ${indexedCount} files (${failureCount} failed)`
            : `Indexed ${attemptedCount} files`,
    );

    return { indexedCount, blockingInitError: _blockingMLInitError };
};

const syncWithLocalFilesAndGetFilesToIndex = async (
    count: number,
): Promise<Map<number, EnteFile>> => {
    const collectionFiles = await savedCollectionFiles();
    const fileByID = new Map(collectionFiles.map((f) => [f.id, f]));

    await updateAssumingLocalFiles(
        Array.from(fileByID.keys()),
        await savedTrashItemFileIDs(),
    );

    const fileIDsToIndex = await readNextIndexableFileIDs(count);
    return new Map(fileIDsToIndex.map((id) => [id, fileByID.get(id)!]));
};

const maxIndexableFileSize = 100 * 1000 * 1000;
const index = async (
    { file, processableUploadItem, remoteMLData }: IndexableItem,
    electron: ElectronMLWorker,
) => {
    const f = fileLogID(file);
    const fileID = file.id;

    const existingRemoteFaceIndex = remoteMLData?.parsed?.face;
    const existingRemoteCLIPIndex = remoteMLData?.parsed?.clip;

    let existingFaceIndex: FaceIndex | undefined;
    if (
        existingRemoteFaceIndex &&
        existingRemoteFaceIndex.version >= faceIndexingVersion
    ) {
        const { width, height, faces } = existingRemoteFaceIndex;
        existingFaceIndex = { width, height, faces };
    }

    let existingCLIPIndex: CLIPIndex | undefined;
    if (
        existingRemoteCLIPIndex &&
        existingRemoteCLIPIndex.version >= clipIndexingVersion
    ) {
        const { embedding } = existingRemoteCLIPIndex;
        existingCLIPIndex = { embedding };
    }

    if (existingFaceIndex && existingCLIPIndex) {
        await saveIndexes(
            { fileID, ...existingFaceIndex },
            { fileID, ...existingCLIPIndex },
        );
        return;
    }

    let source: IndexableImageSource;
    try {
        // Videos use thumbnails, so their original file size is irrelevant.
        if (
            file.metadata.fileType != FileType.video &&
            (file.info?.fileSize ?? 0) > maxIndexableFileSize
        ) {
            throw new Error(
                `File too large to index (${file.info?.fileSize} bytes)`,
            );
        }
        source = await fetchIndexableImageSource(
            file,
            processableUploadItem,
            electron,
        );
    } catch (e) {
        // Network failures retry; failures inherent to the file do not.
        if (!isNetworkDownloadError(e)) await markIndexingFailed(fileID);
        throw e;
    }

    const runFaces = !existingFaceIndex;
    const runClip = !existingCLIPIndex;

    const startTime = Date.now();

    let result: MLWorkerAnalyzeImageResult;
    try {
        result = await analyzeImageWithConversionFallback(
            file,
            source,
            { runFaces, runClip },
            electron,
        );
    } catch (e) {
        // Runtime failures retry after repair; image failures are permanent.
        if (isMLImageError(e)) await markIndexingFailed(fileID);
        throw e;
    }

    const faceIndex = existingFaceIndex ?? faceIndexFromAnalysisResult(result);
    const clipIndex = existingCLIPIndex ?? clipIndexFromAnalysisResult(result);
    const indexFlags = mlIndexFlagsForRustResult(result);

    log.debug(() => {
        const ms = Date.now() - startTime;
        const msg = [];
        if (runFaces) msg.push(`${faceIndex.faces.length} faces`);
        if (runClip) msg.push("clip");
        return `Indexed ${msg.join(" and ")} in ${f} (${ms} ms)`;
    });

    const remoteFaceIndex =
        existingFaceIndex && existingRemoteFaceIndex
            ? existingRemoteFaceIndex
            : {
                  version: faceIndexingVersion,
                  client: clientIdentifier,
                  flags: indexFlags,
                  ...faceIndex,
              };

    const remoteCLIPIndex =
        existingCLIPIndex && existingRemoteCLIPIndex
            ? existingRemoteCLIPIndex
            : {
                  version: clipIndexingVersion,
                  client: clientIdentifier,
                  flags: indexFlags,
                  ...clipIndex,
              };

    // Preserve fields added by newer clients when upserting known indexes.
    const existingRawMLData = remoteMLData?.raw ?? {};
    const rawMLData: RawRemoteMLData = {
        ...existingRawMLData,
        ...(existingFaceIndex ? {} : { face: remoteFaceIndex }),
        ...(existingCLIPIndex ? {} : { clip: remoteCLIPIndex }),
    };

    log.debug(() => ["Uploading ML data", rawMLData]);

    try {
        const lastUpdatedAt = remoteMLData?.updatedAt ?? 0;
        await putMLData(file, rawMLData, lastUpdatedAt);
    } catch (e) {
        // 4xx is permanent except 409, which means the data already exists.
        if (isHTTP4xxError(e)) {
            if (!isHTTPErrorWithStatus(e, 409)) {
                await markIndexingFailed(fileID);
            }
        }
        throw e;
    }

    await saveIndexes({ fileID, ...faceIndex }, { fileID, ...clipIndex });

    // Crop caching is best-effort and must not invalidate a saved index.
    if (runFaces && result.faceCrops) {
        try {
            await saveFaceCropBlobs(result.faceCrops, faceIndex);
        } catch (e) {
            log.error(`Failed to save face crops for ${f}`, e);
        }
    }
};

const petsIndexingEnabled = false;

const analyzeImageWithConversionFallback = async (
    file: EnteFile,
    source: IndexableImageSource,
    { runFaces, runClip }: { runFaces: boolean; runClip: boolean },
    electron: ElectronMLWorker,
): Promise<MLWorkerAnalyzeImageResult> => {
    const request = {
        fileID: file.id,
        runFaces,
        runClip,
        runPets: petsIndexingEnabled,
        generateFaceCrops: runFaces,
    };

    try {
        return await enqueueAnalyzeImage(electron, { ...request, ...source });
    } catch (e) {
        // Native decode failures for rare formats get one JPEG fallback.
        const ext = lowercaseExtension(fileFileName(file));
        if (!isMLDecodeError(e) || !ext || !needsJPEGConversion(ext)) throw e;

        log.info(
            `Native decode of ${fileLogID(file)} failed, retrying with a JPEG conversion`,
            e,
        );
        let bytes: Uint8Array;
        try {
            bytes = await renderableImageBytes(file, source);
        } catch (conversionError) {
            const message =
                conversionError instanceof Error
                    ? conversionError.message
                    : String(conversionError);
            throw namedError(
                "ml_image",
                `JPEG conversion fallback failed: ${message}`,
            );
        }
        return await enqueueAnalyzeImage(electron, { ...request, bytes });
    }
};

const isMLImageError = (e: unknown): e is Error =>
    isNamedError(e, "ml_decode") || isNamedError(e, "ml_image");

const isMLDecodeError = (e: unknown) => isNamedError(e, "ml_decode");

const isMLInitError = (e: unknown): e is Error => isNamedError(e, "ml_init");

// Native model sessions serialize anyway; keep only one inference outstanding.
let _analyzeImageQueue: Promise<unknown> = Promise.resolve();

let _blockingMLInitError: Error | undefined;

const enqueueAnalyzeImage = (
    electron: ElectronMLWorker,
    request: MLWorkerAnalyzeImageRequest,
): Promise<MLWorkerAnalyzeImageResult> => {
    const result = _analyzeImageQueue.then(() =>
        electron.analyzeImage(request),
    );
    _analyzeImageQueue = result.catch(() => undefined);
    return result;
};

// Convert native typed arrays before serializing either index.
const faceIndexFromAnalysisResult = (
    result: MLWorkerAnalyzeImageResult,
): FaceIndex => {
    const faces = result.faces;
    if (!faces) throw new Error("Analysis result is missing the face index");

    const { width, height } = result.decodedImageSize;

    return {
        width,
        height,
        faces: faces.map((face) => ({
            faceID: face.faceId,
            detection: {
                box: {
                    x: face.detection.boxXyxy[0]!,
                    y: face.detection.boxXyxy[1]!,
                    width:
                        face.detection.boxXyxy[2]! - face.detection.boxXyxy[0]!,
                    height:
                        face.detection.boxXyxy[3]! - face.detection.boxXyxy[1]!,
                },
                landmarks: face.detection.keypoints.map((point) => ({
                    x: point[0]!,
                    y: point[1]!,
                })),
            },
            score: face.detection.score,
            blur: face.blurValue,
            embedding: Array.from(face.embedding),
        })),
    };
};

const clipIndexFromAnalysisResult = (
    result: MLWorkerAnalyzeImageResult,
): CLIPIndex => {
    const embedding = result.clip?.embedding;
    if (!embedding)
        throw new Error("Analysis result is missing the CLIP embedding");
    return { embedding: Array.from(embedding) };
};
