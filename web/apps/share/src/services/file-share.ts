import bs58 from "bs58";
import {
    decryptBoxBytes,
    decryptMetadataJSON,
    deriveKey,
    fromHex,
    toB64,
} from "ente-base/crypto";
import { fetchFileLinkFile } from "ente-base/file-download";
import {
    HTTPError,
    isMuseumHTTPError,
    linkDeviceTokenFromResponse,
    linkDeviceTokenRequestHeader,
} from "ente-base/http";
import { apiOrigin } from "ente-base/origins";
import type {
    DecryptedFileInfo,
    FileLinkInfo,
    FileMetadata,
    LinkKeyMaterial,
    LockerInfo,
} from "../types/file-share";
import { saveStreamedFile } from "./download";

const deviceLimitExceededMessage =
    "This link has been viewed on too many devices. Please contact the owner.";

export const extractFileKeyFromURL = async (
    url: URL,
): Promise<LinkKeyMaterial | null> => {
    const hashValue = url.hash.slice(1).split("-")[0];
    if (!hashValue) return null;

    try {
        const base62SecretPattern = /^[0-9A-Za-z]{12}$/;

        if (hashValue.length === 12 && base62SecretPattern.test(hashValue)) {
            return { type: "secret", passphrase: hashValue };
        }

        // Legacy links embed the raw key, base58 encoded (about 44 chars) or
        // hex encoded (64 chars); the length discriminates between the two.
        if (hashValue.length < 50) {
            const decoded = bs58.decode(hashValue);
            return { type: "direct", fileKey: await toB64(decoded) };
        }
        return { type: "direct", fileKey: await fromHex(hashValue) };
    } catch {
        return null;
    }
};

export const fetchFileInfo = async (
    accessToken: string,
    linkDeviceToken?: string,
): Promise<{ fileLinkInfo: FileLinkInfo; linkDeviceToken?: string }> => {
    const url = `${await apiOrigin()}/file-link/info`;

    const response = await fetch(url, {
        headers: {
            "X-Auth-Access-Token": accessToken,
            ...(linkDeviceToken && {
                [linkDeviceTokenRequestHeader]: linkDeviceToken,
            }),
        },
        cache: "no-store",
    });

    if (!response.ok) {
        const error = new HTTPError(response);
        if (await isMuseumHTTPError(error, 403, "LINK_DEVICE_LIMIT_EXCEEDED")) {
            throw new Error(deviceLimitExceededMessage);
        }
        if (response.status === 429) {
            throw new Error("Too many requests. Please try again later.");
        }
        if (response.status === 410) {
            if (await isMuseumHTTPError(error, 410, "LINK_EXPIRED")) {
                throw new Error("This link has expired.");
            }
            if (await isMuseumHTTPError(error, 410, "LINK_DISABLED")) {
                throw new Error("This link has been deleted by the owner.");
            }
            throw new Error("This link is no longer available.");
        }
        throw new Error(`Failed to fetch file`);
    }

    const data = (await response.json()) as FileLinkInfo;
    return {
        fileLinkInfo: data,
        linkDeviceToken: linkDeviceTokenFromResponse(response),
    };
};

const decryptFileKey = async (
    encryptedKey: string,
    keyDecryptionNonce: string,
    linkKey: string,
): Promise<string> => {
    try {
        const decryptedKeyBytes = await decryptBoxBytes(
            { encryptedData: encryptedKey, nonce: keyDecryptionNonce },
            linkKey,
        );
        return await toB64(decryptedKeyBytes);
    } catch {
        // Older links use the link key itself as the file key; fall back to
        // it when unwrapping fails.
        return linkKey;
    }
};

const decryptMetadata = async (
    encryptedData: string,
    decryptionHeader: string,
    fileKey: string,
): Promise<FileMetadata> => {
    try {
        const decryptedMetadata = await decryptMetadataJSON(
            { encryptedData, decryptionHeader },
            fileKey,
        );
        return decryptedMetadata as FileMetadata;
    } catch {
        return {};
    }
};

