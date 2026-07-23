import type { LocalUser } from "ente-accounts/services/user";
import {
    groupFilesByCollectionID,
    sortFiles,
    uniqueFilesByID,
} from "ente-gallery/utils/file";
import {
    CollectionOrder,
    collectionTypes,
    type Collection,
} from "ente-media/collection";
import type { EnteFile } from "ente-media/file";
import {
    isArchivedFile,
    metadataHash,
    type FilePrivateMagicMetadataData,
} from "ente-media/file-metadata";
import type { MagicMetadata } from "ente-media/magic-metadata";
import {
    createCollectionNameByID,
    isArchivedCollection,
    isHiddenCollection,
} from "ente-new/photos/services/collection";
import { sortTrashItems, type TrashItem } from "ente-new/photos/services/trash";
import { splitByPredicate } from "ente-utils/array";
import { includes } from "ente-utils/type-guards";
import { t } from "i18next";
import React, { useReducer } from "react";
import {
    findDefaultHiddenCollectionIDs,
    isDefaultHiddenCollection,
} from "../../services/collection";
import {
    CollectionSummarySortPriority,
    PseudoCollectionID,
    type CollectionSummary,
    type CollectionSummaryAttribute,
    type CollectionSummaryType,
} from "../../services/collection-summary";
import type { PeopleState, Person } from "../../services/ml/people";
import type { SearchSuggestion } from "../../services/search/types";
import type { FamilyData, UserDetails } from "../../services/user-details";

/**
 * Specifies what the bar at the top of the gallery is displaying currently.
 *
 * TODO: Deprecated(?). Use GalleryView instead. Deprecated if it can be used in
 * all cases where the bar mode was in use.
 */
export type GalleryBarMode =
    | "albums"
    | "hidden-albums"
    | "archive-albums"
    | "people";

/**
 * Specifies what the gallery is currently displaying.
 *
 * This can be overridden by the display of search results.
 */
export type GalleryView =
    | {
          /**
           * We're in the Albums, Hidden albums, or Archive section.
           */
          type: "albums" | "hidden-albums" | "archive-albums";
          activeCollectionSummaryID: number;
          /**
           * If the active collection ID is for a collection and not a
           * pseudo-collection, this property will be set to the corresponding
           * {@link Collection}.
           *
           * It is guaranteed that this will be one of the {@link collections}.
           */
          activeCollection: Collection | undefined;
          /**
           * The currently active collection summary.
           */
          activeCollectionSummary: CollectionSummary;
      }
    | {
          /**
           * We're in the "People" section.
           */
          type: "people";
          /**
           * The list of people to show in the gallery bar.
           *
           * Note that this can be different from the underlying list of
           * visiblePeople in the {@link peopleState}, and can temporarily
           * include a person from outside that list.
           */
          visiblePeople: Person[];
          /**
           * The full list of people, with temporary hide/delete state applied.
           */
          people: Person[];
          /**
           * The currently selected person in the gallery bar, if any.
           *
           * It is guaranteed that when it is set, {@link activePerson} will be
           * one of the objects from among {@link people}.
           */
          activePerson: Person | undefined;
      };

/**
 * Derived UI state backing the gallery.
 *
 * This might be different from the actual different from the actual underlying
 * state since there might be unsynced data (hidden or deleted that have not yet
 * been synced with remote) that should be temporarily taken into account for
 * the UI state until the operation completes.
 */
export interface GalleryState {
    /*--<  Mostly static state  >--*/

    /**
     * The logged in {@link LocalUser}.
     *
     * This is expected to be undefined only for a brief duration until the code
     * for the initial "mount" runs (If we're not logged in, then the gallery
     * will redirect the user to an appropriate authentication page).
     */
    user: LocalUser | undefined;
    /**
     * Family plan related information for the logged in {@link LocalUser}.
     */
    familyData: FamilyData | undefined;

    /*--<  Primary state: Files, collections, people  >--*/

    /**
     * The user's collections.
     */
    collections: Collection[];
    /**
     * The user's files, without any unsynced modifications applied to them.
     *
     * The list is sorted so that newer files are first.
     *
     * This property is expected to be of use only internal to the reducer;
     * external code should only needs {@link files} instead.
     */
    lastSyncedCollectionFiles: EnteFile[];
    /**
     * The items in the user's trash.
     *
     * The items are sorted in ascending order of their time to deletion. For
     * more details about the sorting order, see {@link sortTrashItems}.
     */
    trashItems: TrashItem[];
    /**
     * Latest snapshot of people related state, as reported by
     * {@link usePeopleStateSnapshot}.
     */
    peopleState: PeopleState | undefined;

    /*--<  Derived state  >--*/

    /**
     * The user's "collection files", with any unsynced modifications also
     * applied to them.
     *
     * "Collection files" means that there might be multiple entries for the
     * same file ID, one for each collection the file belongs to. For more
     * details, see [Note: Collection file].
     *
     * The list is sorted so that newer files are first.
     *
     * See {@link lastSyncedFiles} for the same list, but without unsynced
     * modifications.
     *
     * [Note: Unsynced modifications]
     *
     * Unsynced modifications are those whose effects have already been made on
     * remote (so thus they have been "saved", so to say), but we still haven't
     * yet refreshed our local state to incorporate them. The refresh will
     * happen on the next files pull, until then they remain as in-memory state
     * in the reducer.
     */
    collectionFiles: EnteFile[];
    /**
     * Collection IDs of hidden collections.
     */
    hiddenCollectionIDs: Set<number>;
    /**
     * Collection IDs of default hidden collections.
     *
     * The default hidden collection contains files that have been hidden
     * individually. Rarely, but it is a technical possibility, multiple clients
     * might create such "default" hidden collections. So this needs to be a set
     * of IDs, but usually will be only one. In either case, the client shows a
     * "merged" default hidden collection to the user.
     */
    defaultHiddenCollectionIDs: Set<number>;
    /**
     * File IDs of hidden files.
     *
     * [Note: Hidden files]
     *
     * Files can be individually hidden, or hidden by virtue of being placed in
     * a hidden album. However unlike archiving (See: [Note: Archived files]),
     * in the case of individually hiding a file, we do not set a file level
     * property but rather move it to the "default hidden collection".
     *
     * So effectively, files can be hidden only by virtue of being present in a
     * hidden collection.
     *
     * If a file is present in any hidden collection, then it is considered
     * hidden. Since this computation requires multiple steps, we precompute the
     * list of such files and keep it this set.
     */
    hiddenFileIDs: Set<number>;
    /**
     * Collection IDs of archived collections.
     */
    archivedCollectionIDs: Set<number>;
    /**
     * File IDs of the files that the user has archived.
     *
     * Includes the effects of {@link unsyncedVisibilityUpdates}.
     *
     * [Note: Archived files]
     *
     * Files can be individually archived (which is a file level property), or
     * archived by virtue of being placed in an archived album (which is a
     * collection file level property).
     *
     * Archived files are not supposed to be shown in the all section,
     * irrespective of which of those two way they obtain their archive status.
     *
     * In particular, a (collection) file can be both in an archived album and
     * an normal album, so just checking for membership in archived collections
     * is not enough to filter them out from all. Instead, we need to compile a
     * list of file IDs that have the archive status, and then filter the
     * collection files using this list.
     *
     * For fast filtering, this is a set instead of a list.
     */
    archivedFileIDs: Set<number>;
    /**
     * File IDs of all the files that the user has marked as a favorite.
     *
     * Includes the effects of {@link unsyncedFavoriteUpdates}.
     *
     * For fast lookup, this is a set instead of a list.
     */
    favoriteFileIDs: Set<number>;
    /**
     * A map from collection IDs to their user visible name.
     *
     * It will contain entries for all collections (both normal and hidden).
     */
    collectionNameByID: Map<number, string>;
    /**
     * A map from file IDs to the IDs of the normal (non-hidden) collections
     * that they're a part of.
     */
    fileNormalCollectionIDs: Map<number, number[]>;
    /**
     * A map from known Ente user IDs to their emails
     *
     * This will not have an entry for the user themselves.
     *
     * This is used to perform a fast lookup of the email of the Ente user that
     * shared a file or collection.
     */
    emailByUserID: Map<number, string>;
    /**
     * A list of emails that can be served as suggestions when the user is
     * trying to share a collection with another Ente user.
     *
     * These are derived from the emails of the Ente users with whom the user
     * has already shared collections, plus the emails of their family members.
     */
    shareSuggestionEmails: string[];

    /*--<  Derived UI state  >--*/

    /**
     * A map of normal (non-hidden) collections massaged into a form suitable
     * for being directly consumed by the UI, indexed by the collection IDs.
     */
    normalCollectionSummaries: Map<number, CollectionSummary>;
    /**
     * A variant of {@link normalCollectionSummaries}, but for hidden
     * collections.
     */
    hiddenCollectionSummaries: Map<number, CollectionSummary>;
    /**
     * A variant of {@link normalCollectionSummaries}, but for archived
     * collections and the archive section entry.
     */
    archivedCollectionSummaries: Map<number, CollectionSummary>;
    /**
     * The ID of the collection summary that should be shown when the user
     * navigates to the uncategorized section.
     *
     * This will be either the ID of the user's uncategorized collection, if one
     * has already been created, otherwise it will be the predefined
     * {@link PseudoCollectionID.uncategorizedPlaceholder}.
     *
     * See: [Note: Uncategorized placeholder]
     */
    uncategorizedCollectionSummaryID: number;

    /*--<  In-flight updates  >--*/

