import type { LockerUploadProgress } from "@/services/uploads";
import type { LockerCollection, LockerUploadCandidate } from "@/types";

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

export type UploadDestination =
    | { kind: "existing"; id: number }
    | { kind: "new"; name: string }
    | { kind: "ambiguous"; name: string };

export type UploadDestinationsByFileKey = Record<string, UploadDestination[]>;

export const uploadDestinationKey = (destination: UploadDestination) =>
    destination.kind === "existing"
        ? `existing:${destination.id}`
        : `${destination.kind}:${normalizeCollectionName(destination.name)}`;

export const toggleUploadDestination = (
    selected: UploadDestination[],
    destination: UploadDestination,
    collections: LockerCollection[],
): UploadDestination[] => {
    const key = uploadDestinationKey(destination);
    if (selected.some((candidate) => uploadDestinationKey(candidate) === key)) {
        return selected.filter(
            (candidate) => uploadDestinationKey(candidate) !== key,
        );
    }
    if (destination.kind !== "existing") return [...selected, destination];

    const collection = collections.find(({ id }) => id === destination.id);
    return [
        ...selected.filter(
            (candidate) =>
                candidate.kind === "existing" ||
                !collection ||
                normalizeCollectionName(candidate.name) !==
                    normalizeCollectionName(collection.name),
        ),
        destination,
    ];
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

export const updateUploadDestinations = (
    current: UploadDestinationsByFileKey,
    fileKey: string | undefined,
    items: LockerUploadCandidate[],
    completedFileKeys: ReadonlySet<string>,
    change: (destinations: UploadDestination[]) => UploadDestination[],
): UploadDestinationsByFileKey => {
    const next = { ...current };
    const keys =
        fileKey === undefined ? items.map(uploadQueueItemKey) : [fileKey];
    for (const key of keys) {
        if (!completedFileKeys.has(key)) {
            next[key] = change(current[key] ?? []);
        }
    }
    return next;
};

export const uploadDestinationsByItem = (
    items: LockerUploadCandidate[],
    collections: LockerCollection[],
    defaultCollectionID?: number | null,
): UploadDestinationsByFileKey => {
    const destinationsForItem = (
        item: LockerUploadCandidate,
    ): UploadDestination[] => {
        const suggestions = dedupeCollectionNames(
            item.suggestedCollectionNames,
        );
        if (!suggestions.length) {
            return defaultCollectionID == null
                ? []
                : [{ kind: "existing", id: defaultCollectionID }];
        }

        return suggestions.map((name) => {
            const matches = collections.filter(
                (collection) =>
                    normalizeCollectionName(collection.name) ===
                    normalizeCollectionName(name),
            );
            if (matches.length > 1) return { kind: "ambiguous", name };
            const match = matches[0];
            return match
                ? { kind: "existing", id: match.id }
                : { kind: "new", name: name.trim() };
        });
    };

    return Object.fromEntries(
        items.map((item) => [
            uploadQueueItemKey(item),
            destinationsForItem(item),
        ]),
    );
};

export const replaceCreatedUploadDestination = (
    selections: UploadDestinationsByFileKey,
    name: string,
    id: number,
): UploadDestinationsByFileKey =>
    Object.fromEntries(
        Object.entries(selections).map(([fileKey, destinations]) => [
            fileKey,
            destinations.map((destination) =>
                destination.kind === "new" &&
                normalizeCollectionName(destination.name) ===
                    normalizeCollectionName(name)
                    ? { kind: "existing", id }
                    : destination,
            ),
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
