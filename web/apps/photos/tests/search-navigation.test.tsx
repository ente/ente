import { PseudoCollectionID } from "ente-new/photos/services/collection-summary";
import type { SearchOption } from "ente-new/photos/services/search/types";
import { renderToStaticMarkup } from "react-dom/server";
import { expect, test, vi } from "vitest";
import { showCollectionSummaryWithAuthentication } from "../src/components/gallery/helpers";
import {
    activeSectionID,
    initialNavigationState,
    navigationReducer,
    type NavigationAction,
} from "../src/components/gallery/navigation/navigation-state";
import type { PhotosNavigationActions } from "../src/components/gallery/navigation/PhotosNavigationContext";
import { initialGalleryState } from "../src/components/gallery/reducer";
import { useSearchNavigation } from "../src/components/gallery/sections/search/use-search-navigation";

const hidden: SearchOption = {
    suggestion: {
        type: "sidebarAction",
        actionID: "shortcuts.hidden",
        label: "Hidden",
        path: [],
    },
    fileCount: 0,
    previewFiles: [],
};

const controller = (section: "duplicates" | "large-files") => {
    let navigation = navigationReducer(initialNavigationState, {
        type: "showCleanup",
        section,
    });
    const authentication = Promise.withResolvers<boolean>();
    const showSettings = vi.fn();
    const send = (action: NavigationAction) => {
        navigation = navigationReducer(navigation, action);
    };
    const showCollectionSummary = vi.fn<
        PhotosNavigationActions["showCollectionSummary"]
    >((id, isHidden) =>
        showCollectionSummaryWithAuthentication(
            id,
            !!isHidden,
            { current: 0 },
            () => authentication.promise,
            (collectionSummaryID) =>
                send({
                    type: "showCollectionSummary",
                    collectionSummaryID,
                    library: initialGalleryState,
                }),
        ),
    );
    let select: ReturnType<typeof useSearchNavigation>;
    const Harness = () => {
        select = useSearchNavigation({
            library: initialGalleryState,
            navigation,
            send,
            showCollectionSummary,
            showSettings,
        });
        return null;
    };
    renderToStaticMarkup(<Harness />);
    return {
        select: select!,
        state: () => navigation,
        showSettings,
        authenticate: async (success: boolean) => {
            authentication.resolve(success);
            await showCollectionSummary.mock.results[0]!.value;
        },
    };
};

test.each(["duplicates", "large-files"] as const)(
    "%s stays open while Hidden authentication is pending or cancelled",
    async (section) => {
        const navigation = controller(section);
        const origin = navigation.state();
        navigation.select(hidden);
        expect(navigation.state()).toEqual(origin);
        await navigation.authenticate(false);
        expect(navigation.state()).toEqual(origin);
    },
);

test.each(["duplicates", "large-files"] as const)(
    "%s exits when Hidden authentication succeeds",
    async (section) => {
        const navigation = controller(section);
        navigation.select(hidden);
        await navigation.authenticate(true);
        expect(activeSectionID(navigation.state())).toBe("albums");
        expect(navigation.state().destination.collectionID).toBe(
            PseudoCollectionID.hiddenItems,
        );
    },
);

test("a settings search shortcut still dismisses cleanup", () => {
    const navigation = controller("duplicates");
    navigation.select({
        ...hidden,
        suggestion: {
            type: "sidebarAction",
            actionID: "utility.preferences",
            label: "Preferences",
            path: [],
        },
    });
    expect(navigation.showSettings).toHaveBeenCalledExactlyOnceWith(
        "utility.preferences",
    );
    expect(navigation.state().overlay).toBeUndefined();
});

test("a file search still replaces cleanup with results", () => {
    const navigation = controller("large-files");
    navigation.select({
        ...hidden,
        suggestion: { type: "fileName", label: "photo", fileIDs: [1] },
    });
    expect(activeSectionID(navigation.state())).toBe("search");
});