    /**
     * File IDs of the files that have been just been deleted by the user.
     *
     * The delete on remote for these has either completed, or is currently in
     * flight, but the local state has not yet been updated. We stash these
     * changes here temporarily so that the UI can reflect the changes until our
     * local state also gets synced in a bit.
     */
    tempDeletedFileIDs: Set<number>;
    /**
     * Variant of {@link tempDeletedFileIDs} for files that have just been
     * hidden.
     */
    tempHiddenFileIDs: Set<number>;
    /**
     * File (IDs) for which there is currently an in-flight favorite /
     * unfavorite operation.
     *
     * See also {@link unsyncedFavoriteUpdates}.
     */
    pendingFavoriteUpdates: Set<number>;
    /**
     * Local favorite status overlay for updates triggered by an interactive
     * user action. Some entries may still be pending remote mutation, while
     * others may have succeeded remotely but not yet been synced back to our
     * local DB.
     *
     * Each entry is keyed by file ID for owned files, and by hash/type for
     * non-owned shared files. This keeps equivalent shared-file updates
     * last-writer-wins before the next remote pull.
     *
     * The next time a remote pull completes, we clear this map since thereafter
     * just deriving {@link favoriteFileIDs} from our local files would reflect
     * the correct state on remote too.
     */
    unsyncedFavoriteUpdates: Map<
        UnsyncedFavoriteUpdateKey,
        UnsyncedFavoriteUpdate
    >;
    /**
     * File (IDs) for which there is currently an in-flight archive / unarchive
     * operation.
     *
     * See also {@link unsyncedPrivateMagicMetadataUpdates}.
     */
    pendingVisibilityUpdates: Set<number>;
    /**
     * Updates to file magic metadata (triggered by some interactive user
     * action) that have already been made to applied to remote, but whose
     * effects on remote have not yet been synced back to our local DB.
     *
     * Each entry from a file ID to the magic metadata that should be used for
     * that file instead of what we get from our local DB.
     *
     * The next time a remote pull completes, we clear this map since thereafter
     * the synced files themselves will reflect the latest private magic
     * metadata.
     */
    unsyncedPrivateMagicMetadataUpdates: Map<
        number,
        MagicMetadata<FilePrivateMagicMetadataData>
    >;

    /*--<  State that underlies transient UI state  >--*/

    /**
     * The currently selected collection summary, if any.
     *
     * When present, this is used to derive the
     * {@link activeCollectionSummaryID} property of the {@link view}.
     *
     * UI code should use the {@link view}, this property is meant as the
     * underlying primitive state. In particular, this does not get reset when
     * we switch sections, which allows us to come back to the same active
     * collection (if possible) on switching back.
     */
    selectedCollectionSummaryID: number | undefined;
    /**
     * The currently selected person, if any.
     *
     * When present, it is used to derive the {@link activePerson} property of
     * the {@link view}.
     *
     * UI code should use the {@link view}, this property is meant as the
     * underlying primitive state. In particular, this does not get reset when
     * we switch sections, which allows us to come back to the same person (if
     * possible) on switching back.
     */
    selectedPersonID: string | undefined;
    /**
     * If present, this person is tacked on the the list of visible people
     * temporarily (until the user switches out from the people view).
     *
     * This is needed to retain a usually non-visible but temporarily selected
     * person in the people bar until the user switches to some other view.
     */
    extraVisiblePerson: Person | undefined;
    /**
     * The suggestion selected by the user from the search bar dropdown.
     *
     * This is used to compute the {@link searchResults}.
     */
    searchSuggestion: SearchSuggestion | undefined;
    /**
     * List of files that match the selected search option.
     *
     * This will be set only if we are showing search results.
     *
     * The search dropdown shows a list of options ("suggestions") that match
     * the user's search term. If the user selects from one of these options,
     * then we run a search to find all files that match that suggestion, and
     * set this value to the result.
     */
    searchResults: EnteFile[] | undefined;
    /**
     * `true` an external effect is currently (asynchronously) updating search
     * results.
     */
    isRecomputingSearchResults: boolean;
    /**
     * {@link SearchSuggestion}s that have been enqueued while we were
     * recomputing the current search results.
     *
     * We only need the last element of this array (if any), the rest are
     * discarded when we get around to processing these.
     */
    pendingSearchSuggestions: SearchSuggestion[];

    /*--<  Transient UI state  >--*/

    /**
     * The view, and the item within it, that the gallery is currently showing.
     *
     * This can be temporarily overridden when we display search results.
     */
    view: GalleryView | undefined;
    /**
     * `true` if we are in "search mode".
     *
     * We will always be in search mode if we are showing search results, but we
     * also may be in search mode earlier on smaller screens, where the search
     * input is only shown on entering search mode. See: [Note: "Search mode"].
     *
     * That is, {@link isInSearchMode} may be true even when
     * {@link searchResults} is undefined.
     *
     * We will be _showing_ search results if both {@link isInSearchMode} is
     * `true` and {@link searchResults} is defined.
     */
    isInSearchMode: boolean;
    /**
     * Sort order for search results.
     *
     * - `undefined`: No explicit sort selected, keep original order (preserves
     *   CLIP relevance sorting for ML searches)
     * - `true`: Ascending order (oldest first)
     * - `false`: Descending order (newest first)
     */
    searchSortAsc: boolean | undefined;
    /**
     * The files to show, uniqued and sorted appropriately.
     */
    filteredFiles: EnteFile[];
}

export type GalleryAction =
    | {
          type: "mount";
          user: LocalUser;
          familyData: FamilyData | undefined;
          collections: Collection[];
          collectionFiles: EnteFile[];
          trashItems: TrashItem[];
      }
    | { type: "setUserDetails"; userDetails: UserDetails }
    | { type: "setCollections"; collections: Collection[] }
    | { type: "setCollectionFiles"; collectionFiles: EnteFile[] }
    | { type: "uploadFile"; file: EnteFile }
    | { type: "setTrashItems"; trashItems: TrashItem[] }
    | { type: "setPeopleState"; peopleState: PeopleState | undefined }
    | { type: "markTempDeleted"; files: EnteFile[] }
    | { type: "clearTempDeleted" }
    | { type: "markTempHidden"; files: EnteFile[] }
    | { type: "clearTempHidden" }
    | { type: "addPendingFavoriteUpdate"; fileID: number }
    | { type: "removePendingFavoriteUpdate"; fileID: number }
    | { type: "unsyncedFavoriteUpdate"; file: EnteFile; isFavorite: boolean }
    | { type: "addPendingVisibilityUpdate"; fileID: number }
    | { type: "removePendingVisibilityUpdate"; fileID: number }
    | {
          type: "unsyncedPrivateMagicMetadataUpdate";
          fileID: number;
          privateMagicMetadata: MagicMetadata<FilePrivateMagicMetadataData>;
      }
    | { type: "clearUnsyncedState" }
    | { type: "showAll" }
    | { type: "showHidden" }
    | { type: "showAlbums" }
    | { type: "showCollectionSummary"; collectionSummaryID: number | undefined }
    | { type: "showPeople" }
    | { type: "showPerson"; personID: string }
    | { type: "enterSearchMode"; searchSuggestion?: SearchSuggestion }
    | { type: "updatingSearchResults" }
    | { type: "setSearchResults"; searchResults: EnteFile[] }
    | { type: "exitSearch"; shouldExitSearchMode?: boolean }
    | { type: "setSearchSortOrder"; asc: boolean | undefined };

const initialGalleryState: GalleryState = {
    user: undefined,
    familyData: undefined,
    collections: [],
    lastSyncedCollectionFiles: [],
    trashItems: [],
    peopleState: undefined,
    collectionFiles: [],
    hiddenCollectionIDs: new Set(),
    defaultHiddenCollectionIDs: new Set(),
    hiddenFileIDs: new Set(),
    archivedCollectionIDs: new Set(),
    archivedFileIDs: new Set(),
    favoriteFileIDs: new Set(),
    collectionNameByID: new Map(),
    fileNormalCollectionIDs: new Map(),
    emailByUserID: new Map(),
    shareSuggestionEmails: [],
    normalCollectionSummaries: new Map(),
    hiddenCollectionSummaries: new Map(),
    archivedCollectionSummaries: new Map(),
    uncategorizedCollectionSummaryID:
        PseudoCollectionID.uncategorizedPlaceholder,
    tempDeletedFileIDs: new Set(),
    tempHiddenFileIDs: new Set(),
    pendingFavoriteUpdates: new Set(),
    unsyncedFavoriteUpdates: new Map(),
    pendingVisibilityUpdates: new Set(),
    unsyncedPrivateMagicMetadataUpdates: new Map(),
    selectedCollectionSummaryID: undefined,
    selectedPersonID: undefined,
    extraVisiblePerson: undefined,
    searchSuggestion: undefined,
    searchResults: undefined,
    isRecomputingSearchResults: false,
    pendingSearchSuggestions: [],
    view: undefined,
    filteredFiles: [],
    isInSearchMode: false,
    searchSortAsc: undefined,
};

