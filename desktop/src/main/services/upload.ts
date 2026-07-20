import fs from "node:fs/promises";
import path from "node:path";
import { existsSync } from "original-fs";
import type {
    PendingUploads,
    PreUploadSkippedFile,
    ZipItem,
} from "../../types/ipc";
import log from "../log";
import { uploadStatusStore } from "../stores/upload-status";
import { clearOpenZipCache, markClosableZip, openZip } from "./zip";

export const listZipItems = async (
    zipPath: string,
): Promise<{
    items: ZipItem[];
    preUploadSkippedFiles: PreUploadSkippedFile[];
}> => {
    try {
        const zip = openZip(zipPath);
        try {
            const entries = await zip.entries();
            const items: ZipItem[] = [];
            const preUploadSkippedFiles: PreUploadSkippedFile[] = [];

            for (const entry of Object.values(entries)) {
                if (!entry.isFile) continue;

                const basename = path.basename(entry.name);
                if (basename.startsWith(".")) {
                    preUploadSkippedFiles.push({
                        name: entry.name,
                        type: "hiddenFile",
                    });
                    continue;
                }
                items.push([zipPath, entry.name]);
            }

            return { items, preUploadSkippedFiles };
        } finally {
            markClosableZip(zipPath);
        }
    } catch (e) {
        log.error("Ignoring malformed zip", e);
        return {
            items: [],
            preUploadSkippedFiles: [
                { name: path.basename(zipPath), type: "failedZip" },
            ],
        };
    }
};

export const pathOrZipItemSize = async (
    pathOrZipItem: string | ZipItem,
): Promise<number> => {
    if (typeof pathOrZipItem == "string") {
        const stat = await fs.stat(pathOrZipItem);
        return stat.size;
    } else {
        const [zipPath, entryName] = pathOrZipItem;
        const zip = openZip(zipPath);
        try {
            const entry = await zip.entry(entryName);
            if (!entry)
                throw new Error(
                    `An entry with name ${entryName} does not exist in the zip file at ${zipPath}`,
                );
            return entry.size;
        } finally {
            markClosableZip(zipPath);
        }
    }
};

export const pendingUploads = (): PendingUploads | undefined => {
    const collectionName = uploadStatusStore.get("collectionName") ?? undefined;

    const allFilePaths = uploadStatusStore.get("filePaths") ?? [];
    const filePaths = allFilePaths.filter((f) => existsSync(f));

    const allZipItems = uploadStatusStore.get("zipItems") ?? [];
    const zipItems = allZipItems.filter(([z]) => existsSync(z));
    const preUploadSkippedFiles =
        uploadStatusStore.get("preUploadSkippedFiles") ?? [];
    const importTakeoutFavorites =
        uploadStatusStore.get("importTakeoutFavorites") ?? true;
    const includePartnerSharedFiles =
        uploadStatusStore.get("includePartnerSharedFiles") ?? true;

    if (filePaths.length == 0 && zipItems.length == 0) return undefined;

    return {
        collectionName,
        filePaths,
        zipItems,
        preUploadSkippedFiles,
        importTakeoutFavorites,
        includePartnerSharedFiles,
    };
};

/**
 * [Note: Missing values in electron-store]
 *
 * Suppose we were to create a store like this:
 *
 *     const store = new Store({
 *         schema: {
 *             foo: { type: "string" },
 *             bars: { type: "array", items: { type: "string" } },
 *         },
 *     });
 *
 * If we fetch `store.get("foo")` or `store.get("bars")`, we get `undefined`.
 * But if we try to set these back to `undefined`, say `store.set("foo",
 * someUndefValue)`, we get asked to
 *
 *     TypeError: Use `delete()` to clear values
 *
 * This happens even if we do bulk object updates, e.g. with a JS object that
 * has undefined keys:
 *
 * > TypeError: Setting a value of type `undefined` for key `collectionName` is
 * > not allowed as it's not supported by JSON
 *
 * So what should the TypeScript type for "foo" be?
 *
 * If it is were to not include the possibility of `undefined`, then the type
 * would lie because `store.get("foo")` can indeed be `undefined. But if we were
 * to include the possibility of `undefined`, then trying to `store.set("foo",
 * someUndefValue)` will throw.
 *
 * The approach we take is to rely on false-y values (empty strings and empty
 * arrays) to indicate missing values, and then converting those to `undefined`
 * when reading from the store, and converting `undefined` to the corresponding
 * false-y value when writing.
 */
export const setPendingUploads = ({
    collectionName,
    filePaths,
    zipItems,
    preUploadSkippedFiles,
    importTakeoutFavorites,
    includePartnerSharedFiles,
}: PendingUploads) => {
    uploadStatusStore.set({
        collectionName: collectionName ?? "",
        filePaths: filePaths,
        zipItems: zipItems,
        preUploadSkippedFiles: preUploadSkippedFiles ?? [],
        importTakeoutFavorites: importTakeoutFavorites ?? true,
        includePartnerSharedFiles: includePartnerSharedFiles ?? true,
    });
};

export const markUploadedFile = (
    path: string,
    associatedPath: string | undefined,
) => {
    const existing = uploadStatusStore.get("filePaths") ?? [];
    const updated = existing.filter((p) => p != path && p != associatedPath);
    uploadStatusStore.set("filePaths", updated);
    // See: [Note: Integral last modified time]
    return fs.stat(path).then((st) => st.mtime.getTime());
};

export const markUploadedZipItem = (
    item: ZipItem,
    associatedItem: ZipItem | undefined,
) => {
    const existing = uploadStatusStore.get("zipItems") ?? [];
    const updated = exceptZipItem(
        exceptZipItem(existing, item),
        associatedItem,
    );
    uploadStatusStore.set("zipItems", updated);
    return fs.stat(item[0]).then((st) => st.mtime.getTime());
};

const exceptZipItem = (items: ZipItem[], item: ZipItem | undefined) =>
    item
        ? items.filter((zi) => !(zi[0] == item[0] && zi[1] == item[1]))
        : items;

export const clearPendingUploads = () => {
    uploadStatusStore.clear();
    clearOpenZipCache();
};
