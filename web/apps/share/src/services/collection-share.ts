import {
    decryptBox,
    decryptMetadataJSON,
    decryptStreamBytes,
    deriveKey,
} from "ente-base/crypto";
import {
    authenticatedPublicAlbumsDeviceLimitRequestHeaders,
    authenticatedPublicAlbumsInfoRequestHeaders,
    authenticatedPublicAlbumsRequestHeaders,
    ensureOk,
    linkDeviceTokenFromResponse,
    type PublicAlbumsCredentials,
} from "ente-base/http";
import { apiOrigin, apiURL } from "ente-base/origins";
import {
    decryptRemoteCollection,
    RemoteCollection,
    type PublicURL,
} from "ente-media/collection";
import { FileDiffResponse, type RemoteEnteFile } from "ente-media/file";
import { z } from "zod";
import type { DecryptedFileInfo, LockerInfoData } from "../types/file-share";

interface ParsedLockerInfoData extends LockerInfoData {
    title?: string;
    name?: string;
}

interface ParsedLockerInfo {
    type?: string;
    data?: ParsedLockerInfoData;
}

export interface SharedCollectionItemInfo extends DecryptedFileInfo {
    collectionID: number;
    hasObject: boolean;
}

export interface PublicCollectionShareInfo {
    id: number;
    name: string;
    allowDownload: boolean;
    items: SharedCollectionItemInfo[];
}

export interface PublicCollectionShareMetadata {
    id: number;
    name: string;
    allowDownload: boolean;
    passwordEnabled: boolean;
    publicURL?: PublicURL;
    collectionKey: string;
    linkDeviceToken?: string;
}

interface DownloadProgress {
    loaded: number;
    total: number | null;
}

const VALID_INFO_TYPES = new Set([
    "note",
    "accountCredential",
    "physicalRecord",
    "emergencyContact",
]);

const normalizeLockerInfoType = (
    type: string | undefined,
): string | undefined => {
    switch (type) {
        case "note":
            return "note";
        case "physical-record":
        case "physicalRecord":
            return "physicalRecord";
        case "account-credential":
        case "accountCredential":
            return "accountCredential";
        case "emergency-contact":
        case "emergencyContact":
            return "emergencyContact";
        default:
            return undefined;
    }
};

const infoItemTitle = (
    infoType: string,
    infoData: ParsedLockerInfoData,
): string => {
    const namedTitle = infoData.title?.trim() || infoData.name?.trim();
    if (namedTitle) {
        return namedTitle;
    }

    switch (infoType) {
        case "note":
            return "Note";
        case "physicalRecord":
            return "Location";
        case "accountCredential":
            return "Secret";
        case "emergencyContact":
            return "Emergency Contact";
        default:
            return "Item";
    }
};

const toUploadedTime = (value: unknown, fallback: number) => {
    if (typeof value !== "number") {
        return fallback;
    }

    return value < 100_000_000_000_000 ? value * 1000 : value;
};

const parseLockerInfo = (rawInfo: unknown): ParsedLockerInfo | undefined => {
    if (!rawInfo) return undefined;

    const parsedInfo = (() => {
        if (typeof rawInfo === "string") {
            try {
                return JSON.parse(rawInfo) as ParsedLockerInfo;
            } catch {
                return undefined;
            }
        }

        if (typeof rawInfo === "object") {
            return rawInfo as ParsedLockerInfo;
        }

        return undefined;
    })();

    if (!parsedInfo) {
        return undefined;
    }

    return { ...parsedInfo, type: normalizeLockerInfoType(parsedInfo.type) };
};

const decryptRemoteFileToCollectionItem = async (
    remoteFile: RemoteEnteFile,
    collectionKey: string,
): Promise<SharedCollectionItemInfo> => {
    const fileKey = await decryptBox(
        {
            encryptedData: remoteFile.encryptedKey,
            nonce: remoteFile.keyDecryptionNonce,
        },
        collectionKey,
    );

    const metadata = (await decryptMetadataJSON(
        remoteFile.metadata,
        fileKey,
    )) as Record<string, unknown> | undefined;

    let pubMagicMetadata: Record<string, unknown> | undefined;
    if (remoteFile.pubMagicMetadata) {
        try {
            pubMagicMetadata = (await decryptMetadataJSON(
                {
                    encryptedData: remoteFile.pubMagicMetadata.data,
                    decryptionHeader: remoteFile.pubMagicMetadata.header,
                },
                fileKey,
            )) as Record<string, unknown> | undefined;
        } catch {
            pubMagicMetadata = undefined;
        }
    }

    const info = parseLockerInfo(pubMagicMetadata?.info);
    const isStructured =
        !!info?.type && !!info.data && VALID_INFO_TYPES.has(info.type);

    if (isStructured) {
        return {
            id: remoteFile.id,
            collectionID: remoteFile.collectionID,
            fileName: infoItemTitle(info.type!, info.data!),
            fileSize: info.data?.size ?? 0,
            uploadedTime: toUploadedTime(
                metadata?.creationTime,
                remoteFile.updationTime,
            ),
            fileKey,
            lockerType: info.type,
            lockerInfoData: info.data,
            hasObject: false,
        };
    }

    const metadataName =
        typeof metadata?.title === "string"
            ? metadata.title
            : typeof metadata?.fileName === "string"
              ? metadata.fileName
              : typeof metadata?.name === "string"
                ? metadata.name
                : undefined;
    const editedName =
        typeof pubMagicMetadata?.editedName === "string"
            ? pubMagicMetadata.editedName
            : undefined;

    return {
        id: remoteFile.id,
        collectionID: remoteFile.collectionID,
        fileName: editedName ?? metadataName ?? "File",
        fileSize:
            remoteFile.info?.fileSize ??
            (typeof metadata?.fileSize === "number"
                ? metadata.fileSize
                : typeof metadata?.size === "number"
                  ? metadata.size
                  : 0),
        uploadedTime: toUploadedTime(
            metadata?.creationTime,
            remoteFile.updationTime,
        ),
        fileDecryptionHeader: remoteFile.file.decryptionHeader,
        fileKey,
        hasObject: remoteFile.file.decryptionHeader.length > 0,
    };
};

