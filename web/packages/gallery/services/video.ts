import { ensureLocalUser } from "ente-accounts/services/user";
import { isDesktop } from "ente-base/app";
import { assertionFailed } from "ente-base/assert";
import { decryptBlobBytes, encryptBlob } from "ente-base/crypto";
import type { EncryptedBlob } from "ente-base/crypto/types";
import { ensureElectron } from "ente-base/electron";
import { isHTTP4xxError, type PublicAlbumsCredentials } from "ente-base/http";
import { getKV, getKVB, getKVN, setKV } from "ente-base/kv";
import log from "ente-base/log";
import { apiURL } from "ente-base/origins";
import type { PublicMemoryCredentials } from "ente-base/public-memory";
import { ensureAuthToken } from "ente-base/token";
import { uniqueFilesByID } from "ente-gallery/utils/file";
import { reconstructHLSPlaylist } from "ente-gallery/utils/hls";
import { fileLogID, type EnteFile } from "ente-media/file";
import { FileType } from "ente-media/file-type";
import { updateFilePublicMagicMetadata } from "ente-new/photos/services/file";
import { savedCollectionFiles } from "ente-new/photos/services/photos-fdb";
import { savedTrashItemFileIDs } from "ente-new/photos/services/trash";
import { gunzip, gzip } from "ente-new/photos/utils/gzip";
import { randomSample } from "ente-utils/array";
import { ensurePrecondition } from "ente-utils/ensure";
import { wait } from "ente-utils/promise";
import { z } from "zod";
import {
    initiateGenerateHLS,
    readVideoStream,
    videoStreamDone,
    type GenerateHLSResult,
} from "../utils/native-stream";
import { downloadManager, isNetworkDownloadError } from "./download";
import {
    fetchFileData,
    fetchFilePreviewData,
    putVideoData,
    syncUpdatedFileDataFileIDs,
} from "./file-data";
import {
    fileSystemUploadItemIfUnchanged,
    type FileSystemUploadItem,
    type ProcessableUploadItem,
    type TimestampedFileSystemUploadItem,
} from "./upload";

export type HLSGenerationEnabledStatus = "processing" | "idle";

export type HLSGenerationStatus =
    | { enabled: false }
    | { enabled: true; status?: HLSGenerationEnabledStatus };

interface VideoProcessingQueueItem {
    file: EnteFile;
    timestampedUploadItem?: TimestampedFileSystemUploadItem;
}

const idleWaitInitial = 10 * 1000;
const idleWaitMax = idleWaitInitial * 2 ** 6;

class VideoState {
    isHLSGenerationEnabled = false;
    hlsGenerationStatusListeners: (() => void)[] = [];
    hlsGenerationStatusSnapshot: HLSGenerationStatus | undefined;
    lastEnabledStatus: HLSGenerationEnabledStatus | undefined;
    liveQueue: VideoProcessingQueueItem[] = [];
    queueProcessor: Promise<void> | undefined;
    tick: Promise<void> | undefined;
    resolveTick: (() => void) | undefined;
    idleWait = idleWaitInitial;
    haveSyncedOnce = false;
}

let _state = new VideoState();

export const resetVideoState = () => {
    // Logout performs a full reload, which aborts any in-flight native work.
    _state = new VideoState();
};

export const hlsGenerationStatusSubscribe = (
    onChange: () => void,
): (() => void) => {
    _state.hlsGenerationStatusListeners.push(onChange);
    return () => {
        _state.hlsGenerationStatusListeners =
            _state.hlsGenerationStatusListeners.filter((l) => l != onChange);
    };
};

export const hlsGenerationStatusSnapshot = () =>
    _state.hlsGenerationStatusSnapshot;

const setHLSGenerationStatusSnapshot = (snapshot: HLSGenerationStatus) => {
    _state.hlsGenerationStatusSnapshot = snapshot;
    _state.hlsGenerationStatusListeners.forEach((l) => l());
};

const updateSnapshotIfNeeded = (
    status: HLSGenerationEnabledStatus | undefined,
) => {
    const enabled = _state.isHLSGenerationEnabled;
    if (enabled && status != _state.lastEnabledStatus) {
        _state.lastEnabledStatus = status;
        setHLSGenerationStatusSnapshot({ enabled, status });
    }
};

