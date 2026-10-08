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

export const searchCategoryForType = (
    type: SearchSuggestion["type"],
): Exclude<SearchCategory, "all"> => {
    switch (type) {
        case "collection":
            return "albums";
        case "person":
            return "people";
        case "location":
        case "city":
            return "places";
        case "sidebarAction":
            return "settings";
        default:
            return "photos";
    }
};

/** The cleanup invalidates in-flight work as well as the debounce timer. */
export const schedulePhotoSearch = (
    query: string,
    search: (query: string) => Promise<SearchOption[]>,
    publish: (result: {
        options: SearchOption[];
        failed: boolean;
        error?: unknown;
    }) => void,
) => {
    let cancelled = false;
    const timer = setTimeout(() => {
        void search(query).then(
            (options) => {
                if (!cancelled) publish({ options, failed: false });
            },
            (error: unknown) => {
                if (!cancelled) publish({ options: [], failed: true, error });
            },
        );
    }, 250);
    return () => {
        cancelled = true;
        clearTimeout(timer);
    };
};
