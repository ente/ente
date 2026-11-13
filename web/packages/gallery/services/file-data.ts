import { encryptBlob } from "ente-base/crypto";
import type { EncryptedBlobB64 } from "ente-base/crypto/types";
import {
    authenticatedPublicAlbumsRequestHeaders,
    authenticatedRequestHeaders,
    ensureOk,
    retryEnsuringHTTPOk,
    type PublicAlbumsCredentials,
} from "ente-base/http";
import { apiURL } from "ente-base/origins";
import {
    authenticatedPublicMemoryRequestHeaders,
    type PublicMemoryCredentials,
} from "ente-base/public-memory";
import type { EnteFile } from "ente-media/file";
import { nullToUndefined } from "ente-utils/transform";
import { z } from "zod";

type FileDataType = "mldata" | "vid_preview";

const RemoteFileData = z.object({
    fileID: z.number(),
    encryptedData: z.string(),
    decryptionHeader: z.string(),
    // Optional only for older self-hosted museums.
    updatedAt: z.number().nullish().transform(nullToUndefined),
});

type RemoteFileData = z.infer<typeof RemoteFileData>;

// Results are sparse and unordered; associate them by fileID.
export const fetchFilesData = async (
    type: FileDataType,
    fileIDs: number[],
): Promise<RemoteFileData[]> => {
    const res = await fetch(await apiURL("/files/data/fetch"), {
        method: "POST",
        headers: await authenticatedRequestHeaders(),
        body: JSON.stringify({ type, fileIDs }),
    });
    ensureOk(res);
    return z.object({ data: z.array(RemoteFileData) }).parse(await res.json())
        .data;
};

export const fetchFileData = async (
    type: FileDataType,
    fileID: number,
    publicAlbumsCredentials?: PublicAlbumsCredentials,
    publicMemoryCredentials?: PublicMemoryCredentials,
): Promise<RemoteFileData | undefined> => {
    const params = new URLSearchParams({
        type,
        fileID: fileID.toString(),
        preferNoContent: "true",
    });

    let res: Response;
    if (publicMemoryCredentials) {
        const url = await apiURL("/public-memory/file-data");
        const headers = authenticatedPublicMemoryRequestHeaders(
            publicMemoryCredentials,
        );
        res = await fetch(`${url}?${params.toString()}`, { headers });
    } else if (publicAlbumsCredentials) {
        const url = await apiURL("/public-collection/files/data/fetch");
        const headers = authenticatedPublicAlbumsRequestHeaders(
            publicAlbumsCredentials,
        );
        res = await fetch(`${url}?${params.toString()}`, { headers });
    } else {
        const url = await apiURL("/files/data/fetch");
        res = await fetch(`${url}?${params.toString()}`, {
            headers: await authenticatedRequestHeaders(),
        });
    }

    if (res.status == 204) return undefined;
    // Older museums ignore preferNoContent and still return 404.
    if (res.status == 404) return undefined;
    ensureOk(res);
    return z.object({ data: RemoteFileData }).parse(await res.json()).data;
};

const RemoteFDStatus = z.object({
    fileID: z.number(),
    type: z.string(),
    isDeleted: z.boolean(),
    updatedAt: z.number(),
});

export interface UpdatedFileDataFileIDsPage {
    fileIDs: Set<number>;
    lastUpdatedAt: number;
}

// Underlying file deletions have no tombstones here; trash sync prunes saved IDs.
export const syncUpdatedFileDataFileIDs = async (
    type: FileDataType,
    lastUpdatedAt: number,
    onPage: (page: UpdatedFileDataFileIDsPage) => Promise<void>,
): Promise<void> => {
    while (true) {
        const res = await fetch(await apiURL("/files/data/status-diff"), {
            method: "POST",
            headers: await authenticatedRequestHeaders(),
            body: JSON.stringify({ lastUpdatedAt }),
        });
        ensureOk(res);
        const diff = z
            .object({ diff: RemoteFDStatus.array().nullish() })
            .parse(await res.json()).diff;
        if (diff?.length) {
            const fileIDs = new Set<number>();
            for (const fd of diff) {
                lastUpdatedAt = Math.max(lastUpdatedAt, fd.updatedAt);
                if (fd.type == type && !fd.isDeleted) {
                    fileIDs.add(fd.fileID);
                }
            }
            await onPage({ fileIDs, lastUpdatedAt });
        } else {
            break;
        }
    }
};

// lastUpdatedAt prevents overwriting remote data newer than the caller's pull.
export const putFileData = async (
    file: EnteFile,
    type: FileDataType,
    data: Uint8Array,
    lastUpdatedAt: number,
) => {
    const { encryptedData, decryptionHeader } = await encryptBlob(
        data,
        file.key,
    );

    const res = await fetch(await apiURL("/files/data"), {
        method: "PUT",
        headers: await authenticatedRequestHeaders(),
        body: JSON.stringify({
            fileID: file.id,
            type,
            encryptedData,
            decryptionHeader,
            lastUpdatedAt,
        }),
    });
    ensureOk(res);
};

// Museum stores playlists as file data and client-uploaded segments as preview data.
export const fetchFilePreviewData = async (
    type: FileDataType,
    fileID: number,
    publicAlbumsCredentials?: PublicAlbumsCredentials,
    publicMemoryCredentials?: PublicMemoryCredentials,
): Promise<string | undefined> => {
    const params = new URLSearchParams({ type, fileID: fileID.toString() });

    let res: Response;
    if (publicMemoryCredentials) {
        const headers = authenticatedPublicMemoryRequestHeaders(
            publicMemoryCredentials,
        );
        const url = await apiURL("/public-memory/files/data/preview");
        res = await fetch(`${url}?${params.toString()}`, { headers });
    } else if (publicAlbumsCredentials) {
        const headers = authenticatedPublicAlbumsRequestHeaders(
            publicAlbumsCredentials,
        );
        const url = await apiURL("/public-collection/files/data/preview");
        res = await fetch(`${url}?${params.toString()}`, { headers });
    } else {
        const url = await apiURL("/files/data/preview");
        res = await fetch(`${url}?${params.toString()}`, {
            headers: await authenticatedRequestHeaders(),
        });
    }

    if (res.status == 404) return undefined;
    ensureOk(res);
    return z.object({ url: z.string() }).parse(await res.json()).url;
};

export const putVideoData = async (
    file: EnteFile,
    encryptedPlaylist: EncryptedBlobB64,
    objectID: string,
    objectSize: number,
) =>
    retryEnsuringHTTPOk(
        async () =>
            fetch(await apiURL("/files/video-data"), {
                method: "PUT",
                headers: await authenticatedRequestHeaders(),
                body: JSON.stringify({
                    fileID: file.id,
                    objectID,
                    objectSize,
                    playlist: encryptedPlaylist.encryptedData,
                    playlistHeader: encryptedPlaylist.decryptionHeader,
                }),
            }),
        { retryProfile: "background" },
    );