export const isHLSGenerationSupported = isDesktop;

export const initVideoProcessing = async () => {
    let enabled = false;
    if (await savedGenerateHLS()) enabled = true;

    _state.isHLSGenerationEnabled = enabled;

    setHLSGenerationStatusSnapshot({ enabled });
};

const savedGenerateHLS = async () => await getKVB("generateHLS");

const saveGenerateHLS = (enabled: boolean) => setKV("generateHLS", enabled);

export const toggleHLSGeneration = async () => {
    if (!isHLSGenerationSupported) {
        assertionFailed();
        return;
    }

    const enabled = !_state.isHLSGenerationEnabled;

    _state.lastEnabledStatus = undefined;

    await saveGenerateHLS(enabled);
    _state.isHLSGenerationEnabled = enabled;

    setHLSGenerationStatusSnapshot({ enabled });

    if (enabled) tickNow();
};

export interface HLSPlaylistData {
    playlistURL: string;
    width: number;
    height: number;
}

// "skip" is stable ineligibility; undefined may become a playlist later.
export type HLSPlaylistDataForFile = HLSPlaylistData | "skip" | undefined;

export const hlsPlaylistDataForFile = async (
    file: EnteFile,
    publicAlbumsCredentials?: PublicAlbumsCredentials,
    publicMemoryCredentials?: PublicMemoryCredentials,
): Promise<HLSPlaylistDataForFile> => {
    ensurePrecondition(file.metadata.fileType == FileType.video);

    if (file.pubMagicMetadata?.data.sv == 1) {
        return "skip";
    }

    const playlistFileData = await fetchFileData(
        "vid_preview",
        file.id,
        publicAlbumsCredentials,
        publicMemoryCredentials,
    );
    if (!playlistFileData) return undefined;

    const {
        type,
        playlist: playlistTemplate,
        width,
        height,
    } = await decryptPlaylistJSON(playlistFileData, file);

    if (type != "hls_video") return undefined;

    const videoURL = await fetchFilePreviewData(
        "vid_preview",
        file.id,
        publicAlbumsCredentials,
        publicMemoryCredentials,
    );
    if (!videoURL) return undefined;

    const playlist = reconstructHLSPlaylist(playlistTemplate, videoURL);
    if (!playlist) {
        log.warn(`Ignoring invalid HLS playlist for ${fileLogID(file)}`);
        return undefined;
    }

    // HLS clients require a recognizable playlist MIME type or filename.
    const playlistURL = await blobToDataURL(
        new Blob([playlist], { type: "application/vnd.apple.mpegurl" }),
    );

    return { playlistURL, width, height };
};

const PlaylistJSON = z.object({
    type: z.string(),
    playlist: z.string(),
    width: z.number(),
    height: z.number(),
    size: z.number(),
});

type PlaylistJSON = z.infer<typeof PlaylistJSON>;

const decryptPlaylistJSON = async (
    encryptedPlaylist: EncryptedBlob,
    file: EnteFile,
) => {
    const decryptedBytes = await decryptBlobBytes(encryptedPlaylist, file.key);
    const jsonString = await gunzip(decryptedBytes);
    return PlaylistJSON.parse(JSON.parse(jsonString));
};

const blobToDataURL = (blob: Blob) =>
    new Promise<string>((resolve) => {
        const reader = new FileReader();
        reader.onload = () => resolve(reader.result as string);
        reader.readAsDataURL(blob);
    });

const savedProcessedVideoFileIDs = () =>
    getKV("videoPreviewProcessedFileIDs").then((v) => new Set(v as number[]));

const savedFailedVideoFileIDs = () =>
    getKV("videoPreviewFailedFileIDs").then((v) => new Set(v as number[]));

const saveProcessedVideoFileIDs = (videoFileIDs: Set<number>) =>
    setKV("videoPreviewProcessedFileIDs", Array.from(videoFileIDs));

const saveFailedVideoFileIDs = (videoFileIDs: Set<number>) =>
    setKV("videoPreviewFailedFileIDs", Array.from(videoFileIDs));

