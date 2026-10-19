import type { LockerUploadProgress } from "@/services/uploads";
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

export const uploadFileExtension = (name: string) => {
    const dot = name.lastIndexOf(".");
    return dot > 0 ? name.slice(dot) : "";
};

export const renamedUploadFileName = (originalName: string, value: string) => {
    const extension = uploadFileExtension(originalName);
    let name = value.replace(/[/\\]|[^\u0020-\uFFFF]/g, "").trim();
    if (extension && name.toLowerCase().endsWith(extension.toLowerCase())) {
        name = name.slice(0, -extension.length).trim();
    }
    if (!name || name === "." || name === "..") return undefined;
    name += extension;
    return new TextEncoder().encode(name).length <= 255 ? name : undefined;
};

export const fileForUpload = (item: LockerUploadCandidate) =>
    item.uploadName && item.uploadName !== item.file.name
        ? new File([item.file], item.uploadName, {
              type: item.file.type,
              lastModified: item.file.lastModified,
          })
        : item.file;
