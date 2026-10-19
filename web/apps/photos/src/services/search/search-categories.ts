import type {
    SearchOption,
    SearchSuggestion,
} from "ente-new/photos/services/search/types";

export const searchCategories = [
    "all",
    "albums",
    "people",
    "places",
    "photos",
    "settings",
] as const;

export type SearchCategory = (typeof searchCategories)[number];

export const searchCategoryForSuggestion = (
    suggestion: SearchSuggestion,
): Exclude<SearchCategory, "all"> => {
    switch (suggestion.type) {
        case "collection":
            return "albums";
        case "person":
            return "people";
        case "location":
        case "city":
            return "places";
        case "sidebarAction":
            switch (suggestion.actionID) {
                case "shortcuts.uncategorized":
                case "shortcuts.archive":
                case "shortcuts.hidden":
                case "shortcuts.trash":
                    return "albums";
                default:
                    return "settings";
            }
        default:
            return "photos";
    }
};

export const matchesSearchCategory = (
    option: SearchOption,
    category: SearchCategory,
) =>
    category === "all" ||
    searchCategoryForSuggestion(option.suggestion) === category;

export const searchCategoryCounts = (options: readonly SearchOption[]) => {
    const counts = {
        all: options.length,
        albums: 0,
        people: 0,
        places: 0,
        photos: 0,
        settings: 0,
    };
    for (const option of options)
        counts[searchCategoryForSuggestion(option.suggestion)]++;
    return counts;
};

export const groupSearchOptions = (options: readonly SearchOption[]) =>
    searchCategories
        .filter((category) => category !== "all")
        .map((category) => ({
            label: category,
            options: options.filter((option) =>
                matchesSearchCategory(option, category),
            ),
        }))
        .filter((group) => group.options.length > 0);
