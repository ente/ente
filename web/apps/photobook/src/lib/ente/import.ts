import JSZip from "jszip";
import {
    downloadEncryptedFile,
    downloadEncryptedThumbnail,
    EnteApiError,
    fetchAllFiles,
    fetchCollectionInfo,
    verifyAlbumPassword,
} from "./api";
import {
    decryptBlobBytes,
    decryptFileBytes,
    decryptFileKey,
    decryptMetadataJson,
} from "./crypto";
import type {
    EnteCredentials,
    EnteFileDescriptor,
    EnteFileMetadata,
    EnteMediaKind,
    EntePublicCollectionInfo,
    EntePublicMagicMetadata,
    EnteRemoteFile,
} from "./types";
import { parseEnteAlbumUrl } from "./url";

const FILE_TYPE_IMAGE = 0;
const FILE_TYPE_LIVE_PHOTO = 2;
// const FILE_TYPE_VIDEO = 1;

export interface EnteImportPreparation {
    credentials: EnteCredentials;
    info: EntePublicCollectionInfo;
    files: EnteFileDescriptor[];
}

const DOWNLOADS_DISABLED_MESSAGE =
    "This Ente Photos album can't be imported because downloads are disabled for this public link. Ask the owner to enable downloads or share a different link.";

export async function prepareEnteAlbum(
    albumUrl: string,
    requestPassword: () => Promise<string | null>,
    signal?: AbortSignal,
): Promise<EnteImportPreparation> {
    const parsed = parseEnteAlbumUrl(albumUrl);
    const resolved = await resolveCollectionCredentials(parsed, signal);
    const { info } = resolved;
    let { credentials } = resolved;

    if (!info.publicURL.enableDownload) {
        throw new Error(DOWNLOADS_DISABLED_MESSAGE);
    }

    if (info.publicURL.passwordEnabled) {
        if (!info.publicURL.password) {
            throw new Error(
                "Album is password-protected but server omitted the password parameters.",
            );
        }
        const password = await requestPassword();
        if (!password) {
            const e = new Error("Album import cancelled.");
            (e as Error & { cancelled?: boolean }).cancelled = true;
            throw e;
        }
        let jwt: string;
        try {
            jwt = await verifyAlbumPassword(
                credentials.apiOrigin,
                credentials.accessToken,
                password,
                info.publicURL.password,
                signal,
            );
        } catch (e) {
            if (e instanceof EnteApiError && e.status === 401) {
                throw new Error("That password is incorrect.", { cause: e });
            }
            throw e;
        }
        credentials = { ...credentials, accessTokenJWT: jwt };
        // Server may return a refreshed info once unlocked, but our only dependency
        // is the password params which we already have, so skip the refetch.
    }

    const rawFiles = await fetchAllFiles(credentials, undefined, signal);

    const descriptors = await decryptFileDescriptors(
        credentials.collectionKey,
        rawFiles,
        signal,
    );

    return { credentials, info, files: descriptors };
}

async function resolveCollectionCredentials(
    parsed: ReturnType<typeof parseEnteAlbumUrl>,
    signal?: AbortSignal,
): Promise<{ credentials: EnteCredentials; info: EntePublicCollectionInfo }> {
    let lastError: unknown;

    for (const apiOrigin of parsed.apiOrigins) {
        const credentials: EnteCredentials = {
            apiOrigin,
            albumsOrigin: parsed.albumsOrigin,
            accessToken: parsed.accessToken,
            collectionKey: parsed.collectionKey,
        };

        try {
            const info = await fetchCollectionInfo(
                credentials.apiOrigin,
                credentials.accessToken,
                undefined,
                signal,
            );
            return { credentials, info };
        } catch (error) {
            lastError = error;
        }
    }

    throw lastError instanceof Error
        ? lastError
        : new Error(
              "Unable to resolve the Ente deployment for this album link.",
          );
}

export async function fetchAndDecryptThumbnail(
    credentials: EnteCredentials,
    file: EnteFileDescriptor,
    signal?: AbortSignal,
): Promise<Blob> {
    const encrypted = await downloadEncryptedThumbnail(
        credentials,
        file.enteFileId,
        signal,
    );
    const plain = await decryptBlobBytes(
        encrypted,
        file.thumbnailDecryptionHeader,
        file.fileKey,
    );
    // Ente thumbnails are typically JPEG; the browser will sniff the content
    // type from the bytes, so a bare image/* Blob is fine.
    return new Blob([plain as BlobPart], { type: "image/jpeg" });
}

export async function fetchAndDecryptOriginal(
    credentials: EnteCredentials,
    file: EnteFileDescriptor,
    signal?: AbortSignal,
): Promise<Blob> {
    const encrypted = await downloadEncryptedFile(
        credentials,
        file.enteFileId,
        signal,
    );
    const plain = await decryptFileBytes(
        encrypted,
        file.fileDecryptionHeader,
        file.fileKey,
    );
    return new Blob([plain as BlobPart], {
        type: guessMimeFromName(file.fileName),
    });
}

