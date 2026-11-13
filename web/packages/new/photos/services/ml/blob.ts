import { basename } from "ente-base/file-name";
import log from "ente-base/log";
import type { ElectronMLWorker } from "ente-base/types/ipc";
import { renderableImageBlob } from "ente-gallery/services/convert";
import { downloadManager } from "ente-gallery/services/download";
import {
    fileSystemUploadItemIfUnchanged,
    type ProcessableUploadItem,
    type UploadItem,
} from "ente-gallery/services/upload";
import { readStream } from "ente-gallery/utils/native-stream";
import type { EnteFile } from "ente-media/file";
import { fileFileName } from "ente-media/file-metadata";
import { FileType } from "ente-media/file-type";
import { decodeLivePhoto } from "ente-media/live-photo";

// These are encoded source bytes; the native pipeline performs decoding.
export interface IndexableImageSource {
    bytes: Uint8Array<ArrayBuffer>;
}

export const fetchIndexableImageSource = async (
    file: EnteFile,
    puItem: ProcessableUploadItem | undefined,
    electron: ElectronMLWorker,
): Promise<IndexableImageSource> => {
    if (file.metadata.fileType == FileType.video) {
        const thumbnailData = await downloadManager.thumbnailData(file);
        return { bytes: thumbnailData! };
    }

    if (puItem) {
        if (puItem instanceof File) {
            return { bytes: new Uint8Array(await puItem.arrayBuffer()) };
        }
        const uploadItem = await fileSystemUploadItemIfUnchanged(
            puItem,
            electron.fsStatMtime,
        );
        if (uploadItem) {
            try {
                const blob = await readNonVideoUploadItem(uploadItem, electron);
                const bytes = new Uint8Array(await blob.arrayBuffer());

                // Fetches run ahead of serialized native analysis.
                // Recheck the path after reading so replaced files use remote bytes.
                if (
                    await fileSystemUploadItemIfUnchanged(
                        puItem,
                        electron.fsStatMtime,
                    )
                ) {
                    return { bytes };
                }
            } catch (e) {
                log.warn(
                    "Could not read upload item for ML indexing; fetching the remote original",
                    e,
                );
            }
        }
    }

    const originalFileBlob = await downloadManager.fileBlob(file, {
        background: true,
    });

    if (file.metadata.fileType == FileType.livePhoto) {
        const { imageData } = await decodeLivePhoto(
            fileFileName(file),
            originalFileBlob,
        );
        return { bytes: imageData };
    } else {
        return { bytes: new Uint8Array(await originalFileBlob.arrayBuffer()) };
    }
};

// Decoder fallback must convert the same stable bytes used by native analysis.
export const renderableImageBytes = async (
    file: EnteFile,
    source: IndexableImageSource,
): Promise<Uint8Array> => {
    const blob = await renderableImageBlob(
        new Blob([source.bytes]),
        fileFileName(file),
    );
    return new Uint8Array(await blob.arrayBuffer());
};

const readNonVideoUploadItem = async (
    uploadItem: UploadItem,
    electron: ElectronMLWorker,
): Promise<File> => {
    if (typeof uploadItem == "string" || Array.isArray(uploadItem)) {
        const { response, lastModifiedMs } = await readStream(
            electron,
            uploadItem,
        );
        const path = typeof uploadItem == "string" ? uploadItem : uploadItem[1];
        // Native indexing never calls this for videos, so buffer the image.
        return new File([await response.arrayBuffer()], basename(path), {
            lastModified: lastModifiedMs,
        });
    } else {
        if (uploadItem instanceof File) {
            return uploadItem;
        } else {
            return uploadItem.file;
        }
    }
};

export const fetchRenderableEnteFileBlob = async (
    file: EnteFile,
): Promise<Blob> => {
    const fileType = file.metadata.fileType;
    if (fileType == FileType.video) {
        const thumbnailData = await downloadManager.thumbnailData(file);
        return new Blob([thumbnailData!]);
    }

    const originalFileBlob = await downloadManager.fileBlob(file, {
        background: true,
    });

    if (fileType == FileType.livePhoto) {
        const { imageFileName, imageData } = await decodeLivePhoto(
            fileFileName(file),
            originalFileBlob,
        );
        return renderableImageBlob(new Blob([imageData]), imageFileName);
    } else if (fileType == FileType.image) {
        return await renderableImageBlob(originalFileBlob, fileFileName(file));
    } else {
        throw new Error(`Cannot index unsupported file type ${fileType}`);
    }
};
