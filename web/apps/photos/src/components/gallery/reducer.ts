import type { LocalUser } from "ente-accounts/services/user";
import {
    groupFilesByCollectionID,
    sortFiles,
    uniqueFilesByID,
} from "ente-gallery/utils/file";
import {
    CollectionOrder,
    CollectionSubType,
    collectionTypes,
    findUserUncategorizedCollection,
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
    findDefaultHiddenCollectionIDs,
    isArchivedCollection,
    isDefaultHiddenCollection,
    isHiddenCollection,
} from "ente-new/photos/services/collection";
import {
    CollectionSummarySortPriority,
    PseudoCollectionID,
    type CollectionSummary,
    type CollectionSummaryAttribute,
    type CollectionSummaryType,
} from "ente-new/photos/services/collection-summary";
import type { PeopleState, Person } from "ente-new/photos/services/ml/people";
import type { SearchSuggestion } from "ente-new/photos/services/search/types";
import { sortTrashItems, type TrashItem } from "ente-new/photos/services/trash";
import type {
    FamilyData,
    UserDetails,
} from "ente-new/photos/services/user-details";
import { splitByPredicate } from "ente-utils/array";
import { includes } from "ente-utils/type-guards";
import { t } from "i18next";
import React, { useReducer } from "react";

// TODO: Deprecated(?). Use GalleryView instead. Deprecated if it can be used in
// all cases where the bar mode was in use.
export type GalleryBarMode =
    | "albums"
    | "hidden-albums"
    | "archive-albums"
    | "people";

type GalleryView =
    | {
          type: "albums" | "hidden-albums" | "archive-albums";
          activeCollectionSummaryID: number;
          activeCollection: Collection | undefined;
          activeCollectionSummary: CollectionSummary;
      }
    | {
          type: "people";
          visiblePeople: Person[];
          people: Person[];
          activePerson: Person | undefined;
      };

interface GalleryState {
    user: LocalUser | undefined;
    familyData: FamilyData | undefined;

    collections: Collection[];
    lastSyncedCollectionFiles: EnteFile[];
    trashItems: TrashItem[];
    peopleState: PeopleState | undefined;

    // Includes local overlays until the next remote pull.
    collectionFiles: EnteFile[];
    hiddenCollectionIDs: Set<number>;
    // Concurrent clients can create more than one default-hidden collection.
    defaultHiddenCollectionIDs: Set<number>;
    hiddenFileIDs: Set<number>;
    archivedCollectionIDs: Set<number>;
    archivedFileIDs: Set<number>;
    favoriteFileIDs: Set<number>;
    collectionNameByID: Map<number, string>;
    fileNormalCollectionIDs: Map<number, number[]>;
    emailByUserID: Map<number, string>;
    shareSuggestionEmails: string[];

    normalCollectionSummaries: Map<number, CollectionSummary>;
    hiddenCollectionSummaries: Map<number, CollectionSummary>;
    archivedCollectionSummaries: Map<number, CollectionSummary>;
    uncategorizedCollectionSummaryID: number;

    tempDeletedFileIDs: Set<number>;
    tempHiddenFileIDs: Set<number>;
    pendingFavoriteUpdates: Set<number>;
    // Shared copies use hash/type keys; owned files use IDs.
    unsyncedFavoriteUpdates: Map<
        UnsyncedFavoriteUpdateKey,
        UnsyncedFavoriteUpdate
    >;
    pendingVisibilityUpdates: Set<number>;
    unsyncedPrivateMagicMetadataUpdates: Map<
        number,
        MagicMetadata<FilePrivateMagicMetadataData>
    >;

    selectedCollectionSummaryID: number | undefined;
    selectedPersonID: string | undefined;
    extraVisiblePerson: Person | undefined;
    searchSuggestion: SearchSuggestion | undefined;
    searchResults: EnteFile[] | undefined;
    isRecomputingSearchResults: boolean;
    pendingSearchSuggestions: SearchSuggestion[];

    view: GalleryView | undefined;
    isInSearchMode: boolean;
    // Undefined preserves relevance order; booleans request time sorting.
    searchSortAsc: boolean | undefined;
    filteredFiles: EnteFile[];
}

