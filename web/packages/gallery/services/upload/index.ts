import { basename, dirname } from "ente-base/file-name";
import log from "ente-base/log";
import { customAPIOrigin } from "ente-base/origins";
import type { ZipItem } from "ente-base/types/ipc";
import { exportMetadataDirectoryName } from "ente-gallery/export-dirs";
import type { Collection } from "ente-media/collection";
import type { EnteFile } from "ente-media/file";
import type { ParsedMetadata } from "ente-media/file-metadata";
import { tryParseTakeoutAlbumNameMetadataJSON } from "./metadata-json";

class UploadState {
    shouldDisableCFUploadProxy = false;
    checksumProtectedUploadsEnabled = false;
}

let _state = new UploadState();

export const resetUploadState = () => {
    _state = new UploadState();
};

export type UploadItem = File | FileAndPath | string | ZipItem;

export interface FileAndPath {
    file: File;
    path: string;
}

export type FileSystemUploadItem = Exclude<UploadItem, File>;

export interface TimestampedFileSystemUploadItem {
    fsUploadItem: FileSystemUploadItem;
    lastModifiedMs: number;
}

// This disambiguates sibling metadata; it is not necessarily a readable path.
export type UploadPathPrefix = string;

export const uploadPathPrefix = (pathOrName: string) => {
    const folderPath = dirname(pathOrName);
    if (basename(folderPath) == exportMetadataDirectoryName) {
        return dirname(folderPath);
    }
    return folderPath;
};

export type UploadItemAndPath = [UploadItem, string];

const takeoutAlbumMetadataJSONItemsByFolderPath = (
    uploadItemAndPaths: UploadItemAndPath[],
) => {
    const result = new Map<string, UploadItem>();
    for (const [uploadItem, path] of uploadItemAndPaths) {
        if (basename(path) == "metadata.json") {
            const folderPath = dirname(path);
            if (!result.has(folderPath)) result.set(folderPath, uploadItem);
        }
    }
    return result;
};

export const takeoutAlbumMetadataJSONItemForFolder = (
    uploadItemAndPaths: UploadItemAndPath[],
    folderPath: string,
): UploadItem | undefined => {
    return takeoutAlbumMetadataJSONItemsByFolderPath(uploadItemAndPaths).get(
        folderPath,
    );
};

export const groupItemsBasedOnParentFolder = async (
    uploadItemAndPaths: UploadItemAndPath[],
    defaultFolderName: string | undefined,
) => {
    const result = new Map<string, UploadItemAndPath[]>();
    const collectionNameByFolderPath = new Map<string, string>();
    const albumMetadataJSONItemsByFolderPath =
        takeoutAlbumMetadataJSONItemsByFolderPath(uploadItemAndPaths);
    for (const [uploadItem, pathOrName] of uploadItemAndPaths) {
        let folderPath = dirname(pathOrName);
        let folderName = basename(folderPath);
        // Exported metadata/ files belong to their parent album.
        if (folderName == exportMetadataDirectoryName) {
            folderPath = dirname(folderPath);
            folderName = basename(folderPath);
        }
        if (!folderName) {
            if (!defaultFolderName)
                throw Error(`Leaf file (without default): ${pathOrName}`);
            folderName = defaultFolderName;
        }

        let collectionName = collectionNameByFolderPath.get(folderPath);
        if (collectionName == undefined) {
            const albumMetadataJSON =
                albumMetadataJSONItemsByFolderPath.get(folderPath);
            const albumName = albumMetadataJSON
                ? await tryParseTakeoutAlbumNameMetadataJSON(albumMetadataJSON)
                : undefined;
            collectionName = albumName ?? folderName;
            collectionNameByFolderPath.set(folderPath, collectionName);
        }

        if (!result.has(collectionName)) result.set(collectionName, []);
        result.get(collectionName)!.push([uploadItem, pathOrName]);
    }
    return result;
};

export interface LivePhotoAssets {
    image: UploadItem;
    video: UploadItem;
}

export interface ClusteredUploadItem {
    localID: number;
    collectionID: number;
    fileName: string;
    isLivePhoto: boolean;
    uploadItem?: UploadItem;
    pathPrefix: UploadPathPrefix | undefined;
    externalParsedMetadata?: ParsedMetadata;
    // TODO: Tie this to the isLivePhoto flag using a discriminated union.
    livePhotoAssets?: LivePhotoAssets;
}

export type UploadableUploadItem = ClusteredUploadItem & {
    collection: Collection;
};

export type ProcessableUploadItem = File | TimestampedFileSystemUploadItem;

