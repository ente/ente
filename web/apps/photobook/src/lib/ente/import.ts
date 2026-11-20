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
import { AlbumImportBlockedError } from "./import-error";
import type { EnteCredentials, EnteFileDescriptor } from "./types";
import { parseEnteAlbumUrl } from "./url";

export async function prepareEnteAlbum(
    albumUrl: string,
    requestPassword: (error?: string) => Promise<string | null>,
    linkDeviceToken?: string,
) {
    let parsed;
    try {
        parsed = parseEnteAlbumUrl(albumUrl);
    } catch (error) {
        throw new AlbumImportBlockedError(
            error instanceof Error
                ? error.message
                : "This album link is invalid.",
        );
    }
    const { collectionKey, ...parsedCredentials } = parsed;
    const deviceTokenKey = `public-collection-link-device-token:${await apiOrigin()}:${parsedCredentials.accessToken}`;
    const credentials: EnteCredentials = {
        ...parsedCredentials,
        linkDeviceToken: linkDeviceToken ?? (await getKVS(deviceTokenKey)),
        downloadOrigin:
            (await customAPIOrigin()) ?? "https://public-albums.ente.com",
    };
    const info = await getPublicCollectionInfo(credentials);
    if (info.linkDeviceToken) {
        credentials.linkDeviceToken = info.linkDeviceToken;
    }
    if (credentials.linkDeviceToken)
        await setKV(deviceTokenKey, credentials.linkDeviceToken);
    const publicURL = info.collection.publicURLs[0];
    if (!publicURL)
        throw new AlbumImportBlockedError(
            "This album no longer has an active public link.",
        );
    if (!publicURL.enableDownload)
        throw new Error(
            "Downloads are disabled for this album. Enable downloads in the album's sharing settings, then try again.",
        );
    if (publicURL.passwordEnabled) {
        let passwordError: string | undefined;
        while (true) {
            const password = await requestPassword(passwordError);
            if (password === null)
                throw Object.assign(new Error("Album import cancelled."), {
                    cancelled: true,
                });
            try {
                credentials.accessTokenJWT =
                    await verifyPublicCollectionPassword(
                        credentials,
                        publicURL,
                        password,
                    );
                break;
            } catch (error) {
                if (!isHTTP401Error(error)) throw error;
                passwordError = "That password is incorrect.";
            }
        }
    }
    const remote = new Map<number, RemoteEnteFile>();
    let sinceTime = 0;
    while (true) {
        const { diff, hasMore } = await getPublicCollectionDiff(
            credentials,
            sinceTime,
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
    files.sort((a, b) => a.dateTaken - b.dateTaken);
    return { credentials, files };
}

export async function fetchAndDecryptThumbnail(
    credentials: EnteCredentials,
    file: EnteFileDescriptor,
): Promise<Blob> {
    const encryptedData = await downloadPublicCollectionFile(
        credentials,
        file.enteFileId,
        true,
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
): Promise<Blob> {
    const encryptedData = await downloadPublicCollectionFile(
        credentials,
        file.enteFileId,
        false,
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