const decryptPubMagicMetadata = async (
    data: string,
    header: string,
    fileKey: string,
): Promise<{ info?: string | LockerInfo; editedName: string } | null> => {
    try {
        const decryptedPubMagicMetadata = await decryptMetadataJSON(
            { encryptedData: data, decryptionHeader: header },
            fileKey,
        );
        return decryptedPubMagicMetadata as {
            info?: string | LockerInfo;
            editedName: string;
        };
    } catch {
        return null;
    }
};

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

const parseLockerInfo = (
    rawInfo: string | LockerInfo | undefined,
): LockerInfo | undefined => {
    if (!rawInfo) return undefined;

    const parsedInfo =
        typeof rawInfo === "string"
            ? (() => {
                  try {
                      return JSON.parse(rawInfo) as LockerInfo;
                  } catch {
                      return undefined;
                  }
              })()
            : rawInfo;

    if (!parsedInfo) {
        return undefined;
    }

    return { ...parsedInfo, type: normalizeLockerInfoType(parsedInfo.type) };
};

const extractFileInfo = (
    metadata: FileMetadata,
    pubMagicMetadata: {
        info?: string | LockerInfo | undefined;
        editedName: string;
    } | null,
    file: FileLinkInfo["file"],
    infoObject: LockerInfo | undefined,
): { fileName: string; fileSize: number; uploadedTime: number } => {
    const fileName =
        pubMagicMetadata?.editedName ||
        metadata.fileName ||
        metadata.title ||
        metadata.name ||
        "Unknown file";

    const pubMagicFileSize = infoObject?.data?.size;
    const fileSizeFromInfo = file?.info?.fileSize || 0;

    const fileSize =
        pubMagicFileSize ||
        fileSizeFromInfo ||
        metadata.fileSize ||
        metadata.size ||
        file?.file?.size ||
        0;

    const metadataUploadTime =
        metadata.uploadedTime ||
        metadata.createdAt ||
        metadata.modificationTime;

    const uploadedTime = metadataUploadTime || file?.updationTime || 0;

    return { fileName, fileSize, uploadedTime };
};

const resolveFileKey = async (
    fileLinkInfo: FileLinkInfo,
    keyMaterial: LinkKeyMaterial,
): Promise<string> => {
    const file = fileLinkInfo.file;

    if (keyMaterial.type === "secret") {
        const linkMeta = fileLinkInfo.link;
        if (
            !linkMeta?.encryptedFileKey ||
            !linkMeta.encryptedFileKeyNonce ||
            !linkMeta.kdfNonce ||
            linkMeta.kdfMemLimit == null ||
            linkMeta.kdfOpsLimit == null
        ) {
            throw new Error("Missing link metadata for deriving file key");
        }

        const derivedKey = await deriveKey(
            keyMaterial.passphrase,
            linkMeta.kdfNonce,
            linkMeta.kdfOpsLimit,
            linkMeta.kdfMemLimit,
        );

        const decryptedKeyBytes = await decryptBoxBytes(
            {
                encryptedData: linkMeta.encryptedFileKey,
                nonce: linkMeta.encryptedFileKeyNonce,
            },
            derivedKey,
        );
        return await toB64(decryptedKeyBytes);
    }

    if (file?.encryptedKey && file.keyDecryptionNonce) {
        return await decryptFileKey(
            file.encryptedKey,
            file.keyDecryptionNonce,
            keyMaterial.fileKey,
        );
    }

    return keyMaterial.fileKey;
};