const galleryReducer: React.Reducer<GalleryState, GalleryAction> = (
    state,
    action,
) => {
    switch (action.type) {
        case "mount": {
            const { user, familyData } = action;

            const lastSyncedCollectionFiles = sortFiles(action.collectionFiles);
            const trashItems = sortTrashItems(action.trashItems);

            // During mount there are no unsynced updates, and we can directly
            // use the provided files.
            const collectionFiles = lastSyncedCollectionFiles;

            const collections = action.collections;

            const {
                normalCollections,
                hiddenCollections,
                hiddenCollectionIDs,
                hiddenFileIDs,
            } = deriveHiddenInfo(collections, collectionFiles);

            const archivedCollectionIDs =
                deriveArchivedCollectionIDs(normalCollections);
            const archivedFileIDs = deriveArchivedFileIDs(
                archivedCollectionIDs,
                collectionFiles,
            );

            const normalCollectionSummaries = deriveNormalCollectionSummaries(
                normalCollections,
                action.user,
                trashItems,
                collectionFiles,
                hiddenFileIDs,
                archivedFileIDs,
            );

            const hiddenCollectionSummaries = deriveHiddenCollectionSummaries(
                hiddenCollections,
                action.user,
                collectionFiles,
            );
            const archivedCollectionSummaries =
                deriveArchivedCollectionSummaries(
                    normalCollections,
                    action.user,
                    collectionFiles,
                    hiddenFileIDs,
                );

            const view = {
                type: "albums" as const,
                activeCollectionSummaryID: PseudoCollectionID.all,
                activeCollection: undefined,
                activeCollectionSummary: normalCollectionSummaries.get(
                    PseudoCollectionID.all,
                )!,
            };

            return stateByUpdatingFilteredFiles({
                ...state,
                user,
                familyData,
                collections,
                lastSyncedCollectionFiles,
                trashItems,
                collectionFiles,
                hiddenCollectionIDs,
                defaultHiddenCollectionIDs:
                    deriveDefaultHiddenCollectionIDs(hiddenCollections),
                hiddenFileIDs,
                archivedCollectionIDs,
                archivedFileIDs,
                favoriteFileIDs: deriveFavoriteFileIDs(
                    action.user,
                    collections,
                    collectionFiles,
                    state.unsyncedFavoriteUpdates,
                ),
                collectionNameByID: createCollectionNameByID(
                    action.collections,
                ),
                fileNormalCollectionIDs: deriveFileNormalCollectionIDs(
                    collectionFiles,
                    hiddenCollectionIDs,
                ),
                emailByUserID: constructUserIDToEmailMap(user, collections),
                shareSuggestionEmails: createShareSuggestionEmails(
                    user,
                    familyData,
                    collections,
                ),
                normalCollectionSummaries,
                hiddenCollectionSummaries,
                archivedCollectionSummaries,
                uncategorizedCollectionSummaryID:
                    deriveUncategorizedCollectionSummaryID(normalCollections),
                view,
            });
        }

        case "setUserDetails": {
            // While user details have more state that can change, the only
            // changes that affect the reducer's state (so far) are if the
            // user's own email changes, or the list of their family members
            // changes.
            //
            // Both of these affect only the list of share suggestion emails.

            let user = state.user!;
            const { email, familyData } = action.userDetails;
            if (email != user.email) {
                user = { ...user, email };
            }

            return {
                ...state,
                user,
                familyData,
                shareSuggestionEmails: createShareSuggestionEmails(
                    user,
                    familyData,
                    state.collections,
                ),
            };
        }

        case "setCollections": {
            const collections = action.collections;

            const {
                normalCollections,
                hiddenCollections,
                hiddenCollectionIDs,
                hiddenFileIDs,
            } = deriveHiddenInfo(collections, state.collectionFiles);

            const archivedCollectionIDs =
                deriveArchivedCollectionIDs(normalCollections);
            const archivedFileIDs = deriveArchivedFileIDs(
                archivedCollectionIDs,
                state.collectionFiles,
            );

            const normalCollectionSummaries = deriveNormalCollectionSummaries(
                normalCollections,
                state.user!,
                state.trashItems,
                state.collectionFiles,
                hiddenFileIDs,
                archivedFileIDs,
            );

            const hiddenCollectionSummaries = deriveHiddenCollectionSummaries(
                hiddenCollections,
                state.user!,
                state.collectionFiles,
            );
            const archivedCollectionSummaries =
                deriveArchivedCollectionSummaries(
                    normalCollections,
                    state.user!,
                    state.collectionFiles,
                    hiddenFileIDs,
                );

            // Revalidate the active view if needed.
            let view = state.view;
            let selectedCollectionSummaryID = state.selectedCollectionSummaryID;
            if (state.view?.type == "albums") {
                ({ view, selectedCollectionSummaryID } =
                    deriveAlbumsViewAndSelectedID(
                        collections,
                        hiddenCollectionIDs,
                        normalCollectionSummaries,
                        selectedCollectionSummaryID,
                    ));
            } else if (state.view?.type == "hidden-albums") {
                ({ view, selectedCollectionSummaryID } =
                    deriveHiddenAlbumsViewAndSelectedID(
                        collections,
                        hiddenCollectionIDs,
                        hiddenCollectionSummaries,
                        selectedCollectionSummaryID,
                    ));
            } else if (state.view?.type == "archive-albums") {
                ({ view, selectedCollectionSummaryID } =
                    deriveArchiveAlbumsViewAndSelectedID(
                        collections,
                        archivedCollectionSummaries,
                        selectedCollectionSummaryID,
                    ));
            }

            return stateByUpdatingFilteredFiles({
                ...state,
                collections,
                hiddenCollectionIDs,
                defaultHiddenCollectionIDs:
                    deriveDefaultHiddenCollectionIDs(hiddenCollections),
                hiddenFileIDs,
                archivedCollectionIDs,
                archivedFileIDs,
                favoriteFileIDs: deriveFavoriteFileIDs(
                    state.user!,
                    normalCollections,
                    state.collectionFiles,
                    state.unsyncedFavoriteUpdates,
                ),
                collectionNameByID: createCollectionNameByID(collections),
                fileNormalCollectionIDs: deriveFileNormalCollectionIDs(
                    state.collectionFiles,
                    hiddenCollectionIDs,
                ),
                emailByUserID: constructUserIDToEmailMap(
                    state.user!,
                    collections,
                ),
                shareSuggestionEmails: createShareSuggestionEmails(
                    state.user!,
                    state.familyData,
                    collections,
                ),
                normalCollectionSummaries,
                hiddenCollectionSummaries,
                archivedCollectionSummaries,
                uncategorizedCollectionSummaryID:
                    deriveUncategorizedCollectionSummaryID(normalCollections),
                selectedCollectionSummaryID,
                pendingSearchSuggestions:
                    enqueuePendingSearchSuggestionsIfNeeded(
                        state.searchSuggestion,
                        state.pendingSearchSuggestions,
                        state.isInSearchMode,
                    ),
                view,
            });
        }

        case "setCollectionFiles": {
            const lastSyncedCollectionFiles = sortFiles(action.collectionFiles);
            const collectionFiles = lastSyncedCollectionFiles;

            return stateByUpdatingFilteredFiles({
                ...stateForUpdatedCollectionFiles(state, collectionFiles),
                lastSyncedCollectionFiles,
                unsyncedPrivateMagicMetadataUpdates: new Map(),
            });
        }

        case "uploadFile": {
            // TODO: Consider batching this instead of doing it per file
            // upload to speed up uploads. Perf test first though.

            const lastSyncedCollectionFiles = sortFiles([
                ...state.lastSyncedCollectionFiles,
                action.file,
            ]);
            const collectionFiles = deriveCollectionFiles(
                lastSyncedCollectionFiles,
                state.unsyncedPrivateMagicMetadataUpdates,
            );

            return stateByUpdatingFilteredFiles({
                ...stateForUpdatedCollectionFiles(state, collectionFiles),
                lastSyncedCollectionFiles,
            });
        }

        case "setTrashItems": {
            const trashItems = sortTrashItems(action.trashItems);

            return stateByUpdatingFilteredFiles({
                ...state,
                trashItems,
                normalCollectionSummaries: deriveNormalCollectionSummaries(
                    state.collections.filter(
                        (c) => !state.hiddenCollectionIDs.has(c.id),
                    ),
                    state.user!,
                    trashItems,
                    state.collectionFiles,
                    state.hiddenFileIDs,
                    state.archivedFileIDs,
                ),
            });
        }

        case "setPeopleState": {
            const peopleState = action.peopleState;

            if (state.view?.type != "people") return { ...state, peopleState };

            const { view, extraVisiblePerson } = derivePeopleView(
                peopleState,
                state.tempDeletedFileIDs,
                state.tempHiddenFileIDs,
                state.selectedPersonID,
                state.extraVisiblePerson,
            );
            return stateByUpdatingFilteredFiles({
                ...state,
                peopleState,
                selectedPersonID: view.activePerson?.id,
                extraVisiblePerson,
                view,
            });
        }

        case "markTempDeleted":
            return stateByUpdatingFilteredFiles({
                ...state,
                tempDeletedFileIDs: new Set(
                    [...state.tempDeletedFileIDs].concat(
                        action.files.map((f) => f.id),
                    ),
                ),
            });

        case "clearTempDeleted":
            return stateByUpdatingFilteredFiles({
                ...state,
                tempDeletedFileIDs: new Set(),
            });

        case "markTempHidden":
            return stateByUpdatingFilteredFiles({
                ...state,
                tempHiddenFileIDs: new Set(
                    [...state.tempHiddenFileIDs].concat(
                        action.files.map((f) => f.id),
                    ),
                ),
            });

        case "clearTempHidden":
            return stateByUpdatingFilteredFiles({
                ...state,
                tempHiddenFileIDs: new Set(),
            });

        case "addPendingFavoriteUpdate": {
            const pendingFavoriteUpdates = new Set(
                state.pendingFavoriteUpdates,
            );
            pendingFavoriteUpdates.add(action.fileID);
            return { ...state, pendingFavoriteUpdates };
        }

        case "removePendingFavoriteUpdate": {
            const pendingFavoriteUpdates = new Set(
                state.pendingFavoriteUpdates,
            );
            pendingFavoriteUpdates.delete(action.fileID);
            return { ...state, pendingFavoriteUpdates };
        }

        case "unsyncedFavoriteUpdate": {
            const unsyncedFavoriteUpdates = new Map(
                state.unsyncedFavoriteUpdates,
            );
            const fileHashAndTypeKey =
                action.file.ownerID == state.user!.id
                    ? undefined
                    : favoriteFileHashAndTypeKey(action.file);
            if (action.file.ownerID != state.user!.id && !fileHashAndTypeKey) {
                return state;
            }
            const updateKey = fileHashAndTypeKey ?? action.file.id;
            unsyncedFavoriteUpdates.set(updateKey, {
                fileID: action.file.id,
                fileHashAndTypeKey,
                isFavorite: action.isFavorite,
            });

            // Skipping a call to stateByUpdatingFilteredFiles since it
            // currently doesn't depend on favorites.
            return {
                ...state,
                favoriteFileIDs: deriveFavoriteFileIDs(
                    state.user!,
                    state.collections,
                    state.collectionFiles,
                    unsyncedFavoriteUpdates,
                ),
                unsyncedFavoriteUpdates,
            };
        }

        case "addPendingVisibilityUpdate": {
            const pendingVisibilityUpdates = new Set(
                state.pendingVisibilityUpdates,
            );
            pendingVisibilityUpdates.add(action.fileID);
            // Not using stateByUpdatingFilteredFiles since it does not depend
            // on pendingVisibilityUpdates.
            return { ...state, pendingVisibilityUpdates };
        }

        case "removePendingVisibilityUpdate": {
            const pendingVisibilityUpdates = new Set(
                state.pendingVisibilityUpdates,
            );
            pendingVisibilityUpdates.delete(action.fileID);
            return { ...state, pendingVisibilityUpdates };
        }

        case "unsyncedPrivateMagicMetadataUpdate": {
            const unsyncedPrivateMagicMetadataUpdates = new Map(
                state.unsyncedPrivateMagicMetadataUpdates,
            );
            unsyncedPrivateMagicMetadataUpdates.set(
                action.fileID,
                action.privateMagicMetadata,
            );

            const collectionFiles = deriveCollectionFiles(
                state.lastSyncedCollectionFiles,
                unsyncedPrivateMagicMetadataUpdates,
            );

            return stateByUpdatingFilteredFiles({
                ...stateForUpdatedCollectionFiles(state, collectionFiles),
                unsyncedPrivateMagicMetadataUpdates,
            });
        }

        case "clearUnsyncedState": {
            // Getting the last syncedCollectionFiles
            const collectionFiles = state.lastSyncedCollectionFiles;

            // Getting the FavoriteFileIDs from the syncedData
            // without applying any optimistic chagnes.
            const syncedFavoriteFileIDs = deriveFavoriteFileIDs(
                state.user!,
                state.collections,
                collectionFiles,
                new Map(),
            );

            const unsyncedFavoriteUpdates: GalleryState["unsyncedFavoriteUpdates"] =
                preserveUnreflectedFavoriteUpdates(
                    state.user!,
                    collectionFiles,
                    syncedFavoriteFileIDs,
                    state.unsyncedFavoriteUpdates,
                );
            const favoriteFileIDs = deriveFavoriteFileIDs(
                state.user!,
                state.collections,
                collectionFiles,
                unsyncedFavoriteUpdates,
            );

            const unsyncedPrivateMagicMetadataUpdates: GalleryState["unsyncedPrivateMagicMetadataUpdates"] =
                new Map();

            return stateByUpdatingFilteredFiles({
                ...stateForUpdatedCollectionFiles(
                    {
                        ...state,
                        favoriteFileIDs,
                        tempDeletedFileIDs: new Set(),
                        tempHiddenFileIDs: new Set(),
                        pendingFavoriteUpdates: new Set(),
                        pendingVisibilityUpdates: new Set(),
                        unsyncedPrivateMagicMetadataUpdates,
                        unsyncedFavoriteUpdates,
                    },
                    collectionFiles,
                ),
                unsyncedPrivateMagicMetadataUpdates,
            });
        }

        case "showAll":
            return stateByUpdatingFilteredFiles({
                ...state,
                selectedCollectionSummaryID: undefined,
                extraVisiblePerson: undefined,
                searchSuggestion: undefined,
                searchResults: undefined,
                isRecomputingSearchResults: false,
                pendingSearchSuggestions: [],
                view: {
                    type: "albums",
                    activeCollectionSummaryID: PseudoCollectionID.all,
                    activeCollection: undefined,
                    activeCollectionSummary:
                        state.normalCollectionSummaries.get(
                            PseudoCollectionID.all,
                        )!,
                },
                isInSearchMode: false,
            });

        case "showHidden":
            return stateByUpdatingFilteredFiles({
                ...state,
                selectedCollectionSummaryID: undefined,
                extraVisiblePerson: undefined,
                searchSuggestion: undefined,
                searchResults: undefined,
                isRecomputingSearchResults: false,
                pendingSearchSuggestions: [],
                view: {
                    type: "hidden-albums",
                    activeCollectionSummaryID: PseudoCollectionID.hiddenItems,
                    activeCollection: undefined,
                    activeCollectionSummary:
                        state.hiddenCollectionSummaries.get(
                            PseudoCollectionID.hiddenItems,
                        )!,
                },
                isInSearchMode: false,
            });

        case "showAlbums": {
            const { view, selectedCollectionSummaryID } =
                deriveAlbumsViewAndSelectedID(
                    state.collections,
                    state.hiddenCollectionIDs,
                    state.normalCollectionSummaries,
                    state.selectedCollectionSummaryID,
                );

            return stateByUpdatingFilteredFiles({
                ...state,
                selectedCollectionSummaryID,
                extraVisiblePerson: undefined,
                searchSuggestion: undefined,
                searchResults: undefined,
                isRecomputingSearchResults: false,
                pendingSearchSuggestions: [],
                view,
                isInSearchMode: false,
            });
        }

        case "showCollectionSummary": {
            const selectedCollectionSummaryID = action.collectionSummaryID;
            const activeCollection = state.collections.find(
                ({ id }) => id == selectedCollectionSummaryID,
            );

            let view: GalleryState["view"];
            if (
                selectedCollectionSummaryID !== undefined &&
                state.hiddenCollectionSummaries.has(selectedCollectionSummaryID)
            ) {
                const activeCollectionSummaryID = selectedCollectionSummaryID;
                view = {
                    type: "hidden-albums",
                    activeCollectionSummaryID,
                    activeCollection,
                    activeCollectionSummary:
                        state.hiddenCollectionSummaries.get(
                            activeCollectionSummaryID,
                        )!,
                };
            } else if (
                selectedCollectionSummaryID !== undefined &&
                state.archivedCollectionSummaries.has(
                    selectedCollectionSummaryID,
                ) &&
                (state.view?.type == "archive-albums" ||
                    selectedCollectionSummaryID ==
                        PseudoCollectionID.archiveItems)
            ) {
                const activeCollectionSummaryID = selectedCollectionSummaryID;
                view = {
                    type: "archive-albums",
                    activeCollectionSummaryID,
                    activeCollection,
                    activeCollectionSummary:
                        state.archivedCollectionSummaries.get(
                            activeCollectionSummaryID,
                        )!,
                };
            } else {
                const activeCollectionSummaryID =
                    selectedCollectionSummaryID ?? PseudoCollectionID.all;
                view = {
                    type: "albums",
                    activeCollectionSummaryID,
                    activeCollection,
                    activeCollectionSummary:
                        state.normalCollectionSummaries.get(
                            activeCollectionSummaryID,
                        )!,
                };
            }

            return stateByUpdatingFilteredFiles({
                ...state,
                selectedCollectionSummaryID,
                extraVisiblePerson: undefined,
                searchResults: undefined,
                searchSuggestion: undefined,
                isRecomputingSearchResults: false,
                pendingSearchSuggestions: [],
                view,
                isInSearchMode: false,
            });
        }

        case "showPeople": {
            const { view, extraVisiblePerson } = derivePeopleView(
                state.peopleState,
                state.tempDeletedFileIDs,
                state.tempHiddenFileIDs,
                state.selectedPersonID,
                state.extraVisiblePerson,
            );
            return stateByUpdatingFilteredFiles({
                ...state,
                selectedPersonID: view.activePerson?.id,
                extraVisiblePerson,
                searchResults: undefined,
                searchSuggestion: undefined,
                isRecomputingSearchResults: false,
                pendingSearchSuggestions: [],
                view,
                isInSearchMode: false,
            });
        }

        case "showPerson": {
            const { view, extraVisiblePerson } = derivePeopleView(
                state.peopleState,
                state.tempDeletedFileIDs,
                state.tempHiddenFileIDs,
                action.personID,
                state.extraVisiblePerson,
            );
            return stateByUpdatingFilteredFiles({
                ...state,
                selectedPersonID: view.activePerson?.id,
                extraVisiblePerson,
                searchResults: undefined,
                searchSuggestion: undefined,
                isRecomputingSearchResults: false,
                pendingSearchSuggestions: [],
                view,
                isInSearchMode: false,
            });
        }

        case "enterSearchMode": {
            const pendingSearchSuggestions = action.searchSuggestion
                ? [...state.pendingSearchSuggestions, action.searchSuggestion]
                : state.pendingSearchSuggestions;

            return stateByUpdatingFilteredFiles({
                ...state,
                isInSearchMode: true,
                searchSuggestion: action.searchSuggestion,
                pendingSearchSuggestions,
            });
        }

        case "updatingSearchResults":
            return stateByUpdatingFilteredFiles({
                ...state,
                isRecomputingSearchResults: true,
                pendingSearchSuggestions: [],
            });

        case "setSearchResults":
            // Discard stale updates
            if (!state.isRecomputingSearchResults) return state;

            return stateByUpdatingFilteredFiles({
                ...state,
                searchResults: action.searchResults,
                isRecomputingSearchResults: false,
            });

        case "exitSearch": {
            // Only exit search mode if explicitly requested (defaults to true for backward compatibility)
            const shouldExitSearchMode = action.shouldExitSearchMode ?? true;
            return stateByUpdatingFilteredFiles({
                ...state,
                searchResults: undefined,
                searchSuggestion: undefined,
                isRecomputingSearchResults: false,
                pendingSearchSuggestions: [],
                isInSearchMode: shouldExitSearchMode
                    ? false
                    : state.isInSearchMode,
            });
        }

        case "setSearchSortOrder":
            return stateByUpdatingFilteredFiles({
                ...state,
                searchSortAsc: action.asc,
            });
    }
};

