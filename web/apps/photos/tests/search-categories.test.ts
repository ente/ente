import type {
    SearchOption,
    SearchSuggestion,
    SidebarActionID,
} from "ente-new/photos/services/search/types";
import { describe, expect, test } from "vitest";
import {
    groupSearchOptions,
    matchesSearchCategory,
    searchCategories,
    searchCategoryCounts,
    searchCategoryForSuggestion,
    type SearchCategory,
} from "../src/services/search/search-categories";

const categoriesByType = {
    collection: "albums",
    person: "people",
    location: "places",
    city: "places",
    sidebarAction: "settings",
    fileType: "photos",
    fileName: "photos",
    fileCaption: "photos",
    cameraMake: "photos",
    cameraModel: "photos",
    date: "photos",
    noLocation: "photos",
    clip: "photos",
} satisfies Record<SearchSuggestion["type"], Exclude<SearchCategory, "all">>;

const sidebarOption = (actionID: SidebarActionID): SearchOption => ({
    suggestion: { type: "sidebarAction", actionID, label: actionID, path: [] },
    fileCount: 0,
    previewFiles: [],
});

const option = (type: SearchSuggestion["type"], fileCount = 100) =>
    type === "sidebarAction"
        ? sidebarOption("utility.preferences")
        : ({
              suggestion: { type, label: type },
              fileCount,
              previewFiles: [],
          } as SearchOption);

describe("search categories", () => {
    test.each(Object.entries(categoriesByType))(
        "maps %s to %s",
        (type, category) => {
            expect(
                searchCategoryForSuggestion(
                    option(type as SearchSuggestion["type"]).suggestion,
                ),
            ).toBe(category);
        },
    );

    test("filters without reordering or changing the source results", () => {
        const options = [
            option("city"),
            option("fileName"),
            option("collection"),
            option("location"),
            option("person"),
            option("sidebarAction"),
            option("clip"),
        ];
        const original = [...options];
        for (const category of searchCategories) {
            const expected =
                category === "all"
                    ? options
                    : options.filter(
                          (o) =>
                              categoriesByType[o.suggestion.type] === category,
                      );
            const filtered = options.filter((o) =>
                matchesSearchCategory(o, category),
            );
            expect(filtered).toEqual(expected);
            filtered.forEach((o, index) => expect(o).toBe(expected[index]));
        }
        expect(options).toEqual(original);
    });

    test("counts suggestions across the complete list, including empty categories", () => {
        expect(
            searchCategoryCounts([
                option("city", 200),
                option("location", 300),
                option("clip", 500),
                option("collection", 1000),
            ]),
        ).toEqual({
            all: 4,
            albums: 1,
            people: 0,
            places: 2,
            photos: 1,
            settings: 0,
        });
        expect(searchCategoryCounts([])).toEqual({
            all: 0,
            albums: 0,
            people: 0,
            places: 0,
            photos: 0,
            settings: 0,
        });
    });
});

test("groups results in tab order while preserving rows within each category", () => {
    const firstPhoto = option("clip");
    const secondPhoto = option("fileName");
    const album = option("collection");
    const place = option("city");
    const setting = option("sidebarAction");
    const options = [firstPhoto, setting, place, secondPhoto, album];
    expect(groupSearchOptions(options)).toEqual([
        { label: "albums", options: [album] },
        { label: "places", options: [place] },
        { label: "photos", options: [firstPhoto, secondPhoto] },
        { label: "settings", options: [setting] },
    ]);
    expect(options).toEqual([firstPhoto, setting, place, secondPhoto, album]);
    expect(groupSearchOptions([])).toEqual([]);
});

const albumShortcuts = [
    "shortcuts.uncategorized",
    "shortcuts.archive",
    "shortcuts.hidden",
    "shortcuts.trash",
] as const;

test.each(albumShortcuts)("categorizes %s as Albums", (actionID) => {
    const shortcut = sidebarOption(actionID);
    expect(searchCategoryForSuggestion(shortcut.suggestion)).toBe("albums");
    expect(matchesSearchCategory(shortcut, "albums")).toBe(true);
    expect(matchesSearchCategory(shortcut, "settings")).toBe(false);
    expect(matchesSearchCategory(shortcut, "all")).toBe(true);
});

test("counts and groups album shortcuts alongside collections", () => {
    const shortcuts = albumShortcuts.map(sidebarOption);
    const album = option("collection");
    const settings = [
        sidebarOption("utility.preferences"),
        sidebarOption("account.subscription"),
        sidebarOption("preferences.theme"),
        sidebarOption("help.support"),
        sidebarOption("freeUpSpace.largeFiles"),
    ];
    const options = [
        settings[0]!,
        shortcuts[0]!,
        album,
        ...shortcuts.slice(1),
        ...settings.slice(1),
    ];
    expect(searchCategoryCounts(options)).toEqual({
        all: 10,
        albums: 5,
        people: 0,
        places: 0,
        photos: 0,
        settings: 5,
    });
    expect(groupSearchOptions(options)).toEqual([
        {
            label: "albums",
            options: [shortcuts[0], album, ...shortcuts.slice(1)],
        },
        { label: "settings", options: settings },
    ]);
});
