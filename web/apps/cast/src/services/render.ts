import type { CastData } from "@/services/cast-data";
import { detectMediaMIMEType } from "@/services/detect-type";
import { decryptStreamBytes } from "ente-base/crypto";
import { nameAndExtension } from "ente-base/file-name";
import { ensureOk, isHTTP401Error, publicRequestHeaders } from "ente-base/http";
import log from "ente-base/log";
import { apiURL, customAPIOrigin } from "ente-base/origins";
import {
    decryptRemoteFile,
    FileDiffResponse,
    RemoteEnteFile,
    type EnteFile,
} from "ente-media/file";
import { fileFileName } from "ente-media/file-metadata";
import { FileType } from "ente-media/file-type";
import { isHEICExtension, needsJPEGConversion } from "ente-media/formats";
import { heicToJPEG } from "ente-media/heic-convert";
import { decodeLivePhoto } from "ente-media/live-photo";
import { shuffled } from "ente-utils/array";
import { wait } from "ente-utils/promise";
import { isChromecast } from "./chromecast-receiver";

/**
 * An async generator function that loops through all the files in the
 * collection, returning renderable image URLs to each that can be displayed in
 * a slideshow.
 *
 * Each time it resolves with a (data) URL for the slideshow image to show next.
 *
 * If there are no renderable image in the collection, the sequence ends by
 * yielding `{done: true}`.
 *
 * Otherwise when the generator reaches the end of the collection, it starts
 * from the beginning again. So the sequence will continue indefinitely for
 * non-empty collections.
 *
 * The generator ignores errors in the fetching and decoding of individual
 * images in the collection, skipping the erroneous ones and moving onward to
 * the next one.
 *
 * - It will however throw if there are errors when getting the collection
 *   itself. This can happen both the first time, or when we are about to loop
 *   around to the start of the collection.
 *
 * - It will also throw if three consecutive image fail.
 *
 * @param castData The collection to show and credentials to fetch the files
 * within it.
 */
export const imageURLGenerator = async function* (castData: CastData) {
    const { collectionKey, castToken } = castData;

    /**
     * Keep a FIFO queue of the URLs that we've vended out recently so that we
     * can revoke those that are not being shown anymore.
     */
    const previousURLs: string[] = [];

    /** Number of milliseconds to keep the slide on the screen. */
    const slideDuration = 12000; /* 12 s */

    /**
     * Time when we last yielded.
     *
     * We use this to keep an roughly periodic spacing between yields that
     * accounts for the time we spend fetching and processing the images.
     */
    let lastYieldTime = Date.now();

    // The first time around regress the lastYieldTime into the past so that
    // we don't wait around too long for the first slide (we do want to wait a
    // bit, for the user to see the checkmark animation as reassurance).
    lastYieldTime -= slideDuration - 2500; /* wait at most 2.5 s */

    /**
     * Number of time we have caught an exception while trying to generate an
     * image URL for individual files.
     *
     * When this happens three times consecutively, we throw.
     */
    let consecutiveFailures = 0;

    while (true) {
        const encryptedFiles = shuffled(
            await getRemoteCastCollectionFiles(castToken),
        );

        let haveEligibleFiles = false;

        for (const encryptedFile of encryptedFiles) {
            const file = await decryptRemoteFile(encryptedFile, collectionKey);

            if (!isFileEligible(file)) continue;

            let url: string;
            try {
                url = await createRenderableURL(castToken, file);
                consecutiveFailures = 0;
                haveEligibleFiles = true;
            } catch (e) {
                consecutiveFailures += 1;
                // 1, 2, bang!
                if (consecutiveFailures == 3) throw e;

                if (isHTTP401Error(e)) {
                    // The token has expired. This can happen, e.g., if the user
                    // opens the dialog to cast again, causing the client to
                    // invalidate existing tokens.
                    //
                    //  Rethrow the error, which will bring us back to the
                    // pairing page.
                    throw e;
                }

                // On all other errors (including temporary network issues),
                log.error("Skipping unrenderable file", e);
                await wait(100); /* Breathe */
                continue;
            }

            // The last element of previousURLs is the URL that is currently
            // being shown on screen.
            //
            // The last to last element is the one that was shown prior to that,
            // and now can be safely revoked.
            if (previousURLs.length > 1)
                URL.revokeObjectURL(previousURLs.shift()!);

            previousURLs.push(url);

            const elapsedTime = Date.now() - lastYieldTime;
            if (elapsedTime > 0 && elapsedTime < slideDuration)
                await wait(slideDuration - elapsedTime);

            lastYieldTime = Date.now();
            yield url;
        }

        // This collection does not have any files that we can show.
        if (!haveEligibleFiles) return;
    }
};

