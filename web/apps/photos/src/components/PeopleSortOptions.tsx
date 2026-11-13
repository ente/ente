import {
    SortOptions,
    type SortOptionsAppearanceProps,
} from "@/components/SortOptions";
import type { PeopleSortBy } from "@/utils/people-sort";
import { t } from "i18next";
import React from "react";

interface PeopleSortOptionsProps extends SortOptionsAppearanceProps {
    activeSortBy: PeopleSortBy;
    onChangeSortBy: (by: PeopleSortBy) => void;
}

type PeopleSortCategory = "name" | "count";

export const PeopleSortOptions: React.FC<PeopleSortOptionsProps> = ({
    activeSortBy,
    onChangeSortBy,
    ...appearanceProps
}) => (
    <SortOptions<PeopleSortCategory>
        {...appearanceProps}
        id="people-sort"
        activeCategory={activeSortBy.startsWith("name") ? "name" : "count"}
        activeAscending={activeSortBy.endsWith("asc")}
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
            { category: "count", label: t("photos"), defaultAscending: false },
        ]}
    />
);
