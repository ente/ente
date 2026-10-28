import { decryptBlobBytes, decryptStreamBytes } from "ente-base/crypto";
import { isHTTP401Error } from "ente-base/http";
import { getKVS, setKV } from "ente-base/kv";
import log from "ente-base/log";
import { apiOrigin, customAPIOrigin } from "ente-base/origins";
import { decryptRemoteFile, type RemoteEnteFile } from "ente-media/file";
import { fileCreationTime, fileFileName } from "ente-media/file-metadata";
import { FileType } from "ente-media/file-type";
import { decodeLivePhoto } from "ente-media/live-photo";
import {
    downloadPublicCollectionFile,
    getPublicCollectionDiff,
    getPublicCollectionInfo,
    verifyPublicCollectionPassword,
} from "ente-media/public-albums";
import type { EnteCredentials, EnteFileDescriptor } from "./types";
import { parseEnteAlbumUrl } from "./url";

export async function prepareEnteAlbum(
    albumUrl: string,
    requestPassword: () => Promise<string | null>,
    signal?: AbortSignal,
) {
    const { collectionKey, ...parsedCredentials } = parseEnteAlbumUrl(albumUrl);
    const deviceTokenKey = `public-collection-link-device-token:${await apiOrigin()}:${parsedCredentials.accessToken}`;
    const credentials: EnteCredentials = {
        ...parsedCredentials,
        linkDeviceToken: await getKVS(deviceTokenKey),
        downloadOrigin:
            (await customAPIOrigin()) ?? "https://public-albums.ente.com",
    };
    const info = await getPublicCollectionInfo(credentials, signal);
    if (info.linkDeviceToken) {
        credentials.linkDeviceToken = info.linkDeviceToken;
        await setKV(deviceTokenKey, info.linkDeviceToken);
    }
    const publicURL = info.collection.publicURLs[0];
    if (!publicURL) throw new Error("Public album share has no active URL.");
    if (!publicURL.enableDownload)
        throw new Error(
            "This album cannot be imported because downloads are disabled for this public link.",
        );
    if (publicURL.passwordEnabled) {
        const password = await requestPassword();
        if (password === null)
            throw Object.assign(new Error("Album import cancelled."), {
                cancelled: true,
            });
        try {
            credentials.accessTokenJWT = await verifyPublicCollectionPassword(
                credentials,
                publicURL,
                password,
                signal,
            );
        } catch (error) {
            if (isHTTP401Error(error))
                throw new Error("That password is incorrect.", {
                    cause: error,
                });
            throw error;
        }
    }
    const remote = new Map<number, RemoteEnteFile>();
    let sinceTime = 0;
    while (true) {
        const { diff, hasMore } = await getPublicCollectionDiff(
            credentials,
            sinceTime,
            signal,
        );
        for (const file of diff) {
            sinceTime = Math.max(sinceTime, file.updationTime);
            if (file.isDeleted) remote.delete(file.id);
            else remote.set(file.id, file);
        }
        if (!hasMore || !diff.length) break;
    }
    const files: EnteFileDescriptor[] = [];
    const pending = remote.values();
    await Promise.all(
        Array.from({ length: Math.min(6, remote.size) }, async () => {
            for (const file of pending) {
                signal?.throwIfAborted();
                try {
                    const decrypted = await decryptRemoteFile(
                        file,
                        collectionKey,
                    );
                    const kind = decrypted.metadata.fileType;
                    if (kind !== FileType.image && kind !== FileType.livePhoto)
                        continue;
                    files.push({
                        enteFileId: decrypted.id,
                        fileKey: decrypted.key,
                        mediaKind:
                            kind === FileType.image ? "image" : "live-photo",
                        thumbnailDecryptionHeader:
                            decrypted.thumbnail.decryptionHeader,
                        fileDecryptionHeader: decrypted.file.decryptionHeader,
                        fileName: fileFileName(decrypted),
                        dateTaken: Math.round(
                            fileCreationTime(decrypted) / 1000,
                        ),
                        width: decrypted.pubMagicMetadata?.data.w ?? 0,
                        height: decrypted.pubMagicMetadata?.data.h ?? 0,
                        fileSize: decrypted.info?.fileSize,
                    });
                } catch (error) {
                    log.warn(`Failed to decrypt album photo ${file.id}`, error);
                }
            }
        }),
    );
    signal?.throwIfAborted();
    files.sort((a, b) => a.dateTaken - b.dateTaken);
    return { credentials, files };
}

export async function fetchAndDecryptThumbnail(
    credentials: EnteCredentials,
    file: EnteFileDescriptor,
    signal?: AbortSignal,
): Promise<Blob> {
    const encryptedData = await downloadPublicCollectionFile(
        credentials,
        file.enteFileId,
        true,
        signal,
        credentials.downloadOrigin,
    );
    const bytes = await decryptBlobBytes(
        { encryptedData, decryptionHeader: file.thumbnailDecryptionHeader },
        file.fileKey,
    );
    return new Blob([bytes], { type: "image/jpeg" });
}

export async function fetchAndDecryptOriginal(
    credentials: EnteCredentials,
    file: EnteFileDescriptor,
    signal?: AbortSignal,
): Promise<Blob> {
    const encryptedData = await downloadPublicCollectionFile(
        credentials,
        file.enteFileId,
        false,
        signal,
        credentials.downloadOrigin,
    );
    const bytes = await decryptStreamBytes(
        { encryptedData, decryptionHeader: file.fileDecryptionHeader },
        file.fileKey,
    );
    return new Blob([bytes], { type: guessMimeFromName(file.fileName) });
}

export async function extractRenderableImage(
    file: EnteFileDescriptor,
    originalBlob: Blob,
): Promise<{ blob: Blob; fileName: string }> {
    if (file.mediaKind === "image")
        return { blob: originalBlob, fileName: file.fileName };
    const { imageData, imageFileName } = await decodeLivePhoto(
        file.fileName,
        originalBlob,
    );
    return {
        blob: new Blob([imageData], { type: guessMimeFromName(imageFileName) }),
        fileName: imageFileName,
    };
}

function guessMimeFromName(name: string): string {
    const ext = name.toLowerCase().split(".").pop() ?? "";
    switch (ext) {
        case "jpg":
        case "jpeg":
            return "image/jpeg";
        case "png":
            return "image/png";
        case "webp":
            return "image/webp";
        case "heic":
            return "image/heic";
        case "heif":
            return "image/heif";
        case "gif":
            return "image/gif";
        default:
            return "image/jpeg";
    }
}