export const useGalleryReducer = () =>
    useReducer(galleryReducer, initialGalleryState);

/**
 * Compute the effective files that we should use by overlaying the files we
 * read from disk by any temporary unsynced updates.
 */
const deriveCollectionFiles = (
    lastSyncedCollectionFiles: GalleryState["lastSyncedCollectionFiles"],
    unsyncedPrivateMagicMetadataUpdates: GalleryState["unsyncedPrivateMagicMetadataUpdates"],
) => {
    // Happy fastpath.
    if (unsyncedPrivateMagicMetadataUpdates.size == 0)
        return lastSyncedCollectionFiles;

    // We have one or more unsynced private magic metadata updates that should
    // be applied to all the collection files with the matching file ID.
    return lastSyncedCollectionFiles.map((file) => {
        const privateMagicMetadata = unsyncedPrivateMagicMetadataUpdates.get(
            file.id,
        );
        if (!privateMagicMetadata) return file;

        return { ...file, magicMetadata: privateMagicMetadata };
    });
};

/**
 * Compute various bits of the state associated with hidden items from their
 * dependencies.
 */
const deriveHiddenInfo = (
    collections: GalleryState["collections"],
    collectionFiles: GalleryState["collectionFiles"],
) => {
    const [hiddenCollections, normalCollections] = splitByPredicate(
        collections,
        isHiddenCollection,
    );
    const hiddenCollectionIDs = new Set(hiddenCollections.map((c) => c.id));
    return {
        normalCollections,
        hiddenCollections,
        hiddenCollectionIDs,
        hiddenFileIDs: deriveHiddenFileIDs(
            collectionFiles,
            hiddenCollectionIDs,
        ),
    };
};