const fetchPublicCollectionDiff = async (
    credentials: PublicAlbumsCredentials,
) => {
    const filesByID = new Map<number, RemoteEnteFile>();
    let sinceTime = 0;
    let hasMore = true;

    while (hasMore) {
        const prevSinceTime = sinceTime;
        const res = await fetch(
            await apiURL("/public-collection/diff", { sinceTime }),
            {
                headers:
                    authenticatedPublicAlbumsDeviceLimitRequestHeaders(
                        credentials,
                    ),
                cache: "no-store",
            },
        );
        ensureOk(res);

        const parsed = FileDiffResponse.parse(await res.json());
        for (const file of parsed.diff) {
            sinceTime = Math.max(sinceTime, file.updationTime);
            if (file.isDeleted) {
                filesByID.delete(file.id);
            } else {
                filesByID.set(file.id, file);
            }
        }
        hasMore = parsed.hasMore;
        // Defensive guard: if the server claims more pages but sinceTime did
        // not advance, stop to avoid spinning on a broken server contract.
        if (hasMore && sinceTime === prevSinceTime) break;
    }

    return [...filesByID.values()];
};

export const verifyPublicCollectionPassword = async (
    publicURL: PublicURL,
    password: string,
    accessToken: string,
) => {
    const passwordHash = await deriveKey(
        password,
        publicURL.nonce!,
        publicURL.opsLimit!,
        publicURL.memLimit!,
    );

    const res = await fetch(
        await apiURL("/public-collection/verify-password"),
        {
            method: "POST",
            headers: authenticatedPublicAlbumsRequestHeaders({ accessToken }),
            body: JSON.stringify({ passHash: passwordHash }),
        },
    );
    ensureOk(res);
    return z.object({ jwtToken: z.string() }).parse(await res.json()).jwtToken;
};

export const fetchPublicCollectionShareMetadata = async (
    credentials: PublicAlbumsCredentials,
    collectionKey: string,
): Promise<PublicCollectionShareMetadata> => {
    const res = await fetch(await apiURL("/public-collection/info"), {
        headers: authenticatedPublicAlbumsInfoRequestHeaders(credentials),
        cache: "no-store",
    });
    ensureOk(res);

    const data = (await res.json()) as { collection: unknown };
    const remoteCollection = RemoteCollection.parse(data.collection);
    const collection = await decryptRemoteCollection(
        remoteCollection,
        collectionKey,
    );

    const publicURL = collection.publicURLs[0];

    return {
        id: collection.id,
        name: collection.name,
        allowDownload: publicURL?.enableDownload ?? true,
        passwordEnabled: publicURL?.passwordEnabled ?? false,
        publicURL,
        collectionKey: collection.key,
        linkDeviceToken: linkDeviceTokenFromResponse(res),
    };
};

export const fetchPublicCollectionShare = async (
    credentials: PublicAlbumsCredentials,
    metadata: PublicCollectionShareMetadata,
): Promise<PublicCollectionShareInfo> => {
    const remoteFiles = await fetchPublicCollectionDiff(credentials);
    const items = await Promise.all(
        remoteFiles.map((file) =>
            decryptRemoteFileToCollectionItem(file, metadata.collectionKey),
        ),
    );
    items.sort((a, b) => b.uploadedTime - a.uploadedTime);

    return {
        id: metadata.id,
        name: metadata.name,
        allowDownload: metadata.allowDownload,
        items,
    };
};

export const downloadPublicCollectionFile = async (
    credentials: PublicAlbumsCredentials,
    fileID: number,
    fileKey: string,
    fileName: string,
    fileDecryptionHeader: string,
    onProgress?: (progress: DownloadProgress) => void,
): Promise<void> => {
    const url = `${await apiOrigin()}/public-collection/files/download/${fileID}`;
    const response = await fetch(url, {
        headers: authenticatedPublicAlbumsRequestHeaders(credentials),
    });
    ensureOk(response);

    const totalHeader = response.headers.get("content-length");
    const total = totalHeader ? Number.parseInt(totalHeader, 10) : null;

    let encryptedData: Uint8Array<ArrayBuffer>;
    if (response.body) {
        const reader = response.body.getReader();
        const chunks: Uint8Array[] = [];
        let loaded = 0;

        while (true) {
            const { done, value } = await reader.read();
            if (done) {
                break;
            }

            chunks.push(value);
            loaded += value.length;
            onProgress?.({ loaded, total });
        }

        encryptedData = new Uint8Array(loaded);
        let offset = 0;
        for (const chunk of chunks) {
            encryptedData.set(chunk, offset);
            offset += chunk.length;
        }
    } else {
        encryptedData = new Uint8Array(await response.arrayBuffer());
        onProgress?.({ loaded: encryptedData.length, total });
    }

    const decryptedData = await decryptStreamBytes(
        { encryptedData, decryptionHeader: fileDecryptionHeader },
        fileKey,
    );

    const blob = new Blob([decryptedData]);
    const blobUrl = URL.createObjectURL(blob);
    const anchor = document.createElement("a");
    anchor.href = blobUrl;
    anchor.download = fileName;
    document.body.appendChild(anchor);
    anchor.click();
    document.body.removeChild(anchor);
    URL.revokeObjectURL(blobUrl);
};
