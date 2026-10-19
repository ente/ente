import { exportMetadataDirectoryName } from "@/public-album/upload/pipeline/export-dirs";
import { basename, dirname } from "ente-base/file-name";
import { customAPIOrigin } from "ente-base/origins";
import type { Collection } from "ente-media/collection";
import type { EnteFile } from "ente-media/file";

class UploadState {
    shouldDisableCFUploadProxy = false;
    checksumProtectedUploadsEnabled = false;
}

const _state = new UploadState();

export type UploadItem = File;

export type UploadPathPrefix = string;

export const uploadPathPrefix = (pathOrName: string) => {
    const folderPath = dirname(pathOrName);
    if (basename(folderPath) == exportMetadataDirectoryName) {
        return dirname(folderPath);
    }
    return folderPath;
};

export interface LivePhotoAssets {
    image: File;
    video: File;
}

export interface ClusteredUploadItem {
    localID: number;
    collectionID: number;
    fileName: string;
    isLivePhoto: boolean;
    uploadItem?: UploadItem;
    pathPrefix: UploadPathPrefix | undefined;
    livePhotoAssets?: LivePhotoAssets;
}

export type UploadableUploadItem = ClusteredUploadItem & {
    collection: Collection;
};

export type UploadPhase =
    "preparing" | "readingMetadata" | "uploading" | "cancelling" | "done";

export type UploadResult =
    | { type: "unsupported" }
    | { type: "zeroSize" }
    | { type: "tooLarge" }
    | { type: "largerThanAvailableStorage" }
    | { type: "blocked" }
    | { type: "failed" }
    | { type: "alreadyUploaded"; file: EnteFile }
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

const computeShouldDisableCFUploadProxy = async () => {
    return !!(await customAPIOrigin());
};