/**
 * Compute the list of hidden file IDs from their dependencies.
 */
const deriveHiddenFileIDs = (
    collectionFiles: GalleryState["collectionFiles"],
    hiddenCollectionIDs: GalleryState["hiddenCollectionIDs"],
) =>
    new Set(
        collectionFiles
            .filter((f) => hiddenCollectionIDs.has(f.collectionID))
            .map((f) => f.id),
    );

/**
 * Compute the default hidden collection IDs from their dependencies.
 */
const deriveDefaultHiddenCollectionIDs = (hiddenCollections: Collection[]) =>
    findDefaultHiddenCollectionIDs(hiddenCollections);

/**
 * Compute archived collection IDs from their dependencies.
 */
const deriveArchivedCollectionIDs = (collections: Collection[]) =>
    new Set<number>(
        collections
            .filter(isArchivedCollection)
            .map((collection) => collection.id),
    );

/**
 * Compute archived file IDs from their dependencies.
 */
const deriveArchivedFileIDs = (
    archivedCollectionIDs: GalleryState["archivedCollectionIDs"],
    collectionFiles: GalleryState["collectionFiles"],
) =>
    new Set(
        collectionFiles
            .filter(
                (file) =>
                    isArchivedFile(file) ||
                    archivedCollectionIDs.has(file.collectionID),
            )
            .map((f) => f.id),
    );

/**
 * Compute favorite file IDs from their dependencies.
 */
const deriveFavoriteFileIDs = (
    user: LocalUser,
    collections: GalleryState["collections"],
    collectionFiles: GalleryState["collectionFiles"],
    unsyncedFavoriteUpdates: GalleryState["unsyncedFavoriteUpdates"],
) => {
    let favoriteFileIDs = new Set<number>();
    let favoriteFileHashAndTypeKeys = new Set<string>();

    // Find the user's Favorites collection and derive both the concrete
    // favorite file IDs and the hash/type keys used to match shared copies.
    for (const collection of collections) {
        // See: [Note: User and shared favorites]
        if (collection.type == "favorites" && collection.owner.id == user.id) {
            const favoriteFiles = collectionFiles.filter(
                (file) => file.collectionID == collection.id,
            );
            favoriteFileIDs = new Set(favoriteFiles.map((file) => file.id));
            favoriteFileHashAndTypeKeys = new Set(
                favoriteFiles.flatMap((file) => {
                    const key = favoriteFileHashAndTypeKey(file);
                    return key ? [key] : [];
                }),
            );
            break;
        }
    }
    // A shared file has a different ID from the user-owned copy in Favorites.
    // If its hash/type key matches a favorite entry, mark the visible shared
    // file ID as favorite so the UI can show the star in shared albums.
    for (const file of collectionFiles) {
        if (file.ownerID == user.id) continue;

        const key = favoriteFileHashAndTypeKey(file);
        if (key && favoriteFileHashAndTypeKeys.has(key)) {
            favoriteFileIDs.add(file.id);
        }
    }

    // Apply favorite changes that have succeeded on remote but have not been
    // pulled into local collectionFiles yet. Hash/type updates apply to every
    // matching shared file; ID-based updates apply only to the clicked file.
    for (const update of unsyncedFavoriteUpdates.values()) {
        const updatedFileIDs = update.fileHashAndTypeKey
            ? collectionFiles
                  .filter(
                      (file) =>
                          file.ownerID != user.id &&
                          favoriteFileHashAndTypeKey(file) ==
                              update.fileHashAndTypeKey,
                  )
                  .map((file) => file.id)
            : [update.fileID];
        for (const fileID of updatedFileIDs) {
            if (update.isFavorite) favoriteFileIDs.add(fileID);
            else favoriteFileIDs.delete(fileID);
        }
    }
    return favoriteFileIDs;
};
/**
 *
 * @param user The currentLoggedIn User
 *
 *  @param collectionFiles  The collectionsFiles which the user currently has
 * from state.lastSyncedCollectionFiles
 *
 * @param syncedFavoriteFileIDs: The list of FavoriteFileIDs derived from
 * the collectionFiles without any optimistic updations.
 *
 * @param unsyncedFavoriteUpdates The list of FavoriteFileIDs derived from
 * the collectionFiles including any optimistic updates from the
 * state.unsyncedFavoriteUpdates,
 *
 * @returns the preservedUpdates, If there is atleast one affected file
 * where the synced state still disagrees with, we store that file's update in
 * this variable and return it else, it will be an empty map.
 */
const preserveUnreflectedFavoriteUpdates = (
    user: LocalUser,
    collectionFiles: GalleryState["collectionFiles"],
    syncedFavoriteFileIDs: GalleryState["favoriteFileIDs"],
    unsyncedFavoriteUpdates: GalleryState["unsyncedFavoriteUpdates"],
) => {
    const preservedUpdates: GalleryState["unsyncedFavoriteUpdates"] = new Map();

    /**
     * Iterating through the unsyncedFavoriteUpdates, if the file has
     * fileHashAndTypeKey it's a shared album file, if so then, finding
     * all non-owned/shared file sin the gallery whose hash/type matches
     * this update and storing their IDs to the updatedFileIDs.
     */
    for (const [key, update] of unsyncedFavoriteUpdates.entries()) {
        const updatedFileIDs = update.fileHashAndTypeKey
            ? collectionFiles
                  .filter(
                      (file) =>
                          file.ownerID != user.id &&
                          favoriteFileHashAndTypeKey(file) ==
                              update.fileHashAndTypeKey,
                  )
                  .map((file) => file.id)
            : [update.fileID];

        // So, If there at least one affected file where synced state still
        // disagrees with the optimistic update, we preserve the update, else ignore it.
        if (
            updatedFileIDs.some(
                (fileID) =>
                    syncedFavoriteFileIDs.has(fileID) != update.isFavorite,
            )
        ) {
            preservedUpdates.set(key, update);
        }
    }

    return preservedUpdates;
};

/**
 * Earlier the UnsyncedFavoriteUpdate was just an fileID
 * because we only had the option to favorite the owner files.
 * Now we can favorite the non-owned files as well.
 *
 * For which we need to do a fileHashAndTypeKey matching
 * therefore this new interface.
 */
interface UnsyncedFavoriteUpdate {
    fileID: number;
    fileHashAndTypeKey?: string;
    isFavorite: boolean;
}

type UnsyncedFavoriteUpdateKey = number | string;

const favoriteFileHashAndTypeKey = (file: EnteFile) => {
    const hash = metadataHash(file.metadata);
    return hash ? `${hash}:${file.metadata.fileType}` : undefined;
};

/**
 * Compute file to (non-hidden) collection mapping from its dependencies.
 */
const deriveFileNormalCollectionIDs = (
    collectionFiles: GalleryState["collectionFiles"],
    hiddenCollectionIDs: GalleryState["hiddenCollectionIDs"],
) =>
    createFileCollectionIDs(
        collectionFiles.filter((f) => !hiddenCollectionIDs.has(f.collectionID)),
    );

/**
 * Construct a map from file IDs to the list of collections (IDs) to which the
 * file belongs.
 */
const createFileCollectionIDs = (files: EnteFile[]) =>
    files.reduce((result, file) => {
        const id = file.id;
        let fs = result.get(id);
        if (!fs) result.set(id, (fs = []));
        fs.push(file.collectionID);
        return result;
    }, new Map<number, number[]>());

/**
 * Compute normal (non-hidden) collection summaries from their dependencies.
 */
const deriveNormalCollectionSummaries = (
    normalCollections: Collection[],
    user: LocalUser,
    trashItems: GalleryState["trashItems"],
    collectionFiles: GalleryState["collectionFiles"],
    hiddenFileIDs: GalleryState["hiddenFileIDs"],
    archivedFileIDs: GalleryState["archivedFileIDs"],
) => {
    const normalCollectionSummaries = createCollectionSummaries(
        user,
        normalCollections,
        collectionFiles,
    );

    const uncategorizedCollection = normalCollections.find(
        ({ type }) => type == "uncategorized",
    );
    if (!uncategorizedCollection) {
        const id = PseudoCollectionID.uncategorizedPlaceholder;
        normalCollectionSummaries.set(id, {
            ...pseudoCollectionOptionsForFiles([]),
            id,
            type: "uncategorized",
            attributes: new Set([
                "uncategorized",
                "system",
                "hideFromCollectionBar",
            ]),
            name: t("section_uncategorized"),
            sortPriority: CollectionSummarySortPriority.system,
        });
    }

    const allSectionFiles = uniqueFilesByID(
        collectionFiles.filter(
            (f) => !hiddenFileIDs.has(f.id) && !archivedFileIDs.has(f.id),
        ),
    );

    const archiveItemsFiles = deriveArchiveItemsFiles(
        collectionFiles,
        hiddenFileIDs,
    );

    normalCollectionSummaries.set(PseudoCollectionID.all, {
        ...pseudoCollectionOptionsForFiles(allSectionFiles),
        id: PseudoCollectionID.all,
        type: "all",
        attributes: new Set(["all", "system"]),
        name: t("section_all"),
        sortPriority: CollectionSummarySortPriority.system,
    });

    normalCollectionSummaries.set(PseudoCollectionID.trash, {
        ...pseudoCollectionOptionsForLatestFileAndCount(
            trashItems[0]?.file,
            trashItems.length,
        ),
        id: PseudoCollectionID.trash,
        name: t("section_trash"),
        type: "trash",
        attributes: new Set(["trash", "system", "hideFromCollectionBar"]),
        coverFile: undefined,
        sortPriority: CollectionSummarySortPriority.other,
    });

    normalCollectionSummaries.set(PseudoCollectionID.archiveItems, {
        ...pseudoCollectionOptionsForFiles(archiveItemsFiles),
        id: PseudoCollectionID.archiveItems,
        name: t("section_archive"),
        type: "archiveItems",
        attributes: new Set([
            "archiveItems",
            "system",
            "hideFromCollectionBar",
        ]),
        coverFile: undefined,
        sortPriority: CollectionSummarySortPriority.other,
    });

    return normalCollectionSummaries;
};

