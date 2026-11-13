import {
    SortOptions,
    type SortOptionsAppearanceProps,
} from "@/components/SortOptions";
import type { CollectionsSortBy } from "ente-new/photos/services/collection-summary";
import { t } from "i18next";
import React from "react";

interface CollectionsSortOptionsProps extends SortOptionsAppearanceProps {
    activeSortBy: CollectionsSortBy;
    onChangeSortBy: (by: CollectionsSortBy) => void;
}

type SortCategory = "name" | "creation-time" | "updation-time";

const getSortCategory = (sortBy: CollectionsSortBy): SortCategory => {
    if (sortBy.startsWith("name")) return "name";
    if (sortBy.startsWith("creation-time")) return "creation-time";
    return "updation-time";
};

export const CollectionsSortOptions: React.FC<CollectionsSortOptionsProps> = ({
    activeSortBy,
    onChangeSortBy,
    ...appearanceProps
}) => (
    <SortOptions<SortCategory>
        {...appearanceProps}
        id="collection-sort"
        activeCategory={getSortCategory(activeSortBy)}
        activeAscending={activeSortBy.endsWith("-asc")}
        onChange={(category, ascending) =>
            onChangeSortBy(`${category}-${ascending ? "asc" : "desc"}`)
        }
        options={[
            {
                category: "name",
                label: t("name"),
                defaultAscending: true,
                ascendingLabel: t("sort_asc_indicator"),
                descendingLabel: t("sort_desc_indicator"),
            },
            {
                category: "creation-time",
                label: t("created"),
                defaultAscending: false,
                ascendingLabel: t("oldest"),
                descendingLabel: t("newest"),
            },
            {
                category: "updation-time",
                label: t("updated"),
                defaultAscending: false,
                ascendingLabel: t("oldest"),
                descendingLabel: t("newest"),
            },
        ]}
    />
);
