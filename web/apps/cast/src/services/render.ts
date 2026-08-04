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

export const imageURLGenerator = async function* (castData: CastData) {
    const { collectionKey, castToken } = castData;

    const previousURLs: string[] = [];

    const slideDuration = 12000;

    let lastYieldTime = Date.now();

    // Wait at most 2.5 s for the first slide, enough for the user to see the
    // checkmark animation as reassurance.
    lastYieldTime -= slideDuration - 2500;

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
                if (consecutiveFailures == 3) throw e;

                if (isHTTP401Error(e)) throw e;

                log.error("Skipping unrenderable file", e);
                await wait(100);
                continue;
            }

            // The last entry is the URL currently on screen; only revoke the
            // ones before it.
            if (previousURLs.length > 1)
                URL.revokeObjectURL(previousURLs.shift()!);

            previousURLs.push(url);

            const elapsedTime = Date.now() - lastYieldTime;
            if (elapsedTime > 0 && elapsedTime < slideDuration)
                await wait(slideDuration - elapsedTime);

            lastYieldTime = Date.now();
            yield url;
        }

        if (!haveEligibleFiles) return;
    }
};

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

    // The extension is a fast but unreliable check (files can be misnamed);
    // the accurate MIME sniff needs a download and decrypt first.
    const [, extension] = nameAndExtension(fileFileName(file));
    if (extension && needsJPEGConversion(extension)) {
        return isHEICExtension(extension);
    }

    return true;
};

const isImageOrLivePhoto = (file: EnteFile) =>
    file.metadata.fileType == FileType.image ||
    file.metadata.fileType == FileType.livePhoto;

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