const pseudoCollectionOptionsForFiles = (files: EnteFile[]) =>
    pseudoCollectionOptionsForLatestFileAndCount(files[0], files.length);

const pseudoCollectionOptionsForLatestFileAndCount = (
    file: EnteFile | undefined,
    fileCount: number,
) => ({
    coverFile: file,
    latestFile: file,
    fileCount,
    updationTime: file?.updationTime,
});

const deriveArchiveItemsFiles = (
    collectionFiles: GalleryState["collectionFiles"],
    hiddenFileIDs: GalleryState["hiddenFileIDs"],
) =>
    uniqueFilesByID(
        collectionFiles.filter(
            (file) => !hiddenFileIDs.has(file.id) && isArchivedFile(file),
        ),
    );

/**
 * Compute hidden collection summaries from their dependencies.
 */
const deriveHiddenCollectionSummaries = (
    hiddenCollections: Collection[],
    user: LocalUser,
    collectionFiles: GalleryState["collectionFiles"],
) => {
    const hiddenCollectionSummaries = createCollectionSummaries(
        user,
        hiddenCollections,
        collectionFiles,
    );

    const dhcIDs = findDefaultHiddenCollectionIDs(hiddenCollections);
    const defaultHiddenFiles = uniqueFilesByID(
        collectionFiles.filter((file) => dhcIDs.has(file.collectionID)),
    );
    hiddenCollectionSummaries.set(PseudoCollectionID.hiddenItems, {
        ...pseudoCollectionOptionsForFiles(defaultHiddenFiles),
        id: PseudoCollectionID.hiddenItems,
        name: t("hidden_items"),
        type: "hiddenItems",
        attributes: new Set(["hiddenItems", "system"]),
        sortPriority: CollectionSummarySortPriority.system,
    });

    return hiddenCollectionSummaries;
};

/**
 * Compute archived collection summaries from their dependencies.
 */
const deriveArchivedCollectionSummaries = (
    normalCollections: Collection[],
    user: LocalUser,
    collectionFiles: GalleryState["collectionFiles"],
    hiddenFileIDs: GalleryState["hiddenFileIDs"],
) => {
    const archivedCollectionSummaries = createCollectionSummaries(
        user,
        normalCollections.filter(isArchivedCollection),
        collectionFiles,
    );

    archivedCollectionSummaries.set(PseudoCollectionID.archiveItems, {
        ...pseudoCollectionOptionsForFiles(
            deriveArchiveItemsFiles(collectionFiles, hiddenFileIDs),
        ),
        id: PseudoCollectionID.archiveItems,
        name: t("section_archive"),
        type: "archiveItems",
        attributes: new Set(["archiveItems", "system"]),
        sortPriority: CollectionSummarySortPriority.system,
    });

    return archivedCollectionSummaries;
};

/**
 * Return the ID of the collection summary that should be shown when the user
 * navigates to the uncategorized section.
 */
const deriveUncategorizedCollectionSummaryID = (
    normalCollections: Collection[],
) =>
    normalCollections.find(({ type }) => type == "uncategorized")?.id ??
    PseudoCollectionID.uncategorizedPlaceholder;

const createCollectionSummaries = (
    user: LocalUser,
    collections: Collection[],
    collectionFiles: EnteFile[],
) => {
    const collectionSummaries = new Map<number, CollectionSummary>();

    const filesByCollection = groupFilesByCollectionID(collectionFiles);
    const coverFiles = findCoverFiles(collections, filesByCollection);

    for (const collection of collections) {
        const collectionType = includes(collectionTypes, collection.type)
            ? collection.type
            : "album";

        const attributes = new Set<CollectionSummaryAttribute>();

        let type: CollectionSummaryType;
        let name = collection.name;
        let sortPriority: CollectionSummarySortPriority =
            CollectionSummarySortPriority.other;

        if (collection.owner.id != user.id) {
            // This case needs to be the first; the rest assume that they're
            // dealing with collections owned by the user.
            type = "sharedIncoming";
            attributes.add("shared");
            attributes.add("sharedIncoming");
            const userRole = collection.sharees.find(
                (s) => s.id == user.id,
            )?.role;
            attributes.add(
                userRole == "ADMIN"
                    ? "sharedIncomingAdmin"
                    : userRole == "COLLABORATOR"
                      ? "sharedIncomingCollaborator"
                      : "sharedIncomingViewer",
            );
        } else if (collectionType == "uncategorized") {
            type = "uncategorized";
            name = t("section_uncategorized");
            attributes.add("system");
            attributes.add("hideFromCollectionBar");
            sortPriority = CollectionSummarySortPriority.system;
        } else if (collectionType == "favorites") {
            // [Note: User and shared favorites]
            //
            // "favorites" can be both the user's own favorites, or favorites of
            // other users shared with them. However, all of the latter will get
            // typed as "sharedIncoming" in the first case above.
            //
            // So if we get here and the collection summary has type
            // "favorites", it is guaranteed to be the user's own favorites. We
            // mark these with the type "userFavorites", which gives it special
            // treatment like custom icon etc.
            //
            // However, notice that the type of the _collection_ itself is not
            // changed, so whenever we're checking the type of the collection
            // (not of the collection summary) and we specifically want to
            // target the user's own favorites, we also need to check the
            // collection owner's ID is the same as the logged in user's ID.
            //
            // This case needs to be above the other cases since the primary
            // classification of this collection summary is that it is the
            // user's "favorites", everything else is secondary and can be part
            // of the `attributes` computed below.
            type = "userFavorites";
            name = t("favorites");
            sortPriority = CollectionSummarySortPriority.favorites;
        } else if (isDefaultHiddenCollection(collection)) {
            type = "defaultHidden";
            attributes.add("system");
            attributes.add("hideFromCollectionBar");
        } else {
            type = collectionType;
        }

        attributes.add(type);
        attributes.add(collectionType);

        if (collection.owner.id == user.id && collection.sharees.length) {
            attributes.add("shared");
            attributes.add("sharedOutgoing");
        }
        if (collection.publicURLs.length) {
            attributes.add("shared");
            attributes.add("sharedViaLink");
            // "sharedOnlyViaLink" stays reserved for the case where the only
            // way the collection is shared is via a public link (no sharees),
            // which decides the primary icon. "sharedViaLink" instead tracks
            // the mere presence of a link, so an album that is shared with
            // people and also has a link still shows the link indicator.
            if (!collection.sharees.length) {
                attributes.add("sharedOnlyViaLink");
            }
        }
        if (isArchivedCollection(collection)) {
            attributes.add("archived");
        }
        if (collection.magicMetadata?.data.order == CollectionOrder.pinned) {
            attributes.add("pinned");
            sortPriority = CollectionSummarySortPriority.pinned;
        }
        // Check for sharee pinned (for incoming shared collections)
        if (
            type == "sharedIncoming" &&
            collection.sharedMagicMetadata?.data.order == CollectionOrder.pinned
        ) {
            attributes.add("shareePinned");
            sortPriority = CollectionSummarySortPriority.pinned;
        }

        if (type == "sharedIncoming" && collectionType == "favorites") {
            // See: [Note: User and shared favorites] above.
            //
            // Use the first letter of the email of the user who shared this
            // particular favorite as a prefix to disambiguate this collection
            // from the user's own favorites.
            // TODO: Use the person name when avail
            const initial = collection.owner.email?.at(0)?.toUpperCase();
            if (initial) {
                name = t("person_favorites", { name: initial });
            } else {
                name = t("shared_favorites");
            }
        }

        const collectionFiles = filesByCollection.get(collection.id);

        // Hide empty favorites from collection bar
        if (type == "userFavorites" && !collectionFiles?.length) {
            attributes.add("hideFromCollectionBar");
        }

        collectionSummaries.set(collection.id, {
            id: collection.id,
            type,
            attributes,
            name,
            latestFile: collectionFiles?.[0],
            coverFile: coverFiles.get(collection.id),
            fileCount: collectionFiles?.length ?? 0,
            updationTime: collection.updationTime,
            sortPriority,
        });
    }

    return collectionSummaries;
};

const findCoverFiles = (
    collections: Collection[],
    filesByCollection: Map<number, EnteFile[]>,
): Map<number, EnteFile> => {
    const coverFiles = new Map<number, EnteFile>();
    for (const collection of collections) {
        const collectionFiles = filesByCollection.get(collection.id);
        if (!collectionFiles || collectionFiles.length == 0) continue;

        let coverFile: EnteFile | undefined;

        // eslint-disable-next-line @typescript-eslint/no-unnecessary-condition
        const coverID = collection.pubMagicMetadata?.data?.coverID;
        if (typeof coverID == "number" && coverID > 0) {
            coverFile = collectionFiles.find(({ id }) => id === coverID);
        }

        if (!coverFile) {
            // eslint-disable-next-line @typescript-eslint/no-unnecessary-condition
            if (collection.pubMagicMetadata?.data?.asc) {
                coverFile = collectionFiles[collectionFiles.length - 1];
            } else {
                coverFile = collectionFiles[0];
            }
        }

        if (coverFile) {
            coverFiles.set(collection.id, coverFile);
        }
    }
    return coverFiles;
};