const markProcessedVideoFileID = async (fileID: number) => {
    const savedIDs = await savedProcessedVideoFileIDs();
    const failedIDs = await savedFailedVideoFileIDs();
    savedIDs.add(fileID);
    if (failedIDs.delete(fileID)) await saveFailedVideoFileIDs(failedIDs);
    await saveProcessedVideoFileIDs(savedIDs);
};

const markProcessedVideoFileIDs = async (fileIDs: Set<number>) => {
    const savedIDs = await savedProcessedVideoFileIDs();
    const failedIDs = await savedFailedVideoFileIDs();
    await Promise.all([
        saveProcessedVideoFileIDs(savedIDs.union(fileIDs)),
        saveFailedVideoFileIDs(failedIDs.difference(fileIDs)),
    ]);
};

const markFailedVideoFile = async (file: EnteFile) => {
    log.info(`Generate HLS for ${fileLogID(file)} | failed`);
    const failedIDs = await savedFailedVideoFileIDs();
    failedIDs.add(file.id);
    await saveFailedVideoFileIDs(failedIDs);
};

const savedSyncLastUpdatedAt = () => getKVN("videoPreviewSyncLastUpdatedAt");

const saveSyncLastUpdatedAt = (lastUpdatedAt: number) =>
    setKV("videoPreviewSyncLastUpdatedAt", lastUpdatedAt);

const pullProcessedFileIDs = async () =>
    syncUpdatedFileDataFileIDs(
        "vid_preview",
        (await savedSyncLastUpdatedAt()) ?? 0,
        async ({ fileIDs, lastUpdatedAt }) => {
            await Promise.all([
                markProcessedVideoFileIDs(fileIDs),
                saveSyncLastUpdatedAt(lastUpdatedAt),
            ]);
        },
    );

export const videoPrunePermanentlyDeletedFileIDsIfNeeded = async (
    deletedFileIDs: Set<number>,
) => {
    if (!isHLSGenerationSupported) return;

    const existing = await savedProcessedVideoFileIDs();
    if (existing.size > 0) {
        const updated = existing.difference(deletedFileIDs);
        if (updated.size != existing.size) {
            await saveProcessedVideoFileIDs(updated);
        }
    }
};

export const videoProcessingSyncIfNeeded = async () => {
    if (!isHLSGenerationSupported) return;

    // Enabling generation later must not wait for another full sync.
    _state.haveSyncedOnce = true;

    if (!isHLSGenerationEnabled()) return;

    await pullProcessedFileIDs();

    tickNow();
};

export const processVideoNewUpload = (
    file: EnteFile,
    processableUploadItem: ProcessableUploadItem,
) => {
    if (!isHLSGenerationSupported) return;
    if (!isHLSGenerationEnabled()) return;
    if (file.metadata.fileType != FileType.video) return;
    if (processableUploadItem instanceof File) {
        assertionFailed();
        return;
    }

    _state.liveQueue.push({
        file,
        timestampedUploadItem: processableUploadItem,
    });

    tickNow();
};

const tickNow = () => {
    if (_state.resolveTick) _state.resolveTick();

    _state.tick = new Promise((r) => (_state.resolveTick = r));

    _state.queueProcessor ??= processQueue();
};

export const isHLSGenerationEnabled = () => _state.isHLSGenerationEnabled;

const processQueue = async () => {
    if (!isHLSGenerationSupported || !isHLSGenerationEnabled()) {
        assertionFailed();
        return;
    }

    const userID = ensureLocalUser().id;

    const transientFailedFileIDs = new Set<number>();

    let bq: typeof _state.liveQueue | undefined;
    while (isHLSGenerationEnabled()) {
        let item = _state.liveQueue.shift();
        if (!item) {
            if (!bq?.length) {
                if (_state.haveSyncedOnce) {
                    bq = await backfillQueue(userID);
                } else {
                    log.info("Not attempting backfill until first sync");
                }
            }
            if (bq?.length) item = bq.pop();
        }
        if (item && !transientFailedFileIDs.has(item.file.id)) {
            updateSnapshotIfNeeded("processing");

            try {
                await processQueueItem(item);
                await markProcessedVideoFileID(item.file.id);
                _state.idleWait = idleWaitInitial;
            } catch (e) {
                log.error(`Failed to process video ${fileLogID(item.file)}`, e);
                transientFailedFileIDs.add(item.file.id);
            }
        } else {
            updateSnapshotIfNeeded("idle");

            const idleWait = _state.idleWait;
            _state.idleWait = Math.min(idleWait * 2, idleWaitMax);

            if (!_state.tick) assertionFailed();
            const tick = _state.tick!;

            log.debug(() => ["gen-hls", { idleWait }]);
            await Promise.race([tick, wait(idleWait)]);
        }
    }

    updateSnapshotIfNeeded(undefined);

    _state.queueProcessor = undefined;
};

