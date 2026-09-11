import { authenticatedRequestHeaders, ensureOk } from "ente-base/http";
import { apiURL } from "ente-base/origins";
import { openFileLinkSecret, prepareFileLink } from "ente-locker-wasm";
import { z } from "zod";
import { ensureAuthenticatedSession } from "./authenticated-session";
import { getEncryptedFileRecord } from "./locker-cache";
import { decryptFileKeyForRecord } from "./sync/decrypt";

const RemoteFileShareLink = z.object({
    linkID: z.union([z.string(), z.number().transform(String)]),
    url: z.string(),
    ownerID: z.number(),
    fileID: z.number(),
    isDisabled: z.boolean().optional(),
    validTill: z.number().nullish(),
    deviceLimit: z.number().nullish(),
    passwordEnabled: z.boolean(),
    nonce: z.string().nullish(),
    memLimit: z.number().nullish(),
    opsLimit: z.number().nullish(),
    enableDownload: z.boolean(),
    createdAt: z.number(),
    encryptedFileKey: z.string().nullish(),
    encryptedFileKeyNonce: z.string().nullish(),
    kdfNonce: z.string().nullish(),
    kdfMemLimit: z.number().nullish(),
    kdfOpsLimit: z.number().nullish(),
    encryptedShareKey: z.string().nullish(),
});

interface LockerFileShareLink {
    linkID: string;
    url: string;
    fileID?: number;
    validTill?: number | null;
    enableDownload?: boolean;
    passwordEnabled?: boolean;
}

export const getOrCreateLockerFileShareLink = async (
    fileID: number,
): Promise<LockerFileShareLink> => {
    const fileRecord = getEncryptedFileRecord(fileID);
    if (!fileRecord) {
        throw new Error(`File ${fileID} not found in cache`);
    }

    const fileKey = await decryptFileKeyForRecord(fileRecord);
    const session = await ensureAuthenticatedSession();
    const payload = await prepareFileLink(session, fileKey);

    const res = await fetch(await apiURL("/files/share-url"), {
        method: "POST",
        headers: {
            ...(await authenticatedRequestHeaders()),
            "Content-Type": "application/json",
        },
        body: JSON.stringify({ fileID, app: "locker", ...payload.metadata }),
    });
    ensureOk(res);

    const link = RemoteFileShareLink.parse(await res.json());
    const secret = link.encryptedShareKey
        ? await openFileLinkSecret(session, link.encryptedShareKey)
        : payload.secret;

    return {
        linkID: link.linkID,
        url: `${link.url}#${secret}`,
        fileID: link.fileID,
        validTill: link.validTill,
        enableDownload: link.enableDownload,
        passwordEnabled: link.passwordEnabled,
    };
};

export const deleteLockerFileShareLink = async (
    fileID: number,
    linkID?: string,
): Promise<void> => {
    const candidateIDs = [linkID, String(fileID)].filter(
        (candidate, index, values): candidate is string =>
            !!candidate && values.indexOf(candidate) === index,
    );

    let lastError: Error | undefined;
    for (const candidateID of candidateIDs) {
        const res = await fetch(
            await apiURL(`/files/share-url/${candidateID}`),
            { method: "DELETE", headers: await authenticatedRequestHeaders() },
        );
        if (res.ok) {
            return;
        }
        lastError = new Error(
            `Failed to delete link ${candidateID}: ${res.status} ${res.statusText}`,
        );
        if (candidateID !== String(fileID)) {
            continue;
        }
    }

    throw lastError ?? new Error("Failed to delete file share link");
};