/**
 * Fetch all the {@link RemoteEnteFile}s present in the collection corresponding
 * to the given {@link castToken}.
 *
 * The remote files are not decrypted or otherwise used at this point, we will
 * decrypt and use them on demand when they need to be displayed.
 *
 * @param castToken A token used both for authentication, and also identifying
 * the collection corresponding to the cast session.
 *
 * @returns All the files in the collection in an arbitrary order. Since we are
 * anyways going to be shuffling these files, the order has no bearing.
 */
export const getRemoteCastCollectionFiles = async (
    castToken: string,
): Promise<RemoteEnteFile[]> => {
    const filesByID = new Map<number, RemoteEnteFile>();
    let sinceTime = 0;
    while (true) {
        const res = await fetch(await apiURL("/cast/diff", { sinceTime }), {
            headers: { "X-Cast-Access-Token": castToken },
        });
        ensureOk(res);
        const { diff, hasMore } = FileDiffResponse.parse(await res.json());
        if (!diff.length) break;
        for (const change of diff) {
            sinceTime = Math.max(sinceTime, change.updationTime);
            if (!change.isDeleted) {
                filesByID.set(change.id, change);
            }
        }
        if (!hasMore) break;
    }
    return [...filesByID.values()];
};

const isFileEligible = (file: EnteFile) => {
    if (!isImageOrLivePhoto(file)) return false;

    if ((file.info?.fileSize ?? 0) > 100 * 1024 * 1024) return false;

    // This check is fast but potentially incorrect because in practice we do
    // encounter files that are incorrectly named and have a misleading
    // extension. To detect the actual type, we need to sniff the MIME type, but
    // that requires downloading and decrypting the file first.
    const [, extension] = nameAndExtension(fileFileName(file));
    if (extension && needsJPEGConversion(extension)) {
        // On the web, we only support HEIC conversion.
        return isHEICExtension(extension);
    }

    return true;
};

const isImageOrLivePhoto = (file: EnteFile) =>
    file.metadata.fileType == FileType.image ||
    file.metadata.fileType == FileType.livePhoto;

/**
 * Create and return a new data URL that can be used to show the given
 * {@link file} in our slideshow image viewer.
 *
 * Once we're done showing the file, the URL should be revoked using
 * {@link URL.revokeObjectURL} to free up browser resources.
 */
const createRenderableURL = async (castToken: string, file: EnteFile) => {
    const imageBlob = await renderableImageBlob(castToken, file);
    return URL.createObjectURL(imageBlob);
};

const renderableImageBlob = async (castToken: string, file: EnteFile) => {
    const shouldUseThumbnail = isChromecast();

    let blob = await downloadFile(castToken, file, shouldUseThumbnail);

    let fileName = fileFileName(file);
    if (!shouldUseThumbnail && file.metadata.fileType == FileType.livePhoto) {
        const { imageData, imageFileName } = await decodeLivePhoto(
            fileName,
            blob,
        );
        fileName = imageFileName;
        blob = new Blob([imageData]);
    }

    // We cannot rely on the file's extension to detect the file type, some
    // files are incorrectly named. So use a MIME type sniffer first, but if
    // that fails than fallback to the extension.
    const mimeType = await detectMediaMIMEType(new File([blob], fileName));
    if (!mimeType)
        throw new Error(`Could not detect MIME type for file ${fileName}`);

    if (mimeType == "image/heif" || mimeType == "image/heic")
        blob = await heicToJPEG(blob);

    return new Blob([blob], { type: mimeType });
};

const downloadFile = async (
    castToken: string,
    file: EnteFile,
    shouldUseThumbnail: boolean,
) => {
    if (!isImageOrLivePhoto(file))
        throw new Error("Can only cast images and live photos");

    const customOrigin = await customAPIOrigin();

    const getFile = () => {
        if (customOrigin) {
            // See: [Note: Passing credentials for self-hosted file fetches]
            const params = new URLSearchParams({ castToken });
            const baseURL = shouldUseThumbnail
                ? `${customOrigin}/cast/files/preview/${file.id}`
                : `${customOrigin}/cast/files/download/${file.id}`;
            return fetch(`${baseURL}?${params.toString()}`, {
                headers: publicRequestHeaders(),
            });
        } else {
            const url = shouldUseThumbnail
                ? `https://cast-albums.ente.com/preview/?fileID=${file.id}`
                : `https://cast-albums.ente.com/download/?fileID=${file.id}`;
            return fetch(url, {
                headers: {
                    ...publicRequestHeaders(),
                    "X-Cast-Access-Token": castToken,
                },
            });
        }
    };

    const res = await getFile();
    ensureOk(res);

    const decrypted = await decryptStreamBytes(
        {
            encryptedData: new Uint8Array(await res.arrayBuffer()),
            decryptionHeader: shouldUseThumbnail
                ? file.thumbnail.decryptionHeader
                : file.file.decryptionHeader,
        },
        file.key,
    );
    return new Response(decrypted).blob();
};