export async function extractRenderableImage(
    file: EnteFileDescriptor,
    originalBlob: Blob,
): Promise<{ blob: Blob; fileName: string }> {
    if (file.mediaKind === "image") {
        return { blob: originalBlob, fileName: file.fileName };
    }

    const zip = await JSZip.loadAsync(originalBlob, { createFolders: true });
    for (const [zipFileName, zipFile] of Object.entries(zip.files)) {
        if (!zipFileName.startsWith("image")) continue;
        const imageBytes = await zipFile.async("uint8array");

        const imageFileName = withExtensionFrom(file.fileName, zipFileName);
        return {
            blob: new Blob([imageBytes as BlobPart], {
                type: guessMimeFromName(imageFileName),
            }),
            fileName: imageFileName,
        };
    }

    throw new Error(`Live Photo "${file.fileName}" does not contain an image.`);
}

// --- internals --------------------------------------------------------------

async function decryptFileDescriptors(
    collectionKey: string,
    files: EnteRemoteFile[],
    signal?: AbortSignal,
): Promise<EnteFileDescriptor[]> {
    // Skip tombstones and obvious non-photo file types before spending crypto
    // cycles on them.
    const live = files.filter((f) => !f.isDeleted);
    const out: EnteFileDescriptor[] = [];

    // Modest parallelism: decrypting metadata is CPU-bound; 6 in flight matches
    // the photobook's existing ingest worker pool.
    const CONCURRENCY = 6;
    let cursor = 0;
    const workers = Array.from(
        { length: Math.min(CONCURRENCY, live.length) },
        async () => {
            while (cursor < live.length) {
                if (signal?.aborted) return;
                const i = cursor++;
                const f = live[i]!;
                try {
                    const d = await decryptOne(collectionKey, f);
                    if (d) out.push(d);
                } catch (e) {
                    console.warn(
                        `Ente: failed to decrypt metadata for file ${f.id}`,
                        e,
                    );
                }
            }
        },
    );
    await Promise.all(workers);

    // Chronological order by dateTaken for the photobook's auto-layout.
    out.sort((a, b) => a.dateTaken - b.dateTaken);
    return out;
}

async function decryptOne(
    collectionKey: string,
    f: EnteRemoteFile,
): Promise<EnteFileDescriptor | null> {
    const fileKey = await decryptFileKey(
        f.encryptedKey,
        f.keyDecryptionNonce,
        collectionKey,
    );

    let metadata: EnteFileMetadata | null = null;
    if (f.metadata.encryptedData) {
        metadata = (await decryptMetadataJson(
            f.metadata.encryptedData,
            f.metadata.decryptionHeader,
            fileKey,
        )) as EnteFileMetadata;
    }
    if (!metadata) return null;

    let pubMagic: EntePublicMagicMetadata | undefined;
    if (f.pubMagicMetadata?.encryptedData) {
        const generic = (await decryptMetadataJson(
            f.pubMagicMetadata.encryptedData,
            f.pubMagicMetadata.decryptionHeader,
            fileKey,
        )) as { data?: EntePublicMagicMetadata } | null;
        pubMagic = generic?.data;
    }

    const fileName = pubMagic?.editedName ?? metadata.title ?? `photo-${f.id}`;
    // Ente stores creationTime in microseconds since epoch.
    const creationMicros = pubMagic?.editedTime ?? metadata.creationTime;
    const dateTaken = Math.round(creationMicros / 1000);
    const mediaKind = mediaKindFromFileType(metadata.fileType);
    if (!mediaKind) return null;

    return {
        enteFileId: f.id,
        fileKey,
        mediaKind,
        thumbnailDecryptionHeader: f.thumbnail.decryptionHeader,
        fileDecryptionHeader: f.file.decryptionHeader,
        fileName,
        dateTaken,
        width: pubMagic?.w ?? 0,
        height: pubMagic?.h ?? 0,
        fileSize: f.info?.fileSize,
    };
}

function mediaKindFromFileType(fileType: number): EnteMediaKind | null {
    if (fileType === FILE_TYPE_IMAGE) return "image";
    if (fileType === FILE_TYPE_LIVE_PHOTO) return "live-photo";
    return null;
}

function withExtensionFrom(
    baseFileName: string,
    extensionSource: string,
): string {
    const dotIndex = extensionSource.lastIndexOf(".");
    if (dotIndex === -1) return baseFileName;

    const ext = extensionSource.slice(dotIndex + 1);
    if (!ext) return baseFileName;

    const baseDotIndex = baseFileName.lastIndexOf(".");
    const stem =
        baseDotIndex === -1
            ? baseFileName
            : baseFileName.slice(0, baseDotIndex);
    return `${stem}.${ext}`;
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
