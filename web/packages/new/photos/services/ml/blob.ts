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

/**
 * The encoded, undecoded image contents that should be indexed for a given
 * file.
 *
 * The native side decodes all the formats we care about itself, so unlike
 * {@link fetchRenderableEnteFileBlob} there is no JPEG conversion involved.
 */
export interface IndexableImageSource {
    bytes: Uint8Array<ArrayBuffer>;
}

/**
 * Return the original image contents for the native ML pipeline to index.
 *
 * - For images this is the original image itself: the local file when we're
 *   called during an upload from this client, otherwise the downloaded (and
 *   decrypted) original.
 * - For videos it is their (JPEG) thumbnail.
 * - For live photos it is the image component of the live photo.
 *
 * @param file The {@link EnteFile} to index.
 *
 * @param puItem If we're called during the upload process, then this will be
 * set to the {@link ProcessableUploadItem} that was uploaded so that we can
 * directly use the on-disk file instead of needing to download the original.
 *
 * @param electron The {@link ElectronMLWorker} instance that we can use to
 * IPC with the Node.js layer.
 */
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

                // Revalidate after stabilizing the bytes. Multiple files are
                // fetched ahead of the serialized native analysis queue, so a
                // path must not remain as a deferred reference to mutable file
                // system contents. If it changed while we were reading it,
                // fall through and use the uploaded remote original instead.
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
        // The file on disk has changed. Fetch it from remote instead.
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

/**
 * Return renderable image bytes derived from an already fetched source.
 *
 * This is used when the native decoder rejects a format that the desktop app
 * can convert to JPEG. Keeping conversion separate from fetching ensures the
 * fallback uses the same stable bytes as the initial analysis attempt.
 */
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

/**
 * Read the given {@link uploadItem} into an in-memory representation.
 *
 * See: [Note: Reading a UploadItem]
 *
 * @param uploadItem An {@link UploadItem} which we are trying to index. The
 * code calling us guarantees that this function will not be called for videos.
 *
 * @returns a web {@link File} that can be used to access the upload item's
 * contents.
 */
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
        // This function will not be called for videos, and for images
        // it is reasonable to read the entire stream into memory here.
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

/**
 * Return a renderable one (possibly involving a JPEG conversion) blob for the
 * given {@link EnteFile}.
 *
 * -  The original will be downloaded if needed.
 * -  The original will be converted to JPEG if needed.
 */
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
        // A layer above us should've already filtered these out.
        throw new Error(`Cannot index unsupported file type ${fileType}`);
    }
};