export const markUploadedAndObtainProcessableItem = async (
    item: ClusteredUploadItem,
): Promise<ProcessableUploadItem> => {
    const electron = globalThis.electron;
    if (!electron) {
        const resultItem = item.isLivePhoto
            ? item.livePhotoAssets!.image
            : item.uploadItem;
        if (resultItem instanceof File) {
            return resultItem;
        } else {
            throw new Error(
                `Unexpected upload item of type "${typeof resultItem}"`,
            );
        }
    }

    const timestamped = async (
        item: FileSystemUploadItem,
        t: Promise<number>,
    ): Promise<TimestampedFileSystemUploadItem> => ({
        fsUploadItem: item,
        lastModifiedMs: await t,
    });

    if (item.isLivePhoto) {
        const [p0, p1] = [
            item.livePhotoAssets!.image,
            item.livePhotoAssets!.video,
        ];
        if (Array.isArray(p0) && Array.isArray(p1)) {
            return timestamped(p0, electron.markUploadedZipItem(p0, p1));
        } else if (typeof p0 == "string" && typeof p1 == "string") {
            return timestamped(p0, electron.markUploadedFile(p0, p1));
        } else if (
            typeof p0 == "object" &&
            "path" in p0 &&
            typeof p1 == "object" &&
            "path" in p1
        ) {
            return timestamped(p0, electron.markUploadedFile(p0.path, p1.path));
        } else {
            throw new Error(
                "Attempting to mark upload completion of unexpected desktop upload items",
            );
        }
    } else {
        const p = item.uploadItem!;
        if (Array.isArray(p)) {
            return timestamped(p, electron.markUploadedZipItem(p));
        } else if (typeof p == "string") {
            return timestamped(p, electron.markUploadedFile(p));
        } else if (typeof p == "object" && "path" in p) {
            return timestamped(p, electron.markUploadedFile(p.path));
        } else {
            return p;
        }
    }
};

export const fileSystemUploadItemIfUnchanged = async (
    { fsUploadItem, lastModifiedMs }: TimestampedFileSystemUploadItem,
    fsStatMtime: (path: string) => Promise<number>,
): Promise<FileSystemUploadItem | undefined> => {
    let path: string;
    if (typeof fsUploadItem == "string") {
        path = fsUploadItem;
    } else if (Array.isArray(fsUploadItem)) {
        // The recorded timestamp belongs to the containing ZIP.
        path = fsUploadItem[0];
    } else {
        path = fsUploadItem.path;
    }

    try {
        const mtimeMs = await fsStatMtime(path);
        if (mtimeMs != lastModifiedMs) {
            log.info(
                `Not using upload item for path '${path}' since modified times have changed`,
            );
            return undefined;
        }
        return fsUploadItem;
    } catch (e) {
        log.warn(`Could not determine modified time for path '${path}'`, e);
        return undefined;
    }
};

export const toPathOrZipEntry = (fsUploadItem: FileSystemUploadItem) =>
    typeof fsUploadItem == "string" || Array.isArray(fsUploadItem)
        ? fsUploadItem
        : fsUploadItem.path;

export type UploadPhase =
    | "preparing"
    | "readingMetadata"
    | "uploading"
    | "cancelling"
    | "done";

export type UploadResult =
    | { type: "unsupported" }
    | { type: "zeroSize" }
    | { type: "tooLarge" }
    | { type: "partnerShared" }
    | { type: "largerThanAvailableStorage" }
    | { type: "blocked" }
    | { type: "failed" }
    | { type: "alreadyUploaded"; file: EnteFile }
    | { type: "addedSymlink"; file: EnteFile }
    | { type: "uploadedWithStaticThumbnail"; file: EnteFile }
    | { type: "uploaded"; file: EnteFile };

export const shouldDisableCFUploadProxy = () =>
    _state.shouldDisableCFUploadProxy;

export const updateShouldDisableCFUploadProxy = async (
    savedPreference?: boolean,
) => {
    _state.shouldDisableCFUploadProxy =
        savedPreference || (await computeShouldDisableCFUploadProxy());
};

export const areChecksumProtectedUploadsEnabled = () =>
    _state.checksumProtectedUploadsEnabled;

export const updateChecksumProtectedUploadsEnabled = (enabled: boolean) => {
    _state.checksumProtectedUploadsEnabled = enabled;
};

const computeShouldDisableCFUploadProxy = async () => {
    // The worker proxy is configured only for Ente's hosted API.
    return !!(await customAPIOrigin());
};