type GalleryAction =
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
                    deriveUncategorizedCollectionSummaryID(
                        normalCollections,
                        user.id,
                    ),
                view,
            });
        }

        case "setUserDetails": {
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
                    deriveUncategorizedCollectionSummaryID(
                        normalCollections,
                        state.user!.id,
                    ),
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
            const collectionFiles = state.lastSyncedCollectionFiles;

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
            if (!state.isRecomputingSearchResults) return state;

            return stateByUpdatingFilteredFiles({
                ...state,
                searchResults: action.searchResults,
                isRecomputingSearchResults: false,
            });

        case "exitSearch": {
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

const deriveCollectionFiles = (
    lastSyncedCollectionFiles: GalleryState["lastSyncedCollectionFiles"],
    unsyncedPrivateMagicMetadataUpdates: GalleryState["unsyncedPrivateMagicMetadataUpdates"],
) => {
    if (unsyncedPrivateMagicMetadataUpdates.size == 0)
        return lastSyncedCollectionFiles;

    return lastSyncedCollectionFiles.map((file) => {
        const privateMagicMetadata = unsyncedPrivateMagicMetadataUpdates.get(
            file.id,
        );
        if (!privateMagicMetadata) return file;

        return { ...file, magicMetadata: privateMagicMetadata };
    });
};

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

const deriveHiddenFileIDs = (
    collectionFiles: GalleryState["collectionFiles"],
    hiddenCollectionIDs: GalleryState["hiddenCollectionIDs"],
) =>
    new Set(
        collectionFiles
            .filter((f) => hiddenCollectionIDs.has(f.collectionID))
            .map((f) => f.id),
    );

const deriveDefaultHiddenCollectionIDs = (hiddenCollections: Collection[]) =>
    findDefaultHiddenCollectionIDs(hiddenCollections);

const deriveArchivedCollectionIDs = (collections: Collection[]) =>
    new Set<number>(
        collections
            .filter(isArchivedCollection)
            .map((collection) => collection.id),
    );

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

const favoriteUpdateFileIDs = (
    user: LocalUser,
    collectionFiles: GalleryState["collectionFiles"],
    update: UnsyncedFavoriteUpdate,
) =>
    update.fileHashAndTypeKey
        ? collectionFiles
              .filter(
                  (file) =>
                      file.ownerID != user.id &&
                      favoriteFileHashAndTypeKey(file) ==
                          update.fileHashAndTypeKey,
              )
              .map((file) => file.id)
        : [update.fileID];

const deriveFavoriteFileIDs = (
    user: LocalUser,
    collections: GalleryState["collections"],
    collectionFiles: GalleryState["collectionFiles"],
    unsyncedFavoriteUpdates: GalleryState["unsyncedFavoriteUpdates"],
) => {
    let favoriteFileIDs = new Set<number>();
    let favoriteFileHashAndTypeKeys = new Set<string>();

    for (const collection of collections) {
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
    // Shared copies have different IDs from their owned favorite.
    for (const file of collectionFiles) {
        if (file.ownerID == user.id) continue;

        const key = favoriteFileHashAndTypeKey(file);
        if (key && favoriteFileHashAndTypeKeys.has(key)) {
            favoriteFileIDs.add(file.id);
        }
    }

    for (const update of unsyncedFavoriteUpdates.values()) {
        const updatedFileIDs = favoriteUpdateFileIDs(
            user,
            collectionFiles,
            update,
        );
        for (const fileID of updatedFileIDs) {
            if (update.isFavorite) favoriteFileIDs.add(fileID);
            else favoriteFileIDs.delete(fileID);
        }
    }
    return favoriteFileIDs;
};
const preserveUnreflectedFavoriteUpdates = (
    user: LocalUser,
    collectionFiles: GalleryState["collectionFiles"],
    syncedFavoriteFileIDs: GalleryState["favoriteFileIDs"],
    unsyncedFavoriteUpdates: GalleryState["unsyncedFavoriteUpdates"],
) => {
    const preservedUpdates: GalleryState["unsyncedFavoriteUpdates"] = new Map();

    // Keep an overlay until a pull reports the same state for every copy.
    for (const [key, update] of unsyncedFavoriteUpdates.entries()) {
        const updatedFileIDs = favoriteUpdateFileIDs(
            user,
            collectionFiles,
            update,
        );

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

const deriveFileNormalCollectionIDs = (
    collectionFiles: GalleryState["collectionFiles"],
    hiddenCollectionIDs: GalleryState["hiddenCollectionIDs"],
) =>
    createFileCollectionIDs(
        collectionFiles.filter((f) => !hiddenCollectionIDs.has(f.collectionID)),
    );

const createFileCollectionIDs = (files: EnteFile[]) =>
    files.reduce((result, file) => {
        const id = file.id;
        let fs = result.get(id);
        if (!fs) result.set(id, (fs = []));
        fs.push(file.collectionID);
        return result;
    }, new Map<number, number[]>());

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

    const uncategorizedCollection = findUserUncategorizedCollection(
        normalCollections,
        user.id,
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

const deriveUncategorizedCollectionSummaryID = (
    normalCollections: Collection[],
    userID: number,
) =>
    findUserUncategorizedCollection(normalCollections, userID)?.id ??
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

        // Ownership comes first so shared favorites remain sharedIncoming.
        if (collection.owner.id != user.id) {
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

        if (
            collection.magicMetadata?.data.subType ==
                CollectionSubType.quicklink &&
            !collection.sharees.length
        ) {
            attributes.add("quickLink");
        }

        if (collection.owner.id == user.id && collection.sharees.length) {
            attributes.add("shared");
            attributes.add("sharedOutgoing");
        }
        if (collection.publicURLs.length) {
            attributes.add("shared");
            attributes.add("sharedViaLink");
            // This selects the primary icon; sharedViaLink only adds a badge.
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
        if (
            type == "sharedIncoming" &&
            collection.sharedMagicMetadata?.data.order == CollectionOrder.pinned
        ) {
            attributes.add("shareePinned");
            sortPriority = CollectionSummarySortPriority.pinned;
        }

        if (type == "sharedIncoming" && collectionType == "favorites") {
            // TODO: Use the person name when avail
            const initial = collection.owner.email?.at(0)?.toUpperCase();
            if (initial) {
                name = t("person_favorites", { name: initial });
            } else {
                name = t("shared_favorites");
            }
        }

        const collectionFiles = filesByCollection.get(collection.id);

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

const deriveAlbumsViewAndSelectedID = (
    collections: GalleryState["collections"],
    hiddenCollectionIDs: GalleryState["hiddenCollectionIDs"],
    collectionSummaries: GalleryState["normalCollectionSummaries"],
    selectedCollectionSummaryID: GalleryState["selectedCollectionSummaryID"],
) => {
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

const deriveHiddenAlbumsViewAndSelectedID = (
    collections: GalleryState["collections"],
    hiddenCollectionIDs: GalleryState["hiddenCollectionIDs"],
    hiddenCollectionSummaries: GalleryState["hiddenCollectionSummaries"],
    selectedCollectionSummaryID: GalleryState["selectedCollectionSummaryID"],
) => {
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

const deriveArchiveAlbumsViewAndSelectedID = (
    collections: GalleryState["collections"],
    archivedCollectionSummaries: GalleryState["archivedCollectionSummaries"],
    selectedCollectionSummaryID: GalleryState["selectedCollectionSummaryID"],
) => {
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

    // Keep a selected small cluster visible until the user leaves this view.
    if (extraVisiblePerson) {
        if (!people.find((p) => p.id == extraVisiblePerson?.id))
            extraVisiblePerson = undefined;
    }

    const findByIDIn = (ps: Person[]) =>
        ps.find((p) => p.id == selectedPersonID);
    let activePerson = findByIDIn(visiblePeople);
    if (!activePerson) {
        activePerson = findByIDIn(people);
        if (activePerson) {
            extraVisiblePerson = activePerson;
        } else {
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

const stateByUpdatingFilteredFiles = (state: GalleryState) => {
    if (state.isInSearchMode) {
        const searchFiles = state.searchResults ?? state.filteredFiles;
        const visibleSearchFiles = suppressSharedFilesSavedByUser(
            searchFiles,
            state.user?.id,
            state.view?.type == "albums" ||
                state.view?.type == "hidden-albums" ||
                state.view?.type == "archive-albums"
                ? state.view.activeCollection
                : undefined,
        );
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

        if (
            activeCollectionSummaryID == PseudoCollectionID.hiddenItems &&
            defaultHiddenCollectionIDs.has(file.collectionID)
        ) {
            return true;
        }

        // A file can be individually archived and belong to an archived album.
        if (isArchivedFile(file)) {
            return (
                (activeCollectionSummaryID == PseudoCollectionID.archiveItems &&
                    !hiddenFileIDs.has(file.id) &&
                    !tempHiddenFileIDs.has(file.id)) ||
                activeCollectionSummaryID == file.collectionID
            );
        }

        if (archivedCollectionIDs.has(file.collectionID)) {
            return activeCollectionSummaryID === file.collectionID;
        }

        if (activeCollectionSummaryID === PseudoCollectionID.all) {
            if (hiddenFileIDs.has(file.id)) return false;
            if (tempHiddenFileIDs.has(file.id)) return false;

            if (archivedFileIDs.has(file.id)) {
                return false;
            }

            return true;
        }

        return activeCollectionSummaryID == file.collectionID;
    });

    return sortAndUniqueFilteredFiles(
        filteredFiles,
        view.activeCollection,
        currentUserID,
    );
};

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
    if (!currentUserID || activeCollection) return files;

    const ownedFileKeys = new Set<string>();
    for (const file of files) {
        if (file.ownerID != currentUserID) continue;
        const hash = metadataHash(file.metadata);
        if (!hash) continue;
        ownedFileKeys.add(`${hash}:${file.metadata.fileType}`);
    }

    if (!ownedFileKeys.size) return files;

    return files.filter((file) => {
        if (file.ownerID == currentUserID) return true;

        const hash = metadataHash(file.metadata);
        if (!hash) return true;

        return !ownedFileKeys.has(`${hash}:${file.metadata.fileType}`);
    });
};

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

const enqueuePendingSearchSuggestionsIfNeeded = (
    searchSuggestion: GalleryState["searchSuggestion"],
    pendingSearchSuggestions: GalleryState["pendingSearchSuggestions"],
    isInSearchMode: GalleryState["isInSearchMode"],
) =>
    searchSuggestion && isInSearchMode
        ? [...pendingSearchSuggestions, searchSuggestion]
        : pendingSearchSuggestions;

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
