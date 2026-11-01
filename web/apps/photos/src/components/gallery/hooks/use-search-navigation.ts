import { PseudoCollectionID } from "ente-new/photos/services/collection-summary";
import type {
    SearchOption,
    SidebarActionID,
} from "ente-new/photos/services/search/types";
import { useCallback } from "react";
import { albumShortcutCollectionID } from "../helpers";
import type {
    GalleryNavigationState,
    NavigationAction,
} from "../navigation-state";
import type { PhotosNavigationActions } from "../PhotosNavigationContext";
import type { GalleryState } from "../reducer";

export const useSearchNavigation = ({
    library,
    navigation,
    send,
    showCollectionSummary,
    showSettings,
}: {
    library: GalleryState;
    navigation: GalleryNavigationState;
    send: React.Dispatch<NavigationAction>;
    showCollectionSummary: PhotosNavigationActions["showCollectionSummary"];
    showSettings: (action?: SidebarActionID) => void;
}) =>
    useCallback(
        (
            option: SearchOption | undefined,
            options?: { shouldExitSearchMode?: boolean },
        ) => {
            send({ type: "closeMap" });
            if (!option) {
                send({
                    type: "exitSearch",
                    shouldExitSearchMode: options?.shouldExitSearchMode ?? true,
                });
                return;
            }
            send({ type: "dismissCleanup" });
            const suggestion = option.suggestion;
            if (suggestion.type === "sidebarAction") {
                const id = albumShortcutCollectionID(
                    suggestion.actionID,
                    library.uncategorizedCollectionSummaryID,
                );
                if (id !== undefined) {
                    void showCollectionSummary(
                        id,
                        id === PseudoCollectionID.hiddenItems,
                    );
                    return;
                }
                showSettings(suggestion.actionID);
                send({
                    type: "exitSearch",
                    shouldExitSearchMode: options?.shouldExitSearchMode ?? true,
                });
            } else if (suggestion.type === "collection")
                send({
                    type: "showCollectionSummary",
                    collectionSummaryID: suggestion.collectionID,
                    library,
                });
            else if (suggestion.type === "person")
                send({ type: "showPerson", personID: suggestion.person.id });
            else {
                if (navigation.destination.albumMode === "hidden-albums")
                    send({ type: "showAlbums" });
                send({ type: "enterSearchMode", searchSuggestion: suggestion });
            }
        },
        [
            library,
            navigation.destination.albumMode,
            send,
            showCollectionSummary,
            showSettings,
        ],
    );
