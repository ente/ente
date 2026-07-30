import { expose, wrap } from "comlink";
import { clientIdentifier } from "ente-base/app";
import { assertionFailed } from "ente-base/assert";
import { lowercaseExtension } from "ente-base/file-name";
import { isHTTP4xxError, isHTTPErrorWithStatus } from "ente-base/http";
import log from "ente-base/log";
import { logUnhandledErrorsAndRejectionsInWorker } from "ente-base/log-web";
import type {
    ElectronMLWorker,
    MLWorkerAnalyzeImageErrorKind,
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

/**
 * A rough hint at what the worker is up to.
 *
 * - "init": Worker has been created but hasn't done anything yet.
 * - "idle": Not doing anything
 * - "tick": Transitioning to a new state
 * - "indexing": Indexing
 * - "fetching": A subset of indexing
 *
 * During indexing, the state is set to "fetching" whenever remote provided us
 * data for more than 50% of the files that we requested from it in the last
 * fetch during indexing.
 */
export type WorkerState = "init" | "idle" | "tick" | "indexing" | "fetching";

const idleDurationStart = 5; /* 5 seconds */
const idleDurationMax = 16 * 60; /* 16 minutes */

interface IndexableItem {
    /**
     * The {@link EnteFile} to (potentially) index.
     */
    file: EnteFile;
    /**
     * If the file was uploaded from the current client, then its contents.
     */
    processableUploadItem: ProcessableUploadItem | undefined;
    /**
     * The existing ML data (if any) on remote corresponding to this file.
     */
    remoteMLData: RemoteMLData | undefined;
}

/**
 * Run operations related to machine learning (e.g. indexing) in a Web Worker.
 *
 * This is a normal class that is however exposed (via comlink) as a proxy
 * running inside a Web Worker. This way, we do not bother the main thread with
 * tasks that might degrade interactivity.
 *
 * Conceptually, the MLWorker state machine is as follows:
 *
 *     ext. event      state           then state
 *    ------------- --------------- --------------
 *     sync         -> "backfillq"  -> "idle"
 *     upload       -> "liveq"      -> "idle"
 *     idleTimeout  -> "backfillq"  -> "idle"
 *
 * where:
 *
 * - "liveq": indexing items that are being uploaded,
 * - "backfillq": index unindexed items otherwise.
 * - "idle": in between state transitions.
 *
 * In addition, MLWorker can also be invoked for interactive tasks: in
 * particular, for finding the closest CLIP match when the user does a search.
 */
export class MLWorker {
    /** The last known state of the worker. */
    public state: WorkerState = "init";
    /** If the worker is currently clustering, then its last known progress. */
    public clusteringProgress: ClusteringProgress | undefined;

    private electron: ElectronMLWorker | undefined;
    private delegate: MLWorkerDelegate | undefined;
    private liveQ: IndexableItem[] = [];
    private idleTimeout: ReturnType<typeof setTimeout> | undefined;
    private idleDuration = idleDurationStart; /* unit: seconds */
    /** Settlers for pending promises returned from calls to {@link index}. */
    private onNextIdles: {
        resolve: (count: number) => void;
        reject: (e: Error) => void;
    }[] = [];
    /**
     * Number of items processed since the last time {@link onNextIdles} was
     * drained.
     */
    private countSinceLastIdle = 0;

    /**
     * Initialize a new {@link MLWorker}.
     *
     * This is conceptually the constructor, however it is easier to have this
     * as a separate function to avoid complicating the comlink types further.
     *
     * @param port A {@link MessagePort} that allows us to communicate with an
     * Electron utility process running in the Node.js layer of our desktop app,
     * exposing an object that conforms to the {@link ElectronMLWorker}
     * interface.
     *
     * @param delegate The {@link MLWorkerDelegate} the worker can use to inform
     * the main thread of interesting events.
     */
    init(port: MessagePort, delegate: MLWorkerDelegate) {
        this.electron = wrap<ElectronMLWorker>(port);
        this.delegate = delegate;
        port.addEventListener("close", () => this.electronPortDidClose(), {
            once: true,
        });
    }

    /**
     * Called when the port to the ML utility process closes, which happens if
     * the utility process exits (e.g. if it crashes).
     *
     * Reject any pending promises returned by {@link index} so that a sync
     * awaiting us doesn't hang forever, then inform the main thread, which
     * will discard us. Anything else in flight dies with us; the next sync
     * will retry with a new worker.
     */
    private electronPortDidClose() {
        const onNextIdles = this.onNextIdles;
        this.onNextIdles = [];
        onNextIdles.forEach(({ reject }) =>
            reject(new Error("The ML utility process exited")),
        );
        this.delegate?.workerDidLoseElectronPort();
    }

    /**
     * Start backfilling if needed, and return after there are no more items
     * remaining to backfill.
     *
     * During a backfill, we first attempt to fetch ML data for files which
     * don't have that data locally. If on fetching we find what we need, we
     * save it locally. Otherwise we index them.
     *
     * @return The count of items processed since the last last time we were
     * idle. The returned promise rejects if the port to the ML utility process
     * closes while we're indexing.
     */
    index() {
        if (_blockingMLInitError) return Promise.resolve(0);

        const nextIdle = new Promise<number>((resolve, reject) =>
            this.onNextIdles.push({ resolve, reject }),
        );
        this.wakeUp();
        return nextIdle;
    }

    /** Invoked in response to external events. */
    private wakeUp() {
        if (this.state == "init" || this.state == "idle") {
            // We are currently paused. Get back to work.
            if (this.idleTimeout) clearTimeout(this.idleTimeout);
            this.idleTimeout = undefined;
            // Change state so that multiple calls to `wakeUp` don't cause
            // multiple calls to `tick`.
            this.state = "tick";
            // Enqueue a tick.
            void this.tick();
        } else {
            // In the middle of a task. Do nothing, `this.tick` will
            // automatically be invoked when the current task finishes.
        }
    }

    /**
     * Called when a file is uploaded from the current client.
     *
     * This is a great opportunity to index since we already have the file with
     * us and won't need to download the file from remote.
     */
    onUpload(file: EnteFile, processableUploadItem: ProcessableUploadItem) {
        if (_blockingMLInitError) return;

        // Add the recently uploaded file to the live indexing queue.
        this.liveQ.push({
            file,
            processableUploadItem,
            remoteMLData: undefined,
        });
        this.wakeUp();
    }

    /**
     * Find {@link CLIPMatches} for a given normalized {@link searchPhrase}.
     */
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

        // Retain the previous state if it was one of the indexing states. This
        // prevents jumping between "fetching" and "indexing" being shown in the
        // UI during the initial load.
        if (this.state != "fetching" && this.state != "indexing")
            this.state = "indexing";

        // Use the liveQ if present, otherwise get the next batch to backfill.
        const items = liveQ.length
            ? liveQ
            : await this.backfillQ().catch((e: unknown) => {
                  // Ignore the error (e.g. a network failure) when determining
                  // the items to backfill, and return an empty items array so
                  // that the next retry happens after an exponential backoff.
                  log.warn("Ignoring error when determining backfillQ", e);
                  return [];
              });

        // If there is items remaining,
        if (items.length > 0) {
            // Index them.
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
                // We made some progress, so there are no complete blockers
                // (e.g. network being offline). Reset the idle duration and
                // move on to the next batch (if any).
                this.idleDuration = idleDurationStart;
                // And tick again.
                scheduleTick();
                return;
            }
        }

        // We come here in three scenarios - either there is nothing left to do,
        // or we cannot currently do it (e.g. user is offline), or we
        // encountered failures during indexing.
        //
        // Failures are not really expected, so something unexpected might be
        // going on, or remote might be having issues.
        //
        // So in all cases, we pause for exponentially longer durations of time
        // (limited to some maximum).

        this.state = "idle";
        this.idleDuration = Math.min(this.idleDuration * 2, idleDurationMax);
        this.idleTimeout = setTimeout(scheduleTick, this.idleDuration * 1000);
        this.delegate?.workerDidUpdateStatus();

        // Release the native ML sessions while we're idling so that the
        // utility process doesn't hold on to the model memory. They get
        // recreated transparently on the next analysis.
        void this.electron?.releaseMLRuntime().catch((e: unknown) => {
            log.warn("Failed to release the native ML runtime", e);
        });

        this.resolvePendingIndexRequests();
    }

    /** Stop indexing until this web worker (and its utility process) is replaced. */
    private suspendForMLInitError(error: MLAnalyzeError) {
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

    /** Resolve callers waiting for the worker to next become idle. */
    private resolvePendingIndexRequests() {
        const onNextIdles = this.onNextIdles;
        const countSinceLastIdle = this.countSinceLastIdle;
        this.onNextIdles = [];
        this.countSinceLastIdle = 0;
        onNextIdles.forEach(({ resolve }) => resolve(countSinceLastIdle));

        // If no one was waiting, then let the main thread know via a different
        // channel so that it can update the clusters and people.
        if (onNextIdles.length == 0 && countSinceLastIdle > 0) {
            this.delegate?.workerDidUnawaitedIndex();
        }
    }

    /** Return the next batch of items to backfill (if any). */
    private async backfillQ() {
        // Find files that our local DB thinks need syncing.
        const fileByID = await syncWithLocalFilesAndGetFilesToIndex(200);
        if (!fileByID.size) return [];

        // Fetch their existing ML data (if any).
        const mlDataByID = await fetchMLData(fileByID);

        // If the number of files for which remote gave us data is more than 50%
        // of what we asked of it, assume we are "fetching", not "indexing".
        // This is a heuristic to try and show a better indexing state in the UI
        // (so that the user does not think that their files are being
        // unnecessarily reindexed).
        if (this.state != "indexing" && this.state != "fetching")
            assertionFailed(`Unexpected state ${this.state}`);
        this.state =
            mlDataByID.size * 2 > fileByID.size ? "fetching" : "indexing";

        // Return files after annotating them with their existing ML data.
        return Array.from(fileByID, ([id, file]) => ({
            file,
            processableUploadItem: undefined,
            remoteMLData: mlDataByID.get(id),
        }));
    }

    /**
     * Run face clustering on all faces, and update both local and remote state
     * as appropriate.
     *
     * This should only be invoked when the face indexing (including syncing
     * with remote) is complete so that we cluster the latest set of faces, and
     * after we have fetched the latest cgroups from remote (so that we do no
     * overwrite any remote updates).
     *
     * @param masterKey The user's master key (as a base64 string), required for
     * updating remote cgroups if needed.
     */
    async clusterFaces(masterKey: string, reason: ClusterFacesReason) {
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

    /**
     * Return suggestions and choices for the given cgroup {@link person}.
     */
    async suggestionsAndChoicesForPerson(
        person: CGroupPerson,
        currentUserID: number,
    ) {
        return _suggestionsAndChoicesForPerson(person, currentUserID);
    }
}

expose(MLWorker);

logUnhandledErrorsAndRejectionsInWorker();

/**
 * Index the given batch of items.
 *
 * @returns the number of indexed items and any process-blocking init error.
 */
const indexNextBatch = async (
    items: IndexableItem[],
    electron: ElectronMLWorker,
    delegate: MLWorkerDelegate | undefined,
) => {
    // Don't try to index if we wouldn't be able to upload them anyway. The
    // liveQ has already been drained, but that's fine, it'll be rare that we
    // were able to upload just a bit ago but don't have network now.
    if (!self.navigator.onLine) {
        log.info("Skipping ML indexing since we are not online");
        return { indexedCount: 0 };
    }

    // Keep track if any of the items failed.
    let failureCount = 0;

    // Index up to 4 items simultaneously.
    const tasks = new Array<Promise<void> | undefined>(4).fill(undefined);

    let i = 0;
    while (i < items.length && !_blockingMLInitError) {
        for (let j = 0; j < tasks.length; j++) {
            if (i < items.length && !tasks[j]) {
                // Use an IIFE to capture the value of j at the time of
                // invocation.
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

        // Wait for at least one to complete (the other runners continue running
        // even if one promise reaches the finish line).
        await Promise.race(tasks.filter((task) => task !== undefined));

        // Let the main thread now we're doing something.
        delegate?.workerDidUpdateStatus();

        // Let us drain the microtask queue. This also gives a chance for other
        // interactive tasks like `clipMatches` to run.
        await wait(0);
    }

    // Wait for the pending tasks to drain out.
    await Promise.all(tasks.filter((task) => task !== undefined));

    // Clear any cached CLIP indexes, since now we might have new ones.
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

/**
 * Sync face DB with the local (and potentially indexable) files that we know
 * about. Then return the next {@link count} files that still need to be
 * indexed.
 *
 * When returning from amongst pending files, prefer the most recent ones first.
 *
 * For specifics of what a "sync" entails, see {@link updateAssumingLocalFiles}.
 *
 * @param count Limit the resulting list of indexable files to {@link count}.
 */
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

/**
 * The maximum size (in bytes) of files that we will index.
 *
 * The same limit is used by the mobile app.
 */
const maxIndexableFileSize = 100 * 1000 * 1000; /* 100 MB */

/**
 * Index file, save the persist the results locally, and put them on remote.
 *
 * Indexing a file involves computing its various ML embeddings: faces and CLIP.
 * Since we have the original file in memory, we also save the face crops.
 *
 * [Note: Transient and permanent indexing failures]
 *
 * We mark indexing for a file as having failed only if there is a good chance
 * that the indexing failed because of some inherent issue with that particular
 * file, and not if there were generic failures (like when trying to save the
 * indexes to remote).
 *
 * When we mark it as failed, then a flag is persisted corresponding to this
 * file in the ML DB so that it won't get reindexed in future runs. This are
 * thus considered as permanent failures.
 *
 * > We might retry these in future versions if we identify reasons for indexing
 * > to fail (it ideally shouldn't) and rectify them.
 *
 * On the other hand, saving the face index to remote might fail for transient
 * issues (network issues, or remote having hiccups). We don't mark a file as
 * failed permanently in such cases, so that it gets retried at some point.
 * These are considered as transient failures.
 *
 * However, it is vary hard to pre-emptively enumerate all possible failure
 * modes, and there is a the possibility of some non-transient failure getting
 * classified as a transient failure and causing the client to try and index the
 * same file again and again, when in fact there is a issue specific to that
 * file which is preventing the index from being saved. What exactly? We don't
 * know, but the possibility exists.
 *
 * To reduce the chances of this happening, we treat HTTP 4xx responses as
 * permanent failures too - there are no known cases where a client retrying a
 * 4xx response would work, and there are expected (but rare) cases where a
 * client might get a non-retriable 4xx (e.g. if the file has over ~700 faces,
 * then remote will return a 413 Request Entity Too Large).
 */
const index = async (
    { file, processableUploadItem, remoteMLData }: IndexableItem,
    electron: ElectronMLWorker,
) => {
    const f = fileLogID(file);
    const fileID = file.id;

    // Massage the existing data (if any) that we got from remote to the form
    // that the rest of this function operates on.
    //
    // Discard any existing data that is made by an older indexing pipelines.
    // See: [Note: Embedding versions]

    const existingRemoteFaceIndex = remoteMLData?.parsed?.face;
    const existingRemoteCLIPIndex = remoteMLData?.parsed?.clip;

    let existingFaceIndex: FaceIndex | undefined;
    if (
        existingRemoteFaceIndex &&
        existingRemoteFaceIndex.version >= faceIndexingVersion
    ) {
        // Destructure the data we got from remote so that we only retain the
        // fields we're interested in the object that gets put into indexed db.
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

    // If we already have all the ML data types then just update our local db
    // and return.

    if (existingFaceIndex && existingCLIPIndex) {
        await saveIndexes(
            { fileID, ...existingFaceIndex },
            { fileID, ...existingCLIPIndex },
        );
        return;
    }

    // There is at least one ML data type that still needs to be indexed.

    let source: IndexableImageSource;
    try {
        // Videos are indexed using their thumbnails, so the size of the video
        // file itself does not matter.
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
        // Network errors are transient and shouldn't be marked.
        //
        // See: [Note: Transient and permanent indexing failures]
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
        // Only failures inherent to the image (including the JPEG conversion
        // fallback below) are permanent. Runtime and infrastructure failures
        // should be retried after the underlying issue is resolved.
        // See: [Note: Transient and permanent indexing failures]
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

    // Perform an "upsert" by using the existing raw data we got from the
    // remote as the base, and inserting or overwriting only the parts we
    // actually (re)indexed. Preserving the raw entry for a kept
    // face/clip retains any inner keys that the current client's Zod
    // schema doesn't know about (e.g. a `flags` bitmask set by a
    // different client). See: [Note: Preserve unknown ML data fields].

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
        // See: [Note: Transient and permanent indexing failures]
        if (isHTTP4xxError(e)) {
            // 409 Conflict indicates that we tried overwriting existing
            // mldata. Don't mark it as a failure, the file has already been
            // processed.
            if (!isHTTPErrorWithStatus(e, 409)) {
                await markIndexingFailed(fileID);
            }
        }
        throw e;
    }

    await saveIndexes({ fileID, ...faceIndex }, { fileID, ...clipIndex });

    // This step, saving face crops, is conceptually not part of the indexing
    // pipeline; we just do it here since the analysis has already generated
    // the crops for us from its decode of the original.
    if (runFaces && result.faceCrops) {
        try {
            await saveFaceCropBlobs(result.faceCrops, faceIndex);
        } catch (e) {
            // Ignore errors that happen during this since it does not
            // impact the generated face index.
            log.error(`Failed to save face crops for ${f}`, e);
        }
    }
};

/**
 * `true` if the pet recognition models should also run while indexing.
 *
 * Pet recognition is still under development and not yet enabled anywhere.
 * When it ships, this gate should mirror the mobile one (mobile's
 * `flagService.petEnabled` is derived from the remote `internalUser` flag),
 * and the pet results in the analysis response, currently ignored, will need
 * to be persisted.
 */
const petsIndexingEnabled = false;

/**
 * Run the native ML pipeline on the given image source.
 *
 * The native side decodes all common formats (including HEIC, JXL and TIFF)
 * by itself, but not some rarer ones (e.g. camera RAW). For formats which the
 * app handles by converting to JPEG, retry the analysis with the converted
 * JPEG if the native decode reports a failure.
 */
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
            throw new MLAnalyzeError(
                "image",
                `JPEG conversion fallback failed: ${message}`,
            );
        }
        return await enqueueAnalyzeImage(electron, { ...request, bytes });
    }
};

/** `true` for a permanent failure inherent to the image being analyzed. */
const isMLImageError = (e: unknown): e is MLAnalyzeError =>
    e instanceof MLAnalyzeError && e.kind == "image";

/** `true` specifically for the Rust image decoder failure that permits fallback. */
const isMLDecodeError = (e: unknown) =>
    isMLImageError(e) && e.message.startsWith("Decode: ");

const isMLInitError = (e: unknown): e is MLAnalyzeError =>
    e instanceof MLAnalyzeError && e.kind == "init";

class MLAnalyzeError extends Error {
    constructor(
        public readonly kind: MLWorkerAnalyzeImageErrorKind,
        message: string,
    ) {
        super(message);
        this.name = "MLAnalyzeError";
    }
}

/**
 * A promise queue serializing calls to {@link ElectronMLWorker.analyzeImage}.
 *
 * We process multiple files in parallel so that the fetch (and decrypt) of
 * subsequent items can proceed while one is being analyzed, but keep only a
 * single native inference outstanding at a time: the native model sessions
 * serialize anyway, and queueing on our end avoids tying up worker threads in
 * the utility process.
 */
let _analyzeImageQueue: Promise<unknown> = Promise.resolve();

/** The native addon is loaded only once, so this error cannot recover here. */
let _blockingMLInitError: MLAnalyzeError | undefined;

const enqueueAnalyzeImage = (
    electron: ElectronMLWorker,
    request: MLWorkerAnalyzeImageRequest,
): Promise<MLWorkerAnalyzeImageResult> => {
    const result = _analyzeImageQueue.then(async () => {
        const response = await electron.analyzeImage(request);
        if (!response.ok) {
            throw new MLAnalyzeError(
                response.error.kind,
                response.error.message,
            );
        }
        return response.result;
    });
    _analyzeImageQueue = result.catch(() => undefined);
    return result;
};

/**
 * Convert the face related parts of an analysis result into the
 * {@link FaceIndex} shape that we persist and upload.
 *
 * The coordinates in the result are already relative (normalized 0-1), and
 * the faceIDs already have the format that the (legacy) web pipeline used, so
 * this is a mechanical reshaping.
 */
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
            // Keep persisted and remote indexes as ordinary arrays. The
            // native/IPC boundary uses Float32Array to avoid widening and an
            // extra allocation, but JSON does not serialize typed arrays as
            // arrays.
            embedding: Array.from(face.embedding),
        })),
    };
};

/**
 * Extract the CLIP image embedding from an analysis result.
 *
 * The embedding produced by the native pipeline is already normalized.
 */
const clipIndexFromAnalysisResult = (
    result: MLWorkerAnalyzeImageResult,
): CLIPIndex => {
    const embedding = result.clip?.embedding;
    if (!embedding)
        throw new Error("Analysis result is missing the CLIP embedding");
    return { embedding: Array.from(embedding) };
};