export const decryptFileInfo = async (
    fileLinkInfo: FileLinkInfo,
    keyMaterial: LinkKeyMaterial,
): Promise<DecryptedFileInfo> => {
    try {
        const file = fileLinkInfo.file;
        const ownerName = fileLinkInfo.ownerName;

        if (!file) {
            throw new Error("No file object in response");
        }

        const fileKey = await resolveFileKey(fileLinkInfo, keyMaterial);

        const fileId = file.id || 0;
        const fileDecryptionHeader = file.file?.decryptionHeader;

        const encryptedMetadata =
            file.metadata?.encryptedData || file.encryptedMetadata;
        const metadataDecryptionHeader =
            file.metadata?.decryptionHeader || file.metadataDecryptionHeader;

        if (!encryptedMetadata || !metadataDecryptionHeader) {
            return {
                id: fileId,
                fileName: "Unknown file",
                fileSize: file.info?.fileSize || file.file?.size || 0,
                uploadedTime: file.updationTime || 0,
                ownerName,
                fileDecryptionHeader,
                fileNonce: undefined,
                fileKey,
            };
        }

        const metadata = await decryptMetadata(
            encryptedMetadata,
            metadataDecryptionHeader,
            fileKey,
        );

        let pubMagicMetadata: {
            info?: string | LockerInfo;
            editedName: string;
        } | null = null;
        if (file.pubMagicMetadata?.data && file.pubMagicMetadata.header) {
            pubMagicMetadata = await decryptPubMagicMetadata(
                file.pubMagicMetadata.data,
                file.pubMagicMetadata.header,
                fileKey,
            );
        }

        const infoObject = parseLockerInfo(pubMagicMetadata?.info);
        const lockerType = infoObject?.type;

        const { fileName, fileSize, uploadedTime } = extractFileInfo(
            metadata,
            pubMagicMetadata,
            file,
            infoObject,
        );

        return {
            id: fileId,
            fileName,
            fileSize,
            uploadedTime,
            ownerName,
            fileDecryptionHeader,
            fileNonce: undefined,
            fileKey,
            lockerType,
            lockerInfoData: infoObject?.data,
        };
    } catch {
        const fallbackKey =
            keyMaterial.type === "secret"
                ? keyMaterial.passphrase
                : keyMaterial.fileKey;
        if (!fileLinkInfo.file) {
            return {
                id: 0,
                fileName: "Error: No file data",
                fileSize: 0,
                uploadedTime: 0,
                ownerName: fileLinkInfo.ownerName,
                fileDecryptionHeader: undefined,
                fileNonce: undefined,
                fileKey: fallbackKey,
            };
        }

        const file = fileLinkInfo.file;
        return {
            id: file.id || 0,
            fileName: "Encrypted file",
            fileSize: file.info?.fileSize || file.file?.size || 0,
            uploadedTime: file.updationTime || 0,
            ownerName: fileLinkInfo.ownerName,
            fileDecryptionHeader: file.file?.decryptionHeader,
            fileNonce: undefined,
            fileKey: fallbackKey,
        };
    }
};

export const downloadFile = async (
    accessToken: string,
    fileKey: string,
    fileName: string,
    fileDecryptionHeader?: string,
    fileNonce?: string,
): Promise<void> => {
    const response = await fetchFileLinkFile(accessToken);

    if (!response.ok) {
        if (
            await isMuseumHTTPError(
                new HTTPError(response),
                403,
                "LINK_DEVICE_LIMIT_EXCEEDED",
            )
        ) {
            throw new Error(deviceLimitExceededMessage);
        }
        throw new Error(`Failed to download file: ${response.statusText}`);
    }

    if (fileDecryptionHeader) {
        await saveStreamedFile(
            response,
            fileKey,
            fileName,
            fileDecryptionHeader,
        );
        return;
    }

    const body = response.body;
    if (!body) {
        throw new Error("Response body is empty");
    }

    const encryptedData = new Uint8Array(await response.arrayBuffer());

    let decryptedData: Uint8Array<ArrayBuffer>;

    if (fileNonce) {
        decryptedData = await decryptBoxBytes(
            { encryptedData: await toB64(encryptedData), nonce: fileNonce },
            fileKey,
        );
    } else {
        decryptedData = encryptedData;
    }

    const blob = new Blob([decryptedData]);

    const blobUrl = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = blobUrl;
    a.download = fileName;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(blobUrl);
};

export const formatFileSize = (bytes: number): string => {
    if (bytes === 0) return "0 Bytes";

    const sizes = ["Bytes", "KB", "MB", "GB", "TB"];
    const k = 1024;
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    const size = bytes / Math.pow(k, i);

    return `${Math.round(size)} ${sizes[i]}`;
};