/**
 * Compute the {@link GalleryView} from its dependencies when we are switching
 * to (or back to) the "albums" view, or the underlying collections might've
 * changed.
 */
const deriveAlbumsViewAndSelectedID = (
    collections: GalleryState["collections"],
    hiddenCollectionIDs: GalleryState["hiddenCollectionIDs"],
    collectionSummaries: GalleryState["normalCollectionSummaries"],
    selectedCollectionSummaryID: GalleryState["selectedCollectionSummaryID"],
) => {
    // Make sure that the last selected ID is still valid by searching for it.
    const candidateCollectionSummary = selectedCollectionSummaryID
        ? collectionSummaries.get(selectedCollectionSummaryID)
        : undefined;
    const selectedCollectionSummary =
        candidateCollectionSummary &&
        !candidateCollectionSummary.attributes.has("archiveItems") &&
        !candidateCollectionSummary.attributes.has("archived")
            ? candidateCollectionSummary
            : undefined;

    const activeCollectionSummaryID =
        selectedCollectionSummary?.id ?? PseudoCollectionID.all;
    const activeCollectionSummary = collectionSummaries.get(
        activeCollectionSummaryID,
    )!;
    const activeCollection =
        selectedCollectionSummary &&
        !hiddenCollectionIDs.has(activeCollectionSummaryID)
            ? collections.find(({ id }) => id == activeCollectionSummaryID)
            : undefined;
    return {
        selectedCollectionSummaryID: activeCollectionSummaryID,
        view: {
            type: "albums" as const,
            activeCollectionSummaryID,
            activeCollection,
            activeCollectionSummary,
        },
    };
};

/**
 * Sibling of {@link deriveAlbumsViewAndSelectedID} for when we're in the hidden
 * albums section.
 */
const deriveHiddenAlbumsViewAndSelectedID = (
    collections: GalleryState["collections"],
    hiddenCollectionIDs: GalleryState["hiddenCollectionIDs"],
    hiddenCollectionSummaries: GalleryState["hiddenCollectionSummaries"],
    selectedCollectionSummaryID: GalleryState["selectedCollectionSummaryID"],
) => {
    // Make sure that the last selected ID is still valid by searching for it.
    const selectedCollectionSummary = selectedCollectionSummaryID
        ? hiddenCollectionSummaries.get(selectedCollectionSummaryID)
        : undefined;

    const activeCollectionSummaryID =
        selectedCollectionSummary?.id ?? PseudoCollectionID.hiddenItems;
    const activeCollectionSummary = hiddenCollectionSummaries.get(
        activeCollectionSummaryID,
    )!;
    const activeCollection =
        selectedCollectionSummary &&
        hiddenCollectionIDs.has(activeCollectionSummaryID)
            ? collections.find(({ id }) => id == activeCollectionSummaryID)
            : undefined;
    return {
        selectedCollectionSummaryID: activeCollectionSummaryID,
        view: {
            type: "hidden-albums" as const,
            activeCollectionSummaryID,
            activeCollection,
            activeCollectionSummary,
        },
    };
};

/**
 * Sibling of {@link deriveAlbumsViewAndSelectedID} for when we're in the
 * archive albums section.
 */
const deriveArchiveAlbumsViewAndSelectedID = (
    collections: GalleryState["collections"],
    archivedCollectionSummaries: GalleryState["archivedCollectionSummaries"],
    selectedCollectionSummaryID: GalleryState["selectedCollectionSummaryID"],
) => {
    // Make sure that the last selected ID is still valid by searching for it.
    const selectedCollectionSummary = selectedCollectionSummaryID
        ? archivedCollectionSummaries.get(selectedCollectionSummaryID)
        : undefined;

    const activeCollectionSummaryID =
        selectedCollectionSummary?.id ?? PseudoCollectionID.archiveItems;
    const activeCollectionSummary = archivedCollectionSummaries.get(
        activeCollectionSummaryID,
    )!;
    const activeCollection =
        selectedCollectionSummary &&
        activeCollectionSummaryID != PseudoCollectionID.archiveItems
            ? collections.find(({ id }) => id == activeCollectionSummaryID)
            : undefined;
    return {
        selectedCollectionSummaryID: activeCollectionSummaryID,
        view: {
            type: "archive-albums" as const,
            activeCollectionSummaryID,
            activeCollection,
            activeCollectionSummary,
        },
    };
};

/**
 * Compute the {@link GalleryView} from its dependencies when we are switching
 * to (or back to) the "people" view.
 */
const derivePeopleView = (
    peopleState: GalleryState["peopleState"],
    tempDeletedFileIDs: GalleryState["tempDeletedFileIDs"],
    tempHiddenFileIDs: GalleryState["tempHiddenFileIDs"],
    selectedPersonID: GalleryState["selectedPersonID"],
    extraVisiblePerson: GalleryState["extraVisiblePerson"],
): {
    view: Extract<GalleryView, { type: "people" }>;
    extraVisiblePerson: GalleryState["extraVisiblePerson"];
} => {
    let people = peopleState?.people ?? [];
    let visiblePeople = peopleState?.visiblePeople ?? [];
    if (tempDeletedFileIDs.size + tempHiddenFileIDs.size > 0) {
        // Prune the in-memory temp updates from the actual state to
        // obtain the UI state. Kept inside an preflight check to so
        // that the common path remains fast.
        const filterTemp = (ps: Person[]) =>
            ps
                .map((p) => ({
                    ...p,
                    fileIDs: p.fileIDs.filter(
                        (id) =>
                            !tempDeletedFileIDs.has(id) &&
                            !tempHiddenFileIDs.has(id),
                    ),
                }))
                .filter((p) => p.fileIDs.length > 0);
        people = filterTemp(people);
        visiblePeople = filterTemp(visiblePeople);
    }

    // We might have an extraVisiblePerson that is now part of the visible ones
    // when the user un-ignores a person. If that's the case (which we can
    // detect by its absence from the list of underlying people, since its ID
    // would've changed), clear it out, otherwise we'll end up with two entries.
    if (extraVisiblePerson) {
        if (!people.find((p) => p.id == extraVisiblePerson?.id))
            extraVisiblePerson = undefined;
    }

    const findByIDIn = (ps: Person[]) =>
        ps.find((p) => p.id == selectedPersonID);
    let activePerson = findByIDIn(visiblePeople);
    if (!activePerson) {
        // This might be one of the normally hidden small clusters.
        activePerson = findByIDIn(people);
        if (activePerson) {
            // Temporarily add this person's entry to the list of people
            // surfaced in the people view.
            extraVisiblePerson = activePerson;
        } else {
            // We don't have an "All" pseudo-album in people view, so default to
            // the first person in the list (if any).
            activePerson = visiblePeople[0];
        }
    }

    const view = {
        type: "people" as const,
        people,
        visiblePeople: extraVisiblePerson
            ? visiblePeople.concat([extraVisiblePerson])
            : visiblePeople,
        activePerson,
    };

    return { view, extraVisiblePerson };
};

/**
 * Return a new state from the given {@link state} by recomputing all properties
 * that depend on collection files, using the provided {@link collectionFiles}.
 *
 * Usually, we update state by manually dependency tracking on a fine grained
 * basis, but it results in a duplicate code when the files themselves change,
 * since they effect many things.
 *
 * So this is a convenience function for updating everything that needs to
 * change when the collections files themselves change.
 */
const stateForUpdatedCollectionFiles = (
    state: GalleryState,
    collectionFiles: GalleryState["collectionFiles"],
): GalleryState => {
    const normalCollections = state.collections.filter(
        (c) => !state.hiddenCollectionIDs.has(c.id),
    );
    const hiddenCollections = state.collections.filter((c) =>
        state.hiddenCollectionIDs.has(c.id),
    );
    const hiddenFileIDs = deriveHiddenFileIDs(
        collectionFiles,
        state.hiddenCollectionIDs,
    );
    const archivedFileIDs = deriveArchivedFileIDs(
        state.archivedCollectionIDs,
        collectionFiles,
    );

    return {
        ...state,
        collectionFiles,
        hiddenFileIDs,
        archivedFileIDs,
        favoriteFileIDs: deriveFavoriteFileIDs(
            state.user!,
            state.collections,
            collectionFiles,
            state.unsyncedFavoriteUpdates,
        ),
        fileNormalCollectionIDs: deriveFileNormalCollectionIDs(
            collectionFiles,
            state.hiddenCollectionIDs,
        ),
        normalCollectionSummaries: deriveNormalCollectionSummaries(
            normalCollections,
            state.user!,
            state.trashItems,
            collectionFiles,
            hiddenFileIDs,
            archivedFileIDs,
        ),
        hiddenCollectionSummaries: deriveHiddenCollectionSummaries(
            hiddenCollections,
            state.user!,
            collectionFiles,
        ),
        archivedCollectionSummaries: deriveArchivedCollectionSummaries(
            normalCollections,
            state.user!,
            collectionFiles,
            hiddenFileIDs,
        ),
        pendingSearchSuggestions: enqueuePendingSearchSuggestionsIfNeeded(
            state.searchSuggestion,
            state.pendingSearchSuggestions,
            state.isInSearchMode,
        ),
    };
};

/**
 * Return a new state by recomputing the {@link filteredFiles} property
 * depending on which view we are showing
 *
 * Usually, we update state by manually dependency tracking on a fine grained
 * basis, but it is cumbersome (and mistake prone) to do that for the list of
 * filtered files which depend on a many things.
 *
 * So this is a convenience function for recomputing filtered files whenever any
 * bit of the underlying state that could affect the list of files changes.
 */