const backfillQueue = async (
    userID: number,
): Promise<VideoProcessingQueueItem[]> => {
    const allCollectionFiles = await savedCollectionFiles();
    const localTrashFileIDs = await savedTrashItemFileIDs();
    const videoFiles = uniqueFilesByID(
        allCollectionFiles.filter(
            (f) =>
                f.ownerID == userID &&
                f.metadata.fileType == FileType.video &&
                !localTrashFileIDs.has(f.id) &&
                f.pubMagicMetadata?.data.sv != 1,
        ),
    );

    const doneIDs = (await savedProcessedVideoFileIDs()).union(
        await savedFailedVideoFileIDs(),
    );
    const pendingVideoFiles = videoFiles.filter((f) => !doneIDs.has(f.id));

    const batch = randomSample(pendingVideoFiles, 50);
    return batch.map((file) => ({ file }));
};

const processQueueItem = async ({
    file,
    timestampedUploadItem,
}: VideoProcessingQueueItem) => {
    const electron = ensureElectron();

    log.debug(() => ["gen-hls", { file, timestampedUploadItem }]);

    const playlistFileData = await fetchFileData("vid_preview", file.id);
    if (playlistFileData) {
        // Queue delay may have let another client finish this file first.
        log.info(`Generate HLS for ${fileLogID(file)} | already-processed`);
        return;
    }

    const uploadItem = timestampedUploadItem
        ? await fileSystemUploadItemIfUnchanged(
              timestampedUploadItem,
              electron.fs.statMtime,
          )
        : undefined;

    let sourceVideo: FileSystemUploadItem | ReadableStream | undefined =
        uploadItem;
    if (!sourceVideo) {
        try {
            sourceVideo = (await downloadManager.fileStream(file, {
                background: true,
            }))!;
        } catch (e) {
            if (!isNetworkDownloadError(e)) await markFailedVideoFile(file);
            throw e;
        }
    }

    // Generated segments can be multi-GB, so native owns both upload and retries.
    const fetchURL = await apiURL("/files/data/preview-upload-url");
    const authToken = await ensureAuthToken();

    log.info(`Generate HLS for ${fileLogID(file)} | start`);

    let res: GenerateHLSResult | undefined;
    try {
        res = await initiateGenerateHLS(
            electron,
            sourceVideo,
            file.id,
            fetchURL,
            authToken,
        );
    } catch (e) {
        // Native already retries upload failures other than 4xx responses.
        // A rejection here normally means this video cannot be converted.
        await markFailedVideoFile(file);
        throw e;
    }

    if (!res) {
        log.info(`Generate HLS for ${fileLogID(file)} | not-required`);
        // Persist stable ineligibility so every client can skip this file.
        await updateFilePublicMagicMetadata(file, { sv: 1 });
        return;
    }

    const { playlistToken, dimensions, videoSize, videoObjectID } = res;
    try {
        const playlist = await readVideoStream(electron, playlistToken).then(
            (res) => res.text(),
        );

        const playlistData = await encodePlaylistJSON({
            type: "hls_video",
            playlist,
            ...dimensions,
            size: videoSize,
        });

        const encryptedPlaylist = await encryptBlob(playlistData, file.key);

        try {
            await putVideoData(
                file,
                encryptedPlaylist,
                videoObjectID,
                videoSize,
            );
        } catch (e) {
            if (isHTTP4xxError(e)) await markFailedVideoFile(file);
            throw e;
        }

        log.info(`Generate HLS for ${fileLogID(file)} | done`);
    } finally {
        await videoStreamDone(electron, playlistToken);
    }
};

const encodePlaylistJSON = (playlistJSON: PlaylistJSON) =>
    gzip(JSON.stringify(playlistJSON));
