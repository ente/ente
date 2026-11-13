import {
    isBulkDeletableEmptyAlbum,
    type CollectionSummary,
} from "ente-new/photos/services/collection-summary";
import { t } from "i18next";

export type AlbumFilter = "ente" | "shared" | "received" | "empty-albums";

export const albumFilters: {
    value: AlbumFilter;
    label: () => string;
    title: () => string;
}[] = [
    { value: "ente", label: () => "Ente", title: () => "Ente" },
    {
        value: "shared",
        label: () => t("shared_albums_label"),
        title: () => t("shared_albums_title"),
    },
    {
        value: "received",
        label: () => t("received_albums_label"),
        title: () => t("received_albums_title"),
    },
    {
        value: "empty-albums",
        label: () => t("empty_albums"),
        title: () => t("empty_albums_title"),
    },
];

export const matchesAlbumFilter = (
    cs: CollectionSummary,
    albumFilter: AlbumFilter,
): boolean => {
    switch (albumFilter) {
        case "ente":
            return (
                !cs.attributes.has("system") &&
                !cs.attributes.has("uncategorized") &&
                !cs.attributes.has("quickLink") &&
                !cs.attributes.has("archived") &&
                !(cs.type == "userFavorites" && cs.fileCount == 0)
            );
        case "shared":
            return (
                !cs.attributes.has("archived") &&
                !cs.attributes.has("sharedIncoming") &&
                !cs.attributes.has("quickLink") &&
                (cs.attributes.has("sharedOutgoing") ||
                    cs.attributes.has("sharedViaLink"))
            );
        case "received":
            return (
                !cs.attributes.has("archived") &&
                cs.attributes.has("sharedIncoming")
            );
        case "empty-albums":
            return isBulkDeletableEmptyAlbum(cs);
    }
};

export const visibleAlbumFilters = (
    collectionSummaries: CollectionSummary[],
    query = "",
) => {
    const normalizedQuery = query.trim().toLowerCase();
    return albumFilters.filter(({ value }) => {
        if (
            normalizedQuery &&
            !collectionSummaries.some(
                (cs) =>
                    matchesAlbumFilter(cs, value) &&
                    cs.name.toLowerCase().includes(normalizedQuery),
            )
        )
            return false;
        if (value == "ente") return true;
        if (value == "empty-albums") {
            return (
                collectionSummaries.filter(isBulkDeletableEmptyAlbum).length >=
                3
            );
        }
        return collectionSummaries.some((cs) => matchesAlbumFilter(cs, value));
    });
};

export const filterAlbumSummaries = (
    summaries: CollectionSummary[],
    filter: AlbumFilter,
    query: string,
) => {
    const normalizedQuery = query.trim().toLowerCase();
    return summaries.filter(
        (cs) =>
            matchesAlbumFilter(cs, filter) &&
            (!normalizedQuery ||
                cs.name.toLowerCase().includes(normalizedQuery)),
    );
};
