import type { LockerUploadProgress } from "@/services/remote";
import type { LockerUploadCandidate } from "@/types";

export const normalizeCollectionName = (name: string) =>
    name.trim().toLocaleLowerCase();

export const dedupeCollectionNames = (names: string[]) => {
    const seen = new Set<string>();
    return names.filter((name) => {
        const trimmedName = name.trim();
        const normalizedName = normalizeCollectionName(trimmedName);
        if (!normalizedName || seen.has(normalizedName)) {
            return false;
        }
        seen.add(normalizedName);
        return true;
    });
};

export const addCollectionName = (names: string[], name: string) =>
    dedupeCollectionNames([...names, name.trim()]);

export const toggleCollectionName = (names: string[], name: string) => {
    const normalizedName = normalizeCollectionName(name);
    if (!normalizedName) {
        return names;
    }

    return names.some(
        (candidate) => normalizeCollectionName(candidate) === normalizedName,
    )
        ? names.filter(
              (candidate) =>
                  normalizeCollectionName(candidate) !== normalizedName,
          )
        : addCollectionName(names, name);
};

const uploadItemKeySuffixByFile = new WeakMap<File, string>();
let uploadItemKeyCounter = 0;

export const uploadQueueItemKey = (item: LockerUploadCandidate) =>
    `${item.relativePath ?? item.file.name}:${item.file.size}:${item.file.lastModified}:${
        uploadItemKeySuffixByFile.get(item.file) ??
        (() => {
            const suffix = String(++uploadItemKeyCounter);
            uploadItemKeySuffixByFile.set(item.file, suffix);
            return suffix;
        })()
    }`;

export const uploadItemParentPath = (item: LockerUploadCandidate) => {
    const segments = (item.relativePath ?? item.file.name)
        .split("/")
        .filter(Boolean);
    return segments.slice(0, -1).join("/");
};

export const collectionNamesByUploadItem = (
    items: LockerUploadCandidate[],
    defaultCollectionName?: string,
) =>
    Object.fromEntries(
        items.map((item) => [
            uploadQueueItemKey(item),
            item.suggestedCollectionNames.length > 0
                ? dedupeCollectionNames(item.suggestedCollectionNames)
                : defaultCollectionName
                  ? [defaultCollectionName]
                  : [],
        ]),
    );

export const filterNonEmptyUploadItems = (items: LockerUploadCandidate[]) =>
    items.filter((item) => item.file.size > 0);

export const uploadProgressValue = (
    progress: LockerUploadProgress | null | undefined,
    uploadCap: number,
) => {
    if (!progress) {
        return 0;
    }

    if (progress.phase === "uploading") {
        return Math.min(
            uploadCap,
            (progress.loaded / Math.max(progress.total, 1)) * uploadCap,
        );
    }

    if (progress.phase === "finalizing") {
        return 99;
    }

    return 0;
};

export const formatFileSize = (bytes: number) => {
    if (bytes < 1024) {
        return `${bytes} B`;
    }
    if (bytes < 1024 * 1024) {
        return `${(bytes / 1024).toFixed(1)} KB`;
    }
    if (bytes < 1024 * 1024 * 1024) {
        return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
    }
    return `${(bytes / (1024 * 1024 * 1024)).toFixed(1)} GB`;
};
