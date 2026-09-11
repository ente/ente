import type { LockerItem } from "@/types";
import { authenticatedRequestHeaders, ensureOk } from "ente-base/http";
import log from "ente-base/log";
import { apiURL } from "ente-base/origins";
import { decryptBox, encryptBox } from "ente-locker-wasm";
import { getCollectionRecord, getEncryptedFileRecord } from "./locker-cache";
import { decryptCollectionKey } from "./sync/decrypt";
import { fetchLockerTrash } from "./sync/sync";

export const trashFiles = async (
    fileIDs: number[],
    collectionID: number,
): Promise<void> => {
    const res = await fetch(await apiURL("/files/trash"), {
        method: "POST",
        headers: {
            ...(await authenticatedRequestHeaders()),
            "Content-Type": "application/json",
        },
        body: JSON.stringify({
            items: fileIDs.map((fileID) => ({ fileID, collectionID })),
        }),
    });
    ensureOk(res);
};

export const permanentlyDeleteFromTrash = async (
    fileIDs: number[],
): Promise<void> => {
    const res = await fetch(await apiURL("/trash/delete"), {
        method: "POST",
        headers: {
            ...(await authenticatedRequestHeaders()),
            "Content-Type": "application/json",
        },
        body: JSON.stringify({ fileIDs }),
    });
    ensureOk(res);
};

export const emptyTrash = async (lastUpdatedAt: number): Promise<void> => {
    const res = await fetch(await apiURL("/trash/empty"), {
        method: "POST",
        headers: {
            ...(await authenticatedRequestHeaders()),
            "Content-Type": "application/json",
        },
        body: JSON.stringify({ lastUpdatedAt }),
    });
    ensureOk(res);
};

export const restoreFromTrash = async (
    items: Pick<LockerItem, "id" | "collectionID">[],
    targetCollectionID: number,
): Promise<void> => {
    const collectionRecord = getCollectionRecord(targetCollectionID);
    if (!collectionRecord)
        throw new Error(`Collection ${targetCollectionID} not in cache`);

    const collectionKey = await decryptCollectionKey(collectionRecord);

    const buildRestorePayload = async (
        candidateItems: Pick<LockerItem, "id" | "collectionID">[],
    ) => {
        const files: {
            id: number;
            encryptedKey: string;
            keyDecryptionNonce: string;
        }[] = [];
        const skippedFileIDs: number[] = [];

        for (const item of candidateItems) {
            const fileRecord = getEncryptedFileRecord(
                item.id,
                item.collectionID,
            );
            if (!fileRecord) {
                skippedFileIDs.push(item.id);
                continue;
            }

            const origCollectionRecord = getCollectionRecord(
                fileRecord.collectionID,
            );
            if (!origCollectionRecord) {
                skippedFileIDs.push(item.id);
                continue;
            }

            const origCollectionKey =
                await decryptCollectionKey(origCollectionRecord);
            const fileKey = await decryptBox(
                {
                    encryptedData: fileRecord.encryptedKey,
                    nonce: fileRecord.keyDecryptionNonce,
                },
                origCollectionKey,
            );

            const encryptedFileKey = await encryptBox(fileKey, collectionKey);
            files.push({
                id: item.id,
                encryptedKey: encryptedFileKey.encryptedData,
                keyDecryptionNonce: encryptedFileKey.nonce,
            });
        }

        return { files, skippedFileIDs };
    };

    let { files, skippedFileIDs } = await buildRestorePayload(items);
    if (files.length === 0 && skippedFileIDs.length > 0) {
        await fetchLockerTrash();
        ({ files, skippedFileIDs } = await buildRestorePayload(items));
    }

    if (skippedFileIDs.length > 0) {
        log.warn(
            `Skipping ${skippedFileIDs.length} trash files during restore due to missing cache records`,
            skippedFileIDs,
        );
    }
    if (files.length === 0) {
        throw new Error(
            "Unable to restore files: missing encrypted metadata in local cache. Please refresh and try again.",
        );
    }

    const res = await fetch(await apiURL("/collections/restore-files"), {
        method: "POST",
        headers: {
            ...(await authenticatedRequestHeaders()),
            "Content-Type": "application/json",
        },
        body: JSON.stringify({ collectionID: targetCollectionID, files }),
    });
    ensureOk(res);
};