const stateByUpdatingFilteredFiles = (state: GalleryState) => {
    if (state.isInSearchMode) {
        const searchFiles = state.searchResults ?? state.filteredFiles;
        /**
         * the suppressSharedFilesSavedByUser is a utlity function added in during the
         * UploadToSharedAlbum feature implementation.
         *
         * This particular function actually filters out any files which are actually
         * owned by someone else for which the currentUser has a copy.
         */
        const visibleSearchFiles = suppressSharedFilesSavedByUser(
            searchFiles,
            state.user?.id,
            state.view?.type == "albums" ||
                state.view?.type == "hidden-albums" ||
                state.view?.type == "archive-albums"
                ? state.view.activeCollection
                : undefined,
        );
        // Only apply time-based sorting if user explicitly selected a sort order.
        // When undefined, keep original order (preserves CLIP relevance sorting).
        const filteredFiles =
            state.searchSortAsc !== undefined
                ? sortFiles([...visibleSearchFiles], state.searchSortAsc)
                : visibleSearchFiles;
        return { ...state, filteredFiles };
    } else if (
        state.view?.type == "albums" ||
        state.view?.type == "hidden-albums" ||
        state.view?.type == "archive-albums"
    ) {
        const filteredFiles = deriveAlbumsOrHiddenAlbumsFilteredFiles(
            state.trashItems,
            state.collectionFiles,
            state.defaultHiddenCollectionIDs,
            state.hiddenFileIDs,
            state.archivedCollectionIDs,
            state.archivedFileIDs,
            state.tempDeletedFileIDs,
            state.tempHiddenFileIDs,
            state.view,
            state.user?.id,
        );
        return { ...state, filteredFiles };
    } else if (state.view?.type == "people") {
        const filteredFiles = derivePeopleFilteredFiles(
            state.collectionFiles,
            state.hiddenFileIDs,
            state.view,
            state.user?.id,
        );
        return { ...state, filteredFiles };
    } else {
        return state;
    }
};

/**
 * Compute the sorted list of files to show when we're in the "albums" or
 * "hidden-albums", or "archive-albums" view and the dependencies change.
 */
const deriveAlbumsOrHiddenAlbumsFilteredFiles = (
    trashItems: GalleryState["trashItems"],
    collectionFiles: GalleryState["collectionFiles"],
    defaultHiddenCollectionIDs: GalleryState["defaultHiddenCollectionIDs"],
    hiddenFileIDs: GalleryState["hiddenFileIDs"],
    archivedCollectionIDs: GalleryState["archivedCollectionIDs"],
    archivedFileIDs: GalleryState["archivedFileIDs"],
    tempDeletedFileIDs: GalleryState["tempDeletedFileIDs"],
    tempHiddenFileIDs: GalleryState["tempHiddenFileIDs"],
    view: Extract<
        GalleryView,
        { type: "albums" | "hidden-albums" | "archive-albums" }
    >,
    currentUserID: number | undefined,
) => {
    const activeCollectionSummaryID = view.activeCollectionSummaryID;

    // Trash is dealt with separately.
    //
    // [Note: Files in trash pseudo collection have deleteBy]
    //
    // When showing the trash pseudo collection, each file in the files array is
    // in fact an instance of `EnteTrashFile` - it has an additional (and
    // optional) `deleteBy` property. The types don't reflect this.

    if (activeCollectionSummaryID == PseudoCollectionID.trash) {
        return uniqueFilesByID([
            ...trashItems.map(({ file, deleteBy }) => ({ ...file, deleteBy })),
            ...collectionFiles.filter((file) =>
                tempDeletedFileIDs.has(file.id),
            ),
        ]);
    }

    const filteredFiles = collectionFiles.filter((file) => {
        if (tempDeletedFileIDs.has(file.id)) return false;

        // "Hidden items" shows all individually hidden files.
        if (
            activeCollectionSummaryID == PseudoCollectionID.hiddenItems &&
            defaultHiddenCollectionIDs.has(file.collectionID)
        ) {
            return true;
        }

        // Archived files can only be seen in the archive items, or in their
        // respective collection. Hidden files should be excluded in from
        // archive items (but not from their album).
        //
        // Note that a file may both be archived, AND be part of an archived
        // collection. Such files should be shown in both the archive section
        // and in their respective collection. Thus this (archived file) case
        // needs to be before the following (archived collection) case.
        if (isArchivedFile(file)) {
            return (
                (activeCollectionSummaryID == PseudoCollectionID.archiveItems &&
                    !hiddenFileIDs.has(file.id) &&
                    !tempHiddenFileIDs.has(file.id)) ||
                activeCollectionSummaryID == file.collectionID
            );
        }

        // Files in archived collections can only be seen in their respective
        // collection.
        if (archivedCollectionIDs.has(file.collectionID)) {
            return activeCollectionSummaryID === file.collectionID;
        }

        if (activeCollectionSummaryID === PseudoCollectionID.all) {
            // Hidden files should not be shown in "All".
            if (hiddenFileIDs.has(file.id)) return false;
            if (tempHiddenFileIDs.has(file.id)) return false;

            // Archived files (whether individually archived, or part of some
            // archived album) should not be shown in "All".
            if (archivedFileIDs.has(file.id)) {
                return false;
            }

            // Show all remaining (non-hidden, non-archived) files in "All".
            return true;
        }

        // Show files that belong to the active collection.
        return activeCollectionSummaryID == file.collectionID;
    });

    return sortAndUniqueFilteredFiles(
        filteredFiles,
        view.activeCollection,
        currentUserID,
    );
};

/**
 * Prepare the list of files for being shown in the gallery.
 *
 * This functions uniques the given collection files so that there is only one
 * entry per file ID. Then it sorts them if the active collection prefers them
 * to be sorted oldest first (by default, lists of collection files are sorted
 * newest first, and we assume that {@link files} are already sorted that way).
 */
const sortAndUniqueFilteredFiles = (
    files: EnteFile[],
    activeCollection: Collection | undefined,
    currentUserID: number | undefined,
) => {
    const uniqueFiles = uniqueFilesByID(
        suppressSharedFilesSavedByUser(files, currentUserID, activeCollection),
    );
    const sortAsc = activeCollection?.pubMagicMetadata?.data.asc ?? false;
    return sortAsc ? sortFiles(uniqueFiles, true) : uniqueFiles;
};

const suppressSharedFilesSavedByUser = (
    files: EnteFile[],
    currentUserID: number | undefined,
    activeCollection: Collection | undefined,
) => {
    // If there is no logged-in user, or if we are inside an active album
    // (this suppression is only needed in non-album views), return the
    // files unchanged.
    if (!currentUserID || activeCollection) return files;

    // Collect the hash+type keys for files owned by the current user.
    const ownedFileKeys = new Set<string>();
    for (const file of files) {
        if (file.ownerID != currentUserID) continue;
        const hash = metadataHash(file.metadata);
        if (!hash) continue;
        ownedFileKeys.add(`${hash}:${file.metadata.fileType}`);
    }

    if (!ownedFileKeys.size) return files;

    return files.filter((file) => {
        // Always keep files owned by the current user.
        if (file.ownerID == currentUserID) return true;

        // Keep files whose metadata does not yield a hash.
        const hash = metadataHash(file.metadata);
        if (!hash) return true;

        // Drop a non-owned file if the user already owns a file with the same
        // hash+type key.
        return !ownedFileKeys.has(`${hash}:${file.metadata.fileType}`);
    });
};

/**
 * Compute the sorted list of files to show when we're in the "people" view and
 * the dependencies change.
 */
const derivePeopleFilteredFiles = (
    collectionFiles: GalleryState["collectionFiles"],
    hiddenFileIDs: GalleryState["hiddenFileIDs"],
    view: Extract<GalleryView, { type: "people" }>,
    currentUserID: number | undefined,
) => {
    const pfSet = new Set(view.activePerson?.fileIDs ?? []);
    return uniqueFilesByID(
        suppressSharedFilesSavedByUser(
            collectionFiles.filter((f) => {
                if (!pfSet.has(f.id)) return false;
                if (hiddenFileIDs.has(f.id)) return false;
                return true;
            }),
            currentUserID,
            undefined,
        ),
    );
};

/**
 * Trigger a recomputation of search results if needed.
 *
 * This convenience helper is used on updates to some state (collections, files)
 * that is used to derive the base set of files on which the search are
 * performed. It re-enqueues the current search suggestion as pending, which'll
 * trigger a recomputation of the state's {@link searchResults}.
 */
const enqueuePendingSearchSuggestionsIfNeeded = (
    searchSuggestion: GalleryState["searchSuggestion"],
    pendingSearchSuggestions: GalleryState["pendingSearchSuggestions"],
    isInSearchMode: GalleryState["isInSearchMode"],
) =>
    searchSuggestion && isInSearchMode
        ? [...pendingSearchSuggestions, searchSuggestion]
        : pendingSearchSuggestions;

/**
 * Create a map from the user IDs to their emails, with entries for all Ente
 * users who have shared a collection with the user.
 */
const constructUserIDToEmailMap = (
    user: LocalUser,
    collections: GalleryState["collections"],
): Map<number, string> => {
    const userIDToEmail = new Map<number, string>();
    for (const { owner, sharees } of collections) {
        if (user.id != owner.id && owner.email) {
            userIDToEmail.set(owner.id, owner.email);
        }
        for (const sharee of sharees) {
            if (sharee.id != user.id && sharee.email) {
                userIDToEmail.set(sharee.id, sharee.email);
            }
        }
    }
    return userIDToEmail;
};

/**
 * Create a list of emails that are shown as suggestions to the user when they
 * are trying to share albums with specific users.
 */
const createShareSuggestionEmails = (
    user: LocalUser,
    familyData: FamilyData | undefined,
    collections: Collection[],
): string[] => [
    ...new Set(
        collections
            .map(({ owner, sharees }) =>
                owner.email && owner.id != user.id
                    ? [owner.email]
                    : sharees.map(({ email }) => email),
            )
            .flat()
            .filter((e) => e !== undefined)
            .concat((familyData?.members ?? []).map((member) => member.email))
            .filter((email) => email != user.email),
    ),
];
