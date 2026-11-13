import type { CollectionType } from "ente-media/collection";
import type { EnteFile } from "ente-media/file";

export type CollectionSummaryType =
    | CollectionType
    | "all"
    | "hiddenItems"
    | "defaultHidden"
    | "archiveItems"
    | "trash"
    | "userFavorites"
    | "sharedIncoming";

export type CollectionSummaryAttribute =
    | CollectionSummaryType
    | "shared"
    | "sharedOutgoing"
    | "sharedIncomingViewer"
    | "sharedIncomingCollaborator"
    | "sharedIncomingAdmin"
    | "sharedViaLink"
    | "sharedOnlyViaLink"
    | "quickLink"
    | "system"
    | "archived"
    | "hideFromCollectionBar"
    | "pinned"
    | "shareePinned";

export const PseudoCollectionID = {
    all: 0,
    archiveItems: -1,
    // Trash summaries carry EnteTrashFile entries instead of EnteFile.
    trash: -2,
    // This stands in until the on-demand Uncategorized collection is created.
    uncategorizedPlaceholder: -3,
    // Hidden items merges every default-hidden collection.
    hiddenItems: -4,
} as const;

export interface CollectionSummary {
    id: number;
    type: CollectionSummaryType;
    attributes: Set<CollectionSummaryAttribute>;
    name: string;
    latestFile: EnteFile | undefined;
    coverFile: EnteFile | undefined;
    fileCount: number;
    // Epoch microseconds.
    updationTime: number | undefined;
    sortPriority: CollectionSummarySortPriority;
    order?: number;
}

export type CollectionSummaries = Map<number, CollectionSummary>;

export const collectionsSortBy = [
    "name-asc",
    "name-desc",
    "creation-time-asc",
    "creation-time-desc",
    "updation-time-asc",
    "updation-time-desc",
] as const;

export type CollectionsSortBy = (typeof collectionsSortBy)[number];

// Higher priorities render first.
export const CollectionSummarySortPriority = {
    system: 9,
    favorites: 8,
    pinned: 7,
    other: 0,
} as const;

export type CollectionSummarySortPriority =
    (typeof CollectionSummarySortPriority)[keyof typeof CollectionSummarySortPriority];

export const haveOnlySystemCollections = (
    collectionSummaries: CollectionSummaries,
) =>
    [...collectionSummaries.values()].every((cs) =>
        cs.attributes.has("system"),
    );

export const canAddToCollection = ({ attributes }: CollectionSummary) =>
    !attributes.has("system") && !attributes.has("sharedIncomingViewer");

export const canMoveToCollection = ({ attributes }: CollectionSummary) =>
    !attributes.has("system") && !attributes.has("sharedIncoming");

export const isBulkDeletableEmptyAlbum = (cs: CollectionSummary) =>
    cs.fileCount == 0 &&
    (cs.type == "album" || cs.type == "folder") &&
    !cs.attributes.has("system") &&
    !cs.attributes.has("shared") &&
    !cs.attributes.has("archived");

export const sortCollectionSummaries = (
    collectionSummaries: CollectionSummary[],
    by: CollectionsSortBy,
): CollectionSummary[] => {
    // Collection IDs increase with creation time.
    return [...collectionSummaries].sort((a, b) => {
        switch (by) {
            case "name-asc":
                return a.name.localeCompare(b.name);
            case "name-desc":
                return b.name.localeCompare(a.name);
            case "creation-time-asc":
                return a.id - b.id;
            case "creation-time-desc":
                return b.id - a.id;
            case "updation-time-asc":
                return (a.updationTime ?? 0) - (b.updationTime ?? 0);
            case "updation-time-desc":
                return (b.updationTime ?? 0) - (a.updationTime ?? 0);
        }
    });
};
