// TODO: Audit this file (the code here is mostly fine, but needs revisiting
// the file it depends on have been audited and their interfaces fixed).
/* eslint-disable react-hooks/exhaustive-deps */
/* eslint-disable @typescript-eslint/no-floating-promises */
import type { AddToAlbumPhase } from "@/components/AlbumAddedNotification";
import { AlbumAddedNotification } from "@/components/AlbumAddedNotification";
import { AuthenticateUser } from "@/components/AuthenticateUser";
import { GalleryBarAndListHeader } from "@/components/Collections/GalleryBarAndListHeader";
import { PickCoverPhotoDialog } from "@/components/Collections/PickCoverPhotoDialog";
import type { FileListHeaderOrFooter } from "@/components/FileList";
import { FileListWithViewer } from "@/components/FileListWithViewer";
import { FixCreationTime } from "@/components/FixCreationTime";
import { QuickLinkCreatedNotification } from "@/components/QuickLinkCreatedNotification";
import { Sidebar } from "@/components/Sidebar";
import { Upload } from "@/components/Upload";
import { Upload01Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import ArrowBackIcon from "@mui/icons-material/ArrowBack";
import CheckCircleIcon from "@mui/icons-material/CheckCircle";
import MenuIcon from "@mui/icons-material/Menu";
import { IconButton, Link, Stack, Typography } from "@mui/material";
import { sessionExpiredDialogAttributes } from "ente-accounts/components/utils/dialog";
import {
    getAndClearIsFirstLogin,
    getAndClearJustSignedUp,
} from "ente-accounts/services/accounts-db";
import { processPendingAlbumJoin } from "ente-accounts/services/join-album";
import { stashRedirect } from "ente-accounts/services/redirect";
import { isSessionInvalid } from "ente-accounts/services/session";
import { ensureLocalUser } from "ente-accounts/services/user";
import { isDesktop } from "ente-base/app";
import type { MiniDialogAttributes } from "ente-base/components/MiniDialog";
import { NavbarBase } from "ente-base/components/Navbar";
import { SingleInputDialog } from "ente-base/components/SingleInputDialog";
import { CenteredRow } from "ente-base/components/containers";
import { TranslucentLoadingOverlay } from "ente-base/components/loaders";
import type { ButtonishProps } from "ente-base/components/mui";
import { FocusVisibleButton } from "ente-base/components/mui/FocusVisibleButton";
import { errorDialogAttributes } from "ente-base/components/utils/dialog";
import { useIsSmallWidth } from "ente-base/components/utils/hooks";
import { useModalVisibility } from "ente-base/components/utils/modal";
import { useBaseContext } from "ente-base/context";
import { subscribeMainWindowFocus } from "ente-base/electron";
import { hasPendingAlbumToJoin } from "ente-base/join-album";
import log from "ente-base/log";
import {
    clearSessionStorage,
    haveMasterKeyInSession,
    masterKeyFromSession,
} from "ente-base/session";
import { savedAuthToken } from "ente-base/token";
import type { Location } from "ente-base/types";
import { ensureContactsReady } from "ente-contacts-web";
import { DownloadStatusNotifications } from "ente-gallery/components/DownloadStatusNotifications";
import { FullScreenDropZone } from "ente-gallery/components/FullScreenDropZone";
import type { UploadTypeSelectorIntent } from "ente-gallery/components/Upload";
import { useSaveGroups } from "ente-gallery/components/utils/save-groups";
import type { FileViewerInitialSidebar } from "ente-gallery/components/viewer/FileViewer";
import { CollectionSubType, type Collection } from "ente-media/collection";
import type { EnteFile } from "ente-media/file";
import { ItemVisibility, metadataHash } from "ente-media/file-metadata";
import { AssignPersonDialog } from "ente-new/photos/components/AssignPersonDialog";
import {
    CollectionSelector,
    type CollectionSelectorAttributes,
} from "ente-new/photos/components/CollectionSelector";
import { EditLocationDialog } from "ente-new/photos/components/EditLocationDialog";
import { Export } from "ente-new/photos/components/Export";
import { PlanSelector } from "ente-new/photos/components/PlanSelector";
import {
    SearchBar,
    type SearchBarProps,
} from "ente-new/photos/components/SearchBar";
import {
    SelectedFileOptions,
    type CollectionOp,
    type FileOp,
} from "ente-new/photos/components/SelectedFileOptions";
import { WhatsNew } from "ente-new/photos/components/WhatsNew";
import {
    GalleryEmptyState,
    GalleryEmptyStateV2,
    PeopleEmptyState,
    SearchResultsHeader,
    type RemotePullOpts,
} from "ente-new/photos/components/gallery";
import {
    findCollectionCreatingUncategorizedIfNeeded,
    performCollectionOp,
    validateKey,
} from "ente-new/photos/components/gallery/helpers";
import {
    useGalleryReducer,
    type GalleryBarMode,
} from "ente-new/photos/components/gallery/reducer";
import {
    notifyOthersFilesDialogAttributes,
    notifyUnsupportedSharedFavoritesDialogAttributes,
} from "ente-new/photos/components/utils/dialog-attributes";
import { useIsOffline } from "ente-new/photos/components/utils/use-is-offline";
import {
    usePeopleStateSnapshot,
    useSettingsSnapshot,
    useUserDetailsSnapshot,
} from "ente-new/photos/components/utils/use-snapshot";
import { reauthenticateWithAppLock } from "ente-new/photos/services/app-lock";
import { shouldShowWhatsNew } from "ente-new/photos/services/changelog";
import {
    addToCollection,
    addToFavoritesCollection,
    canAddFilesToCollection,
    createAlbum,
    createPublicURL,
    createQuickLinkCollection,
    removeFromCollection,
    removeFromFavoritesCollection,
    updateCollectionCover,
} from "ente-new/photos/services/collection";
import {
    haveOnlySystemCollections,
    PseudoCollectionID,
} from "ente-new/photos/services/collection-summary";
import exportService from "ente-new/photos/services/export";
import {
    updateFilesLocation,
    updateFilesVisibility,
} from "ente-new/photos/services/file";
import {
    addManualFileAssignmentsToPerson,
    isMLEnabled,
} from "ente-new/photos/services/ml";

import { uploadManager } from "@/services/upload-manager";
import watcher from "@/services/watch";
import {
    getSelectedFiles,
    performFileOp,
    type SelectedState,
} from "@/utils/file";
import {
    quickLinkNameForFiles,
    resolveQuickLinkURL,
} from "ente-gallery/utils/quick-link";
import {
    savedCollectionFiles,
    savedCollections,
    savedTrashItems,
} from "ente-new/photos/services/photos-fdb";
import {
    postPullFiles,
    prePullFiles,
    pullFiles,
} from "ente-new/photos/services/pull";
import {
    filterSearchableFiles,
    updateSearchCollectionsAndFiles,
} from "ente-new/photos/services/search";
import type {
    SearchOption,
    SidebarActionID,
} from "ente-new/photos/services/search/types";
import { initSettings } from "ente-new/photos/services/settings";
import {
    redirectToCustomerPortal,
    savedUserDetailsOrTriggerPull,
    verifyStripeSubscription,
} from "ente-new/photos/services/user-details";
import { usePhotosAppContext } from "ente-new/photos/types/context";
import type { FileContextAction } from "ente-new/photos/utils/file-actions";
import { PromiseQueue } from "ente-utils/promise";
import { t } from "i18next";
import { useRouter, type NextRouter } from "next/router";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import type { FileWithPath } from "react-dropzone";
import { Trans } from "react-i18next";

/**
 * The default view for logged in users.
 *
 * I heard you like ASCII art.
 *
 *        Navbar / Search         ^
 *     ---------------------      |
 *          Gallery Bar         sticky
 *     ---------------------   ---/---
 *       Photo List Header    scrollable
 *     ---------------------      |
 *           Photo List           v
 */
const Page: React.FC = () => {
    const { logout, showMiniDialog, onGenericError } = useBaseContext();
    const {
        showLoadingBar,
        hideLoadingBar,
        watchFolderView,
        showNotification,
    } = usePhotosAppContext();

    const isOffline = useIsOffline();
    const [state, dispatch] = useGalleryReducer();

    const [isFirstLoad, setIsFirstLoad] = useState(false);
    const [isContextMenuOpen, setIsContextMenuOpen] = useState(false);
    const [suppressContextSelectionBar, setSuppressContextSelectionBar] =
        useState(false);
    const [selected, setSelected] = useState<SelectedState>({
        ownCount: 0,
        count: 0,
        collectionID: 0,
        context: { mode: "albums", collectionID: PseudoCollectionID.all },
    });
    const [blockingLoad, setBlockingLoad] = useState(false);
    const [shouldDisableDropzone, setShouldDisableDropzone] = useState(false);
    const [dragAndDropFiles, setDragAndDropFiles] = useState<FileWithPath[]>(
        [],
    );
    const [isFileViewerOpen, setIsFileViewerOpen] = useState(false);

    // Pending navigation from feed item click
    const [pendingFileNavigation, setPendingFileNavigation] = useState<{
        fileIndex: number;
        sidebar?: FileViewerInitialSidebar;
        commentID?: string;
    }>();

    /**
     * Tracks a pending file addition operation.
     *
     * Used to temporarily store the file and optional source collection ID
     * when adding a single file to a collection, allowing the operation
     * to be completed after any necessary user interactions (like selecting
     * a target collection).
     */
    const pendingSingleFileAdd = useRef<
        { file: EnteFile; sourceCollectionSummaryID?: number } | undefined
    >(undefined);
    /**
     * A queue to serialize calls to {@link remoteFilesPull}.
     */
    const remoteFilesPullQueue = useRef(new PromiseQueue<void>());
    /**
     * A queue to serialize calls to {@link remotePull}.
     */
    const remotePullQueue = useRef(new PromiseQueue<void>());

    const [uploadTypeSelectorView, setUploadTypeSelectorView] = useState(false);
    const [uploadTypeSelectorIntent, setUploadTypeSelectorIntent] =
        useState<UploadTypeSelectorIntent>("upload");

    // If the fix creation time dialog is being shown, then the list of files on
    // which it should act.
    const [fixCreationTimeFiles, setFixCreationTimeFiles] = useState<
        EnteFile[]
    >([]);
    const [fileListHeader, setFileListHeader] = useState<
        FileListHeaderOrFooter | undefined
    >(undefined);

    const [openCollectionSelector, setOpenCollectionSelector] = useState(false);
    const [collectionSelectorAttributes, setCollectionSelectorAttributes] =
        useState<CollectionSelectorAttributes | undefined>();

    const { customDomain, isInternalUser } = useSettingsSnapshot();
    const userDetails = useUserDetailsSnapshot();
    const peopleState = usePeopleStateSnapshot();

    // Modal visibility for the context menu "Add Person" action
    const {
        show: showContextMenuAssignPerson,
        props: contextMenuAssignPersonProps,
    } = useModalVisibility();

    // Named people available for assignment (used by context menu)
    const namedPeople = useMemo(
        () =>
            (peopleState?.visiblePeople ?? []).filter(
                (p) => p.type == "cgroup" && !!p.name,
            ),
        [peopleState],
    );
    const showAddPersonAction = useMemo(
        () => isMLEnabled() && namedPeople.length > 0,
        [namedPeople],
    );

    const { saveGroups, onAddSaveGroup, onRemoveSaveGroup } = useSaveGroups();
    const [, setPostCreateAlbumOp] = useState<CollectionOp | undefined>(
        undefined,
    );
    const [pendingSidebarAction, setPendingSidebarAction] = useState<
        SidebarActionID | undefined
    >(undefined);

    /**
     * The last time (epoch milliseconds) when we prompted the user for their
     * password when opening the hidden section.
     *
     * This is used to implement a grace window, where we don't reprompt them
     * for their password for the same purpose again and again.
     */
    const lastAuthenticationForHiddenTimestamp = useRef<number>(0);

    const { show: showSidebar, props: sidebarVisibilityProps } =
        useModalVisibility();
    const { show: showPlanSelector, props: planSelectorVisibilityProps } =
        useModalVisibility();
    const { show: showWhatsNew, props: whatsNewVisibilityProps } =
        useModalVisibility();
    const { show: showFixCreationTime, props: fixCreationTimeVisibilityProps } =
        useModalVisibility();
    const { show: showExport, props: exportVisibilityProps } =
        useModalVisibility();
    const {
        show: showAuthenticateUser,
        props: authenticateUserVisibilityProps,
    } = useModalVisibility();
    const { show: showAlbumNameInput, props: albumNameInputVisibilityProps } =
        useModalVisibility();
    const { show: showEditLocation, props: editLocationVisibilityProps } =
        useModalVisibility();
    const {
        show: showPickCoverPhotoDialog,
        props: pickCoverPhotoDialogVisibilityProps,
    } = useModalVisibility();

    // Progress UI state for single-file add-to-album from the FileViewer
    const [addToAlbumProgress, setAddToAlbumProgress] = useState<{
        open: boolean;
        phase: AddToAlbumPhase;
        albumId?: number;
        albumName?: string;
    }>({ open: false, phase: "processing" });
    const [publicLinkToast, setPublicLinkToast] = useState<{
        open: boolean;
        url?: string;
    }>({ open: false });

    const onAuthenticateCallback = useRef<(() => void) | undefined>(undefined);
    const onAuthenticateCancelCallback = useRef<(() => void) | undefined>(
        undefined,
    );

    const authenticateUserWithPasswordModal = useCallback(
        () =>
            new Promise<void>((resolve, reject) => {
                onAuthenticateCallback.current = resolve;
                onAuthenticateCancelCallback.current = reject;
                showAuthenticateUser();
            }),
        [],
    );

    const authenticateUser = useCallback(async () => {
        if (!isDesktop) return authenticateUserWithPasswordModal();

        const reauthResult = await reauthenticateWithAppLock();
        if (reauthResult === "authenticated") return;
        if (reauthResult === "cancelled") {
            throw new Error("app_lock_reauthentication_cancelled");
        }

        return authenticateUserWithPasswordModal();
    }, [authenticateUserWithPasswordModal]);

    const handleCloseAuthenticateUser = useCallback(() => {
        authenticateUserVisibilityProps.onClose();
        // Reject the pending authentication promise so the caller knows
        // authentication was cancelled (e.g., user clicked backdrop).
        if (onAuthenticateCancelCallback.current) {
            onAuthenticateCancelCallback.current();
            onAuthenticateCancelCallback.current = undefined;
        }
    }, [authenticateUserVisibilityProps.onClose]);

    const handleAuthenticate = useCallback(() => {
        // Clear the cancel callback first since authentication succeeded.
        onAuthenticateCancelCallback.current = undefined;
        // Then resolve the promise.
        if (onAuthenticateCallback.current) {
            onAuthenticateCallback.current();
            onAuthenticateCallback.current = undefined;
        }
    }, []);

    const handleSidebarClose = useCallback(() => {
        sidebarVisibilityProps.onClose();
    }, [sidebarVisibilityProps.onClose]);

    const handleSidebarActionHandled = useCallback(
        () => setPendingSidebarAction(undefined),
        [],
    );

    // Local aliases.
    const {
        user,
        favoriteFileIDs,
        collectionNameByID,
        fileNormalCollectionIDs,
        hiddenCollectionIDs,
        normalCollectionSummaries,
        hiddenFileIDs,
        tempDeletedFileIDs,
        tempHiddenFileIDs,
        pendingFavoriteUpdates,
        pendingVisibilityUpdates,
        isInSearchMode,
        filteredFiles,
    } = state;

    // Derived aliases.
    const barMode = state.view?.type ?? "albums";
    const activeCollectionID =
        state.view?.type == "people"
            ? undefined
            : state.view?.activeCollectionSummaryID;
    const activeCollection =
        state.view?.type == "people" ? undefined : state.view?.activeCollection;
    const activeCollectionSummary =
        state.view?.type == "people"
            ? undefined
            : state.view?.activeCollectionSummary;
    const activePerson =
        state.view?.type == "people" ? state.view.activePerson : undefined;
    const activePersonID = activePerson?.id;
    const fileCollectionIDs = useMemo(
        () =>
            state.collectionFiles.reduce((result, file) => {
                const collectionIDs = result.get(file.id);
                if (collectionIDs) {
                    if (!collectionIDs.includes(file.collectionID)) {
                        collectionIDs.push(file.collectionID);
                    }
                } else {
                    result.set(file.id, [file.collectionID]);
                }
                return result;
            }, new Map<number, number[]>()),
        [state.collectionFiles],
    );

    /**
     * the below function is used to conditionallay render the setCover option in the dropdown
     */
    const isOwnedAlbumEligibleForCover = useMemo(() => {
        if (
            isInSearchMode ||
            !activeCollection ||
            !activeCollectionSummary ||
            !user
        )
            return false;

        if (activeCollection.owner.id != user.id) return false;
        if (
            activeCollection.magicMetadata?.data.subType ==
            CollectionSubType.quicklink
        ) {
            return false;
        }

        return (
            activeCollectionSummary.attributes.has("album") ||
            activeCollectionSummary.attributes.has("folder")
        );
    }, [isInSearchMode, activeCollection, activeCollectionSummary, user]);

    const activeCollectionFiles = useMemo(() => {
        if (!activeCollection) return [];
        if (barMode == "hidden-albums" || barMode == "archive-albums") {
            return filteredFiles;
        }

        return filteredFiles.filter(({ id, magicMetadata }) => {
            const visibility = magicMetadata?.data.visibility;
            const isVisible =
                visibility === undefined ||
                visibility === ItemVisibility.visible;

            return (
                isVisible &&
                !hiddenFileIDs.has(id) &&
                !tempDeletedFileIDs.has(id) &&
                !tempHiddenFileIDs.has(id)
            );
        });
    }, [
        activeCollection,
        barMode,
        filteredFiles,
        hiddenFileIDs,
        tempDeletedFileIDs,
        tempHiddenFileIDs,
    ]);
    const mapFileSource = useMemo(
        () => ({
            collectionFiles: state.collectionFiles,
            favoriteFileIDs,
            hiddenFileIDs,
            archivedFileIDs: state.archivedFileIDs,
            tempDeletedFileIDs,
            tempHiddenFileIDs,
        }),
        [
            favoriteFileIDs,
            hiddenFileIDs,
            state.archivedFileIDs,
            state.collectionFiles,
            tempDeletedFileIDs,
            tempHiddenFileIDs,
        ],
    );
    const selectedFilesInView = useMemo(
        () => getSelectedFiles(selected, filteredFiles),
        [selected, filteredFiles],
    );
    const isAllSelectedInView =
        filteredFiles.length > 0 &&
        selectedFilesInView.length === filteredFiles.length;

    const isInArchiveSection = barMode == "archive-albums";

    const barCollectionSummaries =
        barMode == "hidden-albums"
            ? state.hiddenCollectionSummaries
            : barMode == "archive-albums"
              ? state.archivedCollectionSummaries
              : state.normalCollectionSummaries;

    const router = useRouter();

    useEffect(() => {
        const electron = globalThis.electron;
        let syncIntervalID: ReturnType<typeof setInterval> | undefined;
        let unsubscribeMainWindowFocus: (() => void) | undefined;

        void (async () => {
            if (!haveMasterKeyInSession() || !(await savedAuthToken())) {
                // If we don't have master key or auth token, reauthenticate.
                stashRedirect("/gallery");
                router.push("/");
                return;
            }

            if (!(await validateKey())) {
                // If we have credentials but they can't be decrypted, reset.
                //
                // This code is never expected to run, it is only kept as a
                // safety valve.
                logout();
                return;
            }

            // We are logged in and everything looks fine. Proceed with page
            // load initialization.

            // One time inits.
            preloadImage("/images/subscription-card-background");
            initSettings();
            setupSelectAllKeyBoardShortcutHandler();

            // Show the initial state while the rest of the sequence proceeds.
            dispatch({ type: "showAll" });

            // If this is the user's first login on this client, then show them
            // a message informing the that the initial load might take time.
            setIsFirstLoad(getAndClearIsFirstLogin());

            // If the user created a new account on this client, show them the
            // plan options.
            if (getAndClearJustSignedUp()) {
                showPlanSelector();
            }

            // Initialize the reducer.
            const user = ensureLocalUser();
            const masterKey = await masterKeyFromSession();
            if (masterKey) {
                void ensureContactsReady({
                    userID: user.id,
                    masterKeyB64: masterKey,
                }).catch((error: unknown) => {
                    log.warn(
                        "[gallery] Failed to warm contacts display cache",
                        error,
                    );
                });
            }
            const userDetails = await savedUserDetailsOrTriggerPull();
            dispatch({
                type: "mount",
                user,
                familyData: userDetails?.familyData,
                collections: await savedCollections(),
                collectionFiles: await savedCollectionFiles(),
                trashItems: await savedTrashItems(),
            });

            // Check for pending album join BEFORE fetching data
            let joinedAlbumId: number | null = null;

            if (hasPendingAlbumToJoin()) {
                try {
                    const joinedCollectionId = await processPendingAlbumJoin();
                    if (joinedCollectionId) {
                        joinedAlbumId = joinedCollectionId;
                    }
                } catch (error) {
                    log.error("Failed to join album", error);
                    showMiniDialog({
                        title: t("error"),
                        message:
                            t("album_join_failed") +
                            ": " +
                            (error as Error).message,
                    });
                }
            }

            // Fetch data from remote (this will include the newly joined album if any)
            await remotePull({ source: "gallery-mount" });

            // Navigate directly to the joined album
            if (joinedAlbumId) {
                dispatch({
                    type: "showCollectionSummary",
                    collectionSummaryID: joinedAlbumId,
                });
            }

            // Clear the first load message if needed.
            setIsFirstLoad(false);

            // Start the interval that does a periodic pull.
            syncIntervalID = setInterval(
                () => remotePull({ silent: true, source: "gallery-periodic" }),
                5 * 60 * 1000 /* 5 minutes */,
            );

            if (electron) {
                unsubscribeMainWindowFocus = subscribeMainWindowFocus(() => {
                    remotePull({ silent: true, source: "desktop-focus" });
                    void watcher.checkAccessibility();
                });
                if (await shouldShowWhatsNew(electron)) showWhatsNew();
            }
        })();

        return () => {
            clearInterval(syncIntervalID);
            unsubscribeMainWindowFocus?.();
        };
    }, []);

    useEffect(() => {
        // Only act on updates after the initial mount has completed.
        if (state.user && userDetails) {
            dispatch({ type: "setUserDetails", userDetails });
        }
    }, [state.user, userDetails]);

    useEffect(() => {
        if (typeof activeCollectionID == "undefined" || !router.isReady) {
            return;
        }
        let collectionURL = "";
        if (activeCollectionID !== PseudoCollectionID.all) {
            // TODO: Is this URL param even used?
            collectionURL = `?collection=${activeCollectionID}`;
        }
        const href = `/gallery${collectionURL}`;
        router.push(href, undefined, { shallow: true });
    }, [activeCollectionID, router.isReady]);

    useEffect(() => {
        if (router.isReady && haveMasterKeyInSession()) {
            handleSubscriptionCompletionRedirectIfNeeded(
                showMiniDialog,
                showLoadingBar,
                router,
            );
        }
    }, [router.isReady]);

    useEffect(() => {
        updateSearchCollectionsAndFiles(
            state.collections,
            state.collectionFiles,
            state.hiddenCollectionIDs,
            state.hiddenFileIDs,
        );
    }, [
        state.collections,
        state.collectionFiles,
        state.hiddenCollectionIDs,
        state.hiddenFileIDs,
    ]);

    useEffect(() => {
        dispatch({ type: "setPeopleState", peopleState });
    }, [peopleState]);

    useEffect(() => {
        if (isInSearchMode && state.searchSuggestion) {
            setFileListHeader({
                component: (
                    <SearchResultsHeader
                        searchSuggestion={state.searchSuggestion}
                        fileCount={state.searchResults?.length ?? 0}
                        sortAsc={state.searchSortAsc}
                        onSortOrderChange={(asc) =>
                            dispatch({ type: "setSearchSortOrder", asc })
                        }
                    />
                ),
                height: 104,
            });
        }
    }, [
        isInSearchMode,
        state.searchSuggestion,
        state.searchResults,
        state.searchSortAsc,
    ]);

    useEffect(() => {
        const pendingSearchSuggestion = state.pendingSearchSuggestions.at(-1);
        if (!state.isRecomputingSearchResults && pendingSearchSuggestion) {
            dispatch({ type: "updatingSearchResults" });
            filterSearchableFiles(pendingSearchSuggestion).then(
                (searchResults) => {
                    dispatch({ type: "setSearchResults", searchResults });
                },
            );
        }
    }, [state.isRecomputingSearchResults, state.pendingSearchSuggestions]);

    const selectAll = (e: KeyboardEvent) => {
        // Don't intercept Ctrl/Cmd + a if the user is typing in a text field.
        if (
            e.target instanceof HTMLInputElement ||
            e.target instanceof HTMLTextAreaElement
        ) {
            return;
        }

        // Prevent the browser's default select all handling (selecting all the
        // text in the gallery).
        e.preventDefault();

        // Don't select all if:
        if (
            // - We haven't fetched the user yet;
            !user ||
            // - There is nothing to select;
            !filteredFiles.length ||
            // - Any of the modals are open.
            uploadTypeSelectorView ||
            openCollectionSelector ||
            sidebarVisibilityProps.open ||
            planSelectorVisibilityProps.open ||
            fixCreationTimeVisibilityProps.open ||
            exportVisibilityProps.open ||
            authenticateUserVisibilityProps.open ||
            albumNameInputVisibilityProps.open ||
            pickCoverPhotoDialogVisibilityProps.open ||
            isFileViewerOpen
        ) {
            return;
        }

        // Create a selection with everything based on the current context.
        const selected = {
            ownCount: 0,
            count: 0,
            collectionID: activeCollectionID,
            context:
                barMode == "people" && activePersonID
                    ? { mode: "people" as const, personID: activePersonID }
                    : {
                          mode: barMode as
                              | "albums"
                              | "hidden-albums"
                              | "archive-albums",
                          collectionID: activeCollectionID!,
                      },
        };

        filteredFiles.forEach((item) => {
            if (item.ownerID === user.id) {
                selected.ownCount++;
            }
            selected.count++;
            // @ts-expect-error Selection code needs type fixing
            selected[item.id] = true;
        });
        setSelected(selected);
    };

    const handleSelectAll = () => {
        if (!user || !filteredFiles.length) return;

        const selected = {
            ownCount: 0,
            count: 0,
            collectionID: activeCollectionID,
            context:
                barMode == "people" && activePersonID
                    ? { mode: "people" as const, personID: activePersonID }
                    : {
                          mode: barMode as
                              | "albums"
                              | "hidden-albums"
                              | "archive-albums",
                          collectionID: activeCollectionID!,
                      },
        };

        filteredFiles.forEach((item) => {
            if (item.ownerID === user.id) {
                selected.ownCount++;
            }
            selected.count++;
            // @ts-expect-error Selection code needs type fixing
            selected[item.id] = true;
        });
        setSelected(selected);
    };

    const clearSelection = () => {
        if (!selected.count) {
            return;
        }
        setSelected({
            ownCount: 0,
            count: 0,
            collectionID: 0,
            context: undefined,
        });
    };

    const keyboardShortcutHandlerRef = useRef({ selectAll, clearSelection });

    useEffect(() => {
        keyboardShortcutHandlerRef.current = { selectAll, clearSelection };
    }, [selectAll, clearSelection]);

    const showSessionExpiredDialog = useCallback(
        () => showMiniDialog(sessionExpiredDialogAttributes(logout)),
        [showMiniDialog, logout],
    );

    // [Note: Visual feedback to acknowledge user actions]
    //
    // In some infrequent cases, we want to acknowledge some user action (e.g.
    // pressing a keyboard shortcut which doesn't have an immediate on-screen
    // impact). In these cases, we tickle the loading bar at the top to
    // acknowledge that their action.
    const handleVisualFeedback = useCallback(() => {
        showLoadingBar();
        setTimeout(hideLoadingBar, 0);
    }, [showLoadingBar, hideLoadingBar]);

    const handlePendingNavigationConsumed = useCallback(() => {
        setPendingFileNavigation(undefined);
    }, []);

    /**
     * Pull latest collections, collection files and trash items from remote.
     *
     * This wraps the vanilla {@link pullFiles} with two adornments:
     *
     * 1. Any local database updates due to the pull are also reflected in state
     *    updates to the Gallery's reducer.
     *
     * 2. Parallel calls are serialized so that there is only one invocation of
     *    the underlying {@link pullFiles} at a time.
     *
     * [Note: Full remote pull vs files pull]
     *
     * For interactive operations, if we know that our operation will not have
     * other transitive effects beyond collections, collection files and trash,
     * this is a better option as compared to a full remote pull since it
     * involves a lesser number of API requests (and thus, time).
     */
    const remoteFilesPull = useCallback(
        () =>
            remoteFilesPullQueue.current.add(() =>
                pullFiles({
                    onSetCollections: (collections) =>
                        dispatch({ type: "setCollections", collections }),
                    onSetCollectionFiles: (collectionFiles) =>
                        dispatch({
                            type: "setCollectionFiles",
                            collectionFiles,
                        }),
                    onSetTrashedItems: (trashItems) =>
                        dispatch({ type: "setTrashItems", trashItems }),
                    onDidUpdateCollectionFiles: () =>
                        exportService.onLocalFilesUpdated(),
                }),
            ),
        [],
    );

    /**
     * Perform a serialized full remote pull, also updating our component state
     * to match the updates to the local database.
     *
     * See {@link remoteFilesPull} for the general concept. This is a similar
     * wrapper over the full remote pull sequence which also adds pre-flight
     * checks (e.g. to ensure that the user's session has not expired).
     *
     * This method will usually not throw; exceptions during the pull itself are
     * caught. This is so that this promise can be unguardedly awaited without
     * failing the main operations it forms the tail end of: the remote changes
     * would've already been successfully applied, and possibly transient pull
     * failures should get resolved on the next retry.
     */
    const remotePull = useCallback(
        async (opts?: RemotePullOpts) =>
            remotePullQueue.current.add(async () => {
                const { silent, source } = opts ?? {};

                // Pre-flight checks.
                if (!navigator.onLine) return;
                if (await isSessionInvalid()) {
                    showSessionExpiredDialog();
                    return;
                }
                if (!(await masterKeyFromSession())) {
                    clearSessionStorage();
                    router.push("/credentials");
                    return;
                }

                // The pull itself.
                try {
                    if (!silent) showLoadingBar();
                    await prePullFiles();
                    await remoteFilesPull();
                    await postPullFiles(source);
                } catch (e) {
                    log.error("Remote pull failed", e);
                } finally {
                    dispatch({ type: "clearUnsyncedState" });
                    if (!silent) hideLoadingBar();
                }
            }),
        [
            showLoadingBar,
            hideLoadingBar,
            router,
            showSessionExpiredDialog,
            remoteFilesPull,
        ],
    );

    const setupSelectAllKeyBoardShortcutHandler = () => {
        const handleKeyUp = (e: KeyboardEvent) => {
            switch (e.key) {
                case "Escape":
                    keyboardShortcutHandlerRef.current.clearSelection();
                    break;
                case "a":
                    if (e.ctrlKey || e.metaKey) {
                        keyboardShortcutHandlerRef.current.selectAll(e);
                    }
                    break;
            }
        };
        document.addEventListener("keydown", handleKeyUp);
        return () => {
            document.removeEventListener("keydown", handleKeyUp);
        };
    };

    const handleRemoveFilesFromCollection = (collection: Collection) => {
        void (async () => {
            showLoadingBar();
            let notifyOthersFiles = false;
            try {
                setOpenCollectionSelector(false);
                const selectedFiles = getSelectedFiles(selected, filteredFiles);
                const processedCount = await removeFromCollection(
                    collection,
                    selectedFiles,
                );
                notifyOthersFiles = processedCount != selectedFiles.length;
                clearSelection();
                await remotePull({
                    silent: true,
                    source: "remove-from-collection",
                });
            } catch (e) {
                onGenericError(e);
            } finally {
                hideLoadingBar();
            }

            if (notifyOthersFiles) {
                showMiniDialog(notifyOthersFilesDialogAttributes());
            }
        })();
    };

    const createOnSelectForCollectionOp =
        (op: CollectionOp) => (selectedCollection: Collection) => {
            const selectedFiles = getSelectedFiles(selected, filteredFiles);
            const userFiles = selectedFiles.filter(
                // If a selection is happening, there must be a user.
                (f) => f.ownerID == user!.id,
            );
            const sourceCollectionID = selected.collectionID;

            const performSelectedCollectionOp = async (
                op: CollectionOp,
                filesToProcess: EnteFile[],
                notifySkippedFiles = false,
            ) => {
                showLoadingBar();
                try {
                    setOpenCollectionSelector(false);
                    if (filesToProcess.length > 0) {
                        await performCollectionOp(
                            op,
                            selectedCollection,
                            filesToProcess,
                            sourceCollectionID,
                        );
                    }
                    if (notifySkippedFiles) {
                        showMiniDialog(notifyOthersFilesDialogAttributes());
                    }
                    clearSelection();
                    await remotePull({
                        silent: true,
                        source: `collection-op:${op}`,
                    });
                } finally {
                    hideLoadingBar();
                }
            };

            const shouldAddInsteadOfMove =
                op == "move" &&
                selectedCollection.owner.id != user!.id &&
                canAddFilesToCollection(selectedCollection);

            if (shouldAddInsteadOfMove) {
                showMiniDialog({
                    title: t("cannot_move_to_shared_albums"),
                    message: t("cannot_move_to_shared_albums_message"),
                    continue: {
                        text: t("add"),
                        action: () =>
                            performSelectedCollectionOp("add", selectedFiles),
                    },
                    cancel: t("cancel"),
                });
                return;
            }

            void (async () => {
                try {
                    /**
                     * The add/copy path can process non-owned files when a
                     * shared album requires copying them through the current
                     * user's library.
                     */
                    const filesToProcess =
                        op == "add" ? selectedFiles : userFiles;
                    await performSelectedCollectionOp(
                        op,
                        filesToProcess,
                        op != "add" && userFiles.length != selectedFiles.length,
                    );
                } catch (e) {
                    onGenericError(e);
                }
            })();
        };

    const createOnCreateForCollectionOp = useCallback(
        (op: CollectionOp) => {
            setPostCreateAlbumOp(op);
            return showAlbumNameInput;
        },
        [showAlbumNameInput],
    );

    const handleAlbumNameSubmit = useCallback(
        async (name: string) => {
            try {
                const collection = await createAlbum(name);

                if (pendingSingleFileAdd.current) {
                    await performCollectionOp(
                        "add",
                        collection,
                        [pendingSingleFileAdd.current.file],
                        pendingSingleFileAdd.current.sourceCollectionSummaryID,
                    );

                    await remotePull({
                        silent: true,
                        source: "single-file-add-new-album",
                    });
                    // Show custom toast with album name and navigation
                    setAddToAlbumProgress({
                        open: true,
                        phase: "done",
                        albumId: collection.id,
                        albumName: collection.name,
                    });
                }

                setPostCreateAlbumOp((postCreateAlbumOp) => {
                    // The function returned by createHandleCollectionOp does its
                    // own progress and error reporting, defer to that.
                    createOnSelectForCollectionOp(postCreateAlbumOp!)(
                        collection,
                    );
                    return undefined;
                });
            } finally {
                pendingSingleFileAdd.current = undefined;
            }
        },
        [createOnSelectForCollectionOp, remotePull],
    );

    const handleFavoriteFileOp = async (
        op: Extract<FileOp, "favorite" | "unfavorite">,
        selectedFiles: EnteFile[],
    ) => {
        const filesToProcess: EnteFile[] = [];
        let skippedUnsupportedSharedFile = false;

        /**
         * We currently can only process files which either the currentUser is the owner
         * or the file has a valid metadataHash with it, so checking if we have
         * any unspported files and if so then setting the variable flag as true
         * for showing the modal later on.
         */
        for (const file of selectedFiles) {
            if (file.ownerID == user!.id || metadataHash(file.metadata)) {
                filesToProcess.push(file);
            } else {
                skippedUnsupportedSharedFile = true;
            }
        }

        // if there are no files to process, like if every file
        // we got to process was unsupported then returning the flag and state.
        if (!filesToProcess.length) {
            return { processed: false, skippedUnsupportedSharedFile };
        }

        // if we have files to process then, checking what the op is
        // favorite and then creating a map of the current state before
        // doing anything.  So if the API call fails later, the code knows
        // how to restore each file back to its old state.
        const isFavorite = op == "favorite";
        const previousFavoriteByFileID = new Map(
            filesToProcess.map((file) => [
                file.id,
                favoriteFileIDs.has(file.id),
            ]),
        );

        /**
         * Looping through the filesToProcess to do two things
         * - addPendingFavoriteUpdate: Let the UI know that this file currently have a request in progress.
         * So that the user can't trigger simultaneous updates.
         *
         * - unsycnedFavoriteUpdate: This changes the visible favorite state immediately, for a faster user
         * feedback.
         */
        for (const file of filesToProcess) {
            dispatch({ type: "addPendingFavoriteUpdate", fileID: file.id });
            dispatch({ type: "unsyncedFavoriteUpdate", file, isFavorite });
        }

        try {
            const action = isFavorite
                ? addToFavoritesCollection
                : removeFromFavoritesCollection;
            await action(filesToProcess);
            return { processed: true, skippedUnsupportedSharedFile };
        } catch (e) {
            for (const file of filesToProcess) {
                dispatch({
                    type: "unsyncedFavoriteUpdate",
                    file,
                    isFavorite: previousFavoriteByFileID.get(file.id)!,
                });
            }
            throw e;
        } finally {
            for (const file of filesToProcess) {
                dispatch({
                    type: "removePendingFavoriteUpdate",
                    fileID: file.id,
                });
            }
        }
    };

    const createFileOpHandler =
        (op: FileOp, options?: { suppressSelectionBar?: boolean }) => () => {
            void (async () => {
                if (options?.suppressSelectionBar) {
                    setSuppressContextSelectionBar(true);
                }
                showLoadingBar();
                try {
                    if (op == "sendLink") {
                        const selectedFiles = getSelectedFiles(
                            selected,
                            filteredFiles,
                        );
                        const ownedSelectedFiles = selectedFiles.filter(
                            // There'll be a user if files are being selected.
                            (file) => file.ownerID == user!.id,
                        );
                        if (!ownedSelectedFiles.length) return;
                        if (ownedSelectedFiles.length != selectedFiles.length) {
                            showMiniDialog(notifyOthersFilesDialogAttributes());
                        }

                        const quickLinkCollection =
                            await createQuickLinkCollection(
                                quickLinkNameForFiles(ownedSelectedFiles),
                            );
                        await addToCollection(
                            quickLinkCollection,
                            ownedSelectedFiles,
                        );
                        const publicURL = await createPublicURL(
                            quickLinkCollection.id,
                            { enableJoin: false },
                        );
                        const resolvedURL = await resolveQuickLinkURL(
                            publicURL.url,
                            quickLinkCollection.key,
                            customDomain,
                        );
                        setPublicLinkToast({ open: true, url: resolvedURL });

                        clearSelection();
                        await remotePull({
                            silent: true,
                            source: "selected-files-quick-link",
                        });
                        return;
                    }

                    // When hiding use all non-hidden files instead of the filtered
                    // files since we want to move all files copies to the hidden
                    // collection.
                    const opFiles =
                        op == "hide"
                            ? state.collectionFiles.filter(
                                  (f) => !state.hiddenFileIDs.has(f.id),
                              )
                            : filteredFiles;
                    const selectedFiles = getSelectedFiles(selected, opFiles);
                    if (op == "favorite" || op == "unfavorite") {
                        const { processed, skippedUnsupportedSharedFile } =
                            await handleFavoriteFileOp(op, selectedFiles);
                        clearSelection();
                        if (processed) {
                            await remotePull({
                                silent: true,
                                source: `file-op:${op}`,
                            });
                        }
                        if (skippedUnsupportedSharedFile) {
                            showMiniDialog(
                                notifyUnsupportedSharedFavoritesDialogAttributes(),
                            );
                        }
                        return;
                    }

                    const ownedSelectedFiles =
                        op == "download"
                            ? selectedFiles
                            : selectedFiles.filter(
                                  // There'll be a user if files are being selected.
                                  (file) => file.ownerID == user!.id,
                              );
                    if (ownedSelectedFiles.length > 0) {
                        await performFileOp(
                            op,
                            ownedSelectedFiles,
                            onAddSaveGroup,
                            handleMarkTempDeleted,
                            () => dispatch({ type: "clearTempDeleted" }),
                            (files) =>
                                dispatch({ type: "markTempHidden", files }),
                            () => dispatch({ type: "clearTempHidden" }),
                            (files) => {
                                setFixCreationTimeFiles(files);
                                showFixCreationTime();
                            },
                        );
                    }

                    // Apart from download, the other operations currently only work
                    // on the user's own files.
                    //
                    // See: [Note: Add and move of non-user files].
                    if (
                        op != "download" &&
                        ownedSelectedFiles.length != selectedFiles.length
                    ) {
                        showMiniDialog(notifyOthersFilesDialogAttributes());
                    }
                    clearSelection();
                    await remotePull({ silent: true, source: `file-op:${op}` });
                } catch (e) {
                    onGenericError(e);
                } finally {
                    if (options?.suppressSelectionBar) {
                        setSuppressContextSelectionBar(false);
                    }
                    hideLoadingBar();
                }
            })();
        };

    const handleAddPersonToSelectedFiles = useCallback(
        async (personID: string) => {
            showLoadingBar();
            try {
                const selectedFiles = getSelectedFiles(selected, filteredFiles);
                await addManualFileAssignmentsToPerson(
                    personID,
                    selectedFiles.map((f) => f.id),
                );
                clearSelection();
                const personName = namedPeople.find(
                    (p) => p.id === personID,
                )?.name;
                showNotification({
                    color: "secondary",
                    startIcon: <CheckCircleIcon />,
                    title: t("added_to_person"),
                    caption: personName,
                });
            } catch (e) {
                onGenericError(e);
            } finally {
                hideLoadingBar();
            }
        },
        [
            selected,
            filteredFiles,
            clearSelection,
            showNotification,
            namedPeople,
            showLoadingBar,
            hideLoadingBar,
            onGenericError,
        ],
    );

    // Handler for selecting a person from the context menu assign person dialog
    const handleContextMenuSelectPerson = useCallback(
        (personID: string) => {
            contextMenuAssignPersonProps.onClose();
            void handleAddPersonToSelectedFiles(personID);
        },
        [contextMenuAssignPersonProps, handleAddPersonToSelectedFiles],
    );

    const handleEditLocationConfirm = useCallback(
        async (location: Location) => {
            // Only update files owned by the user
            const userFiles = selectedFilesInView.filter(
                (f) => f.ownerID == user!.id,
            );
            if (userFiles.length > 0) {
                await updateFilesLocation(
                    userFiles,
                    location.latitude,
                    location.longitude,
                );
            }
            void remotePull({ silent: true, source: "edit-location" });
        },
        [selectedFilesInView, user, remotePull],
    );

    const handleSelectSearchOption = (
        searchOption: SearchOption | undefined,
        options?: { shouldExitSearchMode?: boolean },
    ) => {
        if (searchOption) {
            const type = searchOption.suggestion.type;
            if (type == "collection") {
                dispatch({
                    type: "showCollectionSummary",
                    collectionSummaryID: searchOption.suggestion.collectionID,
                });
            } else if (type == "person") {
                dispatch({
                    type: "showPerson",
                    personID: searchOption.suggestion.person.id,
                });
            } else if (type == "sidebarAction") {
                setPendingSidebarAction(searchOption.suggestion.actionID);
                showSidebar();

                const shouldExitSearchMode =
                    options?.shouldExitSearchMode ?? true;
                dispatch({ type: "exitSearch", shouldExitSearchMode });
            } else {
                dispatch({
                    type: "enterSearchMode",
                    searchSuggestion: searchOption.suggestion,
                });
            }
        } else {
            // Pass shouldExitSearchMode to the reducer (defaults to true for backward compatibility)
            const shouldExitSearchMode = options?.shouldExitSearchMode ?? true;
            dispatch({ type: "exitSearch", shouldExitSearchMode });
        }
    };

    const openUploader = (intent?: UploadTypeSelectorIntent) => {
        if (uploadManager.isUploadInProgress()) return;
        setUploadTypeSelectorView(true);
        setUploadTypeSelectorIntent(intent ?? "upload");
    };

    const handleShowCollectionSummaryWithID = useCallback(
        (collectionSummaryID: number | undefined) => {
            // Trigger a pull of the latest data from remote when opening the trash.
            //
            // This is needed for a specific scenario:
            //
            // 1. User deletes a collection, selecting the option to delete files.
            // 2. Museum acks, and then client does a trash pull.
            //
            // This trash pull will not contain the files that belonged to the
            // collection that got deleted because the collection deletion is a
            // asynchronous operation.
            //
            // So the user might not see the entry for the just deleted file if they
            // were to go to the trash meanwhile (until the next pull happens). To
            // avoid this, we trigger a trash pull whenever it is opened.
            if (collectionSummaryID == PseudoCollectionID.trash) {
                void remoteFilesPull();
            }

            dispatch({ type: "showCollectionSummary", collectionSummaryID });
        },
        [],
    );

    /**
     * Switch to gallery view to show a collection or pseudo-collection.
     *
     * @param collectionSummaryID The ID of the {@link CollectionSummary} to
     * show. If not provided, show the "All" section.
     *
     * @param isHidden If `true`, then any reauthentication as appropriate
     * before switching to the hidden section of the app is performed first
     * before before switching to the relevant collection or pseudo-collection.
     */
    const showCollectionSummary = useCallback(
        async (
            collectionSummaryID: number | undefined,
            isHiddenCollectionSummary: boolean | undefined,
        ) => {
            const lastAuthAt = lastAuthenticationForHiddenTimestamp.current;

            if (
                isHiddenCollectionSummary &&
                barMode != "hidden-albums" &&
                Date.now() - lastAuthAt > 5 * 60 * 1e3 /* 5 minutes */
            ) {
                try {
                    await authenticateUser();
                    lastAuthenticationForHiddenTimestamp.current = Date.now();
                } catch {
                    // User cancelled authentication (e.g., clicked backdrop).
                    // Don't proceed to show the collection.
                    return;
                }
            }

            handleShowCollectionSummaryWithID(collectionSummaryID);
        },
        [authenticateUser, handleShowCollectionSummaryWithID, barMode],
    );

    const handleSidebarShowCollectionSummary = showCollectionSummary;

    const handleDownloadStatusNotificationsShowCollectionSummary = useCallback(
        (
            collectionSummaryID: number | undefined,
            isHiddenCollectionSummary: boolean | undefined,
        ) => {
            void showCollectionSummary(
                collectionSummaryID,
                isHiddenCollectionSummary,
            );
        },
        [showCollectionSummary],
    );

    const handleChangeBarMode = (mode: GalleryBarMode) =>
        mode == "people"
            ? dispatch({ type: "showPeople" })
            : dispatch({ type: "showAlbums" });

    const handleFileViewerToggleFavorite = useCallback(
        async (file: EnteFile) => {
            const fileID = file.id;
            const isFavorite = favoriteFileIDs.has(fileID);

            dispatch({ type: "addPendingFavoriteUpdate", fileID });
            dispatch({
                type: "unsyncedFavoriteUpdate",
                file,
                isFavorite: !isFavorite,
            });
            try {
                const action = isFavorite
                    ? removeFromFavoritesCollection
                    : addToFavoritesCollection;
                await action([file]);
            } catch (e) {
                dispatch({ type: "unsyncedFavoriteUpdate", file, isFavorite });
                throw e;
            } finally {
                dispatch({ type: "removePendingFavoriteUpdate", fileID });
            }
        },
        [favoriteFileIDs],
    );

    const handleFileViewerFileVisibilityUpdate = useCallback(
        async (file: EnteFile, visibility: ItemVisibility) => {
            const fileID = file.id;
            dispatch({ type: "addPendingVisibilityUpdate", fileID });
            try {
                await updateFilesVisibility([file], visibility);
                // [Note: Interactive updates to file metadata]
                //
                // 1. Update the remote metadata.
                //
                // 2. Construct a fake a metadata object with the updates
                //    reflected in it.
                //
                // 3. The caller (eventually) triggers a remote pull in the
                //    background, but meanwhile uses this updated metadata.
                //
                // TODO: Replace with files pull?
                dispatch({
                    type: "unsyncedPrivateMagicMetadataUpdate",
                    fileID,
                    privateMagicMetadata: {
                        ...file.magicMetadata,
                        count: file.magicMetadata?.count ?? 0,
                        version: (file.magicMetadata?.version ?? 0) + 1,
                        data: { ...file.magicMetadata?.data, visibility },
                    },
                });
            } finally {
                dispatch({ type: "removePendingVisibilityUpdate", fileID });
            }
        },
        [],
    );

    const handleFileViewerSendLink = useCallback(
        async (file: EnteFile) => {
            if (file.ownerID != user?.id) return;

            showLoadingBar();
            try {
                const quickLinkCollection = await createQuickLinkCollection(
                    quickLinkNameForFiles([file]),
                );
                await addToCollection(quickLinkCollection, [file]);
                const publicURL = await createPublicURL(
                    quickLinkCollection.id,
                    { enableJoin: false },
                );
                const resolvedURL = await resolveQuickLinkURL(
                    publicURL.url,
                    quickLinkCollection.key,
                    customDomain,
                );
                setPublicLinkToast({ open: true, url: resolvedURL });
                await remotePull({ silent: true, source: "viewer-send-link" });
            } catch (e) {
                onGenericError(e);
            } finally {
                hideLoadingBar();
            }
        },
        [
            user?.id,
            showLoadingBar,
            hideLoadingBar,
            customDomain,
            remotePull,
            onGenericError,
        ],
    );

    const handleMarkTempDeleted = useCallback(
        (files: EnteFile[]) => dispatch({ type: "markTempDeleted", files }),
        [],
    );

    const handleSelectCollection = useCallback(
        (collectionID: number) =>
            dispatch({
                type: "showCollectionSummary",
                collectionSummaryID: collectionID,
            }),
        [],
    );

    const handleSelectPerson = useCallback(
        (personID: string) => dispatch({ type: "showPerson", personID }),
        [],
    );

    const handleOpenCollectionSelector = useCallback(
        (attributes: CollectionSelectorAttributes) => {
            setCollectionSelectorAttributes(attributes);
            setOpenCollectionSelector(true);
        },
        [],
    );

    const selectedCount = selected.count;
    const selectedOwnCount = selected.ownCount;
    const selectedFavoriteCount = useMemo(() => {
        if (selected.count == 0) return 0;
        let count = 0;
        for (const [key, value] of Object.entries(selected)) {
            if (typeof value === "boolean" && value) {
                if (favoriteFileIDs.has(Number(key))) {
                    count += 1;
                }
            }
        }
        return count;
    }, [favoriteFileIDs, selected]);

    const handleUpdateCollectionCover = useCallback(
        async (coverID: number) => {
            if (!activeCollection || !isOwnedAlbumEligibleForCover)
                return false;

            showLoadingBar();
            try {
                await updateCollectionCover(activeCollection, coverID);
                await remotePull({
                    silent: true,
                    source: "update-collection-cover",
                });
                return true;
            } catch (e) {
                onGenericError(e);
                return false;
            } finally {
                hideLoadingBar();
            }
        },
        [
            activeCollection,
            isOwnedAlbumEligibleForCover,
            showLoadingBar,
            remotePull,
            onGenericError,
            hideLoadingBar,
        ],
    );

    /**
     * Handle a context menu action on a file.
     *
     * This handler is called when the user right-clicks on a file thumbnail
     * and selects an action from the context menu.
     */
    const handleContextMenuAction = useCallback(
        (
            action: FileContextAction,
            _targetFile?: EnteFile,
            meta?: { isEphemeralSingleSelection: boolean },
        ) => {
            const suppressSelectionBar = !!meta?.isEphemeralSingleSelection;
            // The selection should already be set by FileList's handleContextMenu
            // We just need to invoke the appropriate action handler
            switch (action) {
                case "sendLink":
                    createFileOpHandler("sendLink", { suppressSelectionBar })();
                    break;
                case "download":
                    createFileOpHandler("download", { suppressSelectionBar })();
                    break;
                case "favorite":
                    createFileOpHandler("favorite", { suppressSelectionBar })();
                    break;
                case "unfavorite":
                    createFileOpHandler("unfavorite", {
                        suppressSelectionBar,
                    })();
                    break;
                case "archive":
                    createFileOpHandler("archive", { suppressSelectionBar })();
                    break;
                case "unarchive":
                    createFileOpHandler("unarchive", {
                        suppressSelectionBar,
                    })();
                    break;
                case "hide":
                    createFileOpHandler("hide", { suppressSelectionBar })();
                    break;
                case "fixTime":
                    createFileOpHandler("fixTime", { suppressSelectionBar })();
                    break;
                case "trash":
                    showMiniDialog({
                        title: t("trash_files_title"),
                        message: t("trash_files_message"),
                        continue: {
                            text: t("move_to_trash"),
                            color: "critical",
                            action: createFileOpHandler("trash", {
                                suppressSelectionBar,
                            }),
                        },
                    });
                    break;
                case "deletePermanently":
                    showMiniDialog({
                        title: t("delete_files_title"),
                        message: t("delete_files_message"),
                        continue: {
                            text: t("delete"),
                            color: "critical",
                            action: createFileOpHandler("deletePermanently", {
                                suppressSelectionBar,
                            }),
                        },
                    });
                    break;
                case "restore":
                    handleOpenCollectionSelector({
                        action: "restore",
                        onCreateCollection:
                            createOnCreateForCollectionOp("restore"),
                        onSelectCollection:
                            createOnSelectForCollectionOp("restore"),
                    });
                    break;
                case "addToAlbum":
                    handleOpenCollectionSelector({
                        action: "add",
                        sourceCollectionSummaryID: activeCollectionSummary?.id,
                        onCreateCollection:
                            createOnCreateForCollectionOp("add"),
                        onSelectCollection:
                            createOnSelectForCollectionOp("add"),
                    });
                    break;
                case "moveToAlbum":
                    handleOpenCollectionSelector({
                        action: "move",
                        sourceCollectionSummaryID: activeCollectionSummary?.id,
                        onCreateCollection:
                            createOnCreateForCollectionOp("move"),
                        onSelectCollection:
                            createOnSelectForCollectionOp("move"),
                    });
                    break;
                case "removeFromAlbum": {
                    if (!activeCollection) break;
                    const isSharedIncoming =
                        activeCollectionSummary?.attributes.has(
                            "sharedIncoming",
                        );
                    const isSharedOutgoing =
                        activeCollectionSummary?.attributes.has(
                            "sharedOutgoing",
                        );
                    const isRemovingOthers = selectedCount != selectedOwnCount;
                    const remove = () =>
                        handleRemoveFilesFromCollection(activeCollection);

                    if (isSharedIncoming) {
                        if (isRemovingOthers) {
                            showMiniDialog({
                                title: t("remove_from_album"),
                                message: t("remove_from_album_others_message"),
                                continue: {
                                    text: t("remove"),
                                    color: "critical",
                                    action: remove,
                                },
                                cancel: t("cancel"),
                            });
                        } else {
                            remove();
                        }
                        break;
                    }

                    if (isSharedOutgoing && isRemovingOthers) {
                        showMiniDialog({
                            title: t("remove_from_album"),
                            message: t("remove_from_album_others_message"),
                            continue: {
                                text: t("remove"),
                                color: "critical",
                                action: remove,
                            },
                        });
                        break;
                    }

                    const onlyUserFiles = !isRemovingOthers;
                    showMiniDialog({
                        title: t("remove_from_album"),
                        message: onlyUserFiles
                            ? t("confirm_remove_message")
                            : t("confirm_remove_incl_others_message"),
                        continue: {
                            text: t("yes_remove"),
                            color: onlyUserFiles ? "primary" : "critical",
                            action: remove,
                        },
                    });
                    break;
                }
                case "unhide":
                    handleOpenCollectionSelector({
                        action: "unhide",
                        onCreateCollection:
                            createOnCreateForCollectionOp("unhide"),
                        onSelectCollection:
                            createOnSelectForCollectionOp("unhide"),
                    });
                    break;
                case "addPerson":
                    showContextMenuAssignPerson();
                    break;
                case "editLocation":
                    showEditLocation();
                    break;
            }
        },
        [
            createFileOpHandler,
            createOnCreateForCollectionOp,
            createOnSelectForCollectionOp,
            handleOpenCollectionSelector,
            handleRemoveFilesFromCollection,
            showMiniDialog,
            showContextMenuAssignPerson,
            showEditLocation,
            activeCollectionSummary,
            activeCollection,
            selectedCount,
            selectedOwnCount,
        ],
    );

    const handleOpenPickCoverPhotoDialog = useCallback(() => {
        if (!isOwnedAlbumEligibleForCover) return;
        showPickCoverPhotoDialog();
    }, [isOwnedAlbumEligibleForCover, showPickCoverPhotoDialog]);

    const handleUseSelectedCoverPhoto = useCallback(
        async (file: EnteFile) => handleUpdateCollectionCover(file.id),
        [handleUpdateCollectionCover],
    );

    const handleResetCollectionCover = useCallback(
        async () => handleUpdateCollectionCover(0),
        [handleUpdateCollectionCover],
    );

    const handleCloseCollectionSelector = useCallback(
        () => setOpenCollectionSelector(false),
        [],
    );

    /**
     * Handles adding a single file to a collection by opening a collection selector dialog.
     *
     * @param file - The EnteFile to be added to a collection
     * @param sourceCollectionSummaryID - Optional ID of the source collection where the file currently resides
     *
     * @remarks
     * This function stores the pending file operation, displays a collection selector modal,
     * and handles three scenarios:
     * - User selects an existing collection: adds the file and triggers a remote pull
     * - User creates a new collection: sets up post-create operation and shows album name input
     * - User cancels: clears the pending operation
     *
     * The function shows/hides a loading bar during the add operation and handles errors generically.
     */
    const handleAddSingleFileToCollection = useCallback(
        (file: EnteFile, sourceCollectionSummaryID?: number) => {
            pendingSingleFileAdd.current = { file, sourceCollectionSummaryID };

            const handleSelect = async (collection: Collection) => {
                try {
                    // Show add-to-album progress UI for this operation.
                    setAddToAlbumProgress({ open: true, phase: "processing" });
                    showLoadingBar();
                    await performCollectionOp(
                        "add",
                        collection,
                        [file],
                        sourceCollectionSummaryID,
                    );
                    await remotePull({
                        silent: true,
                        source: "single-file-add-to-album",
                    });
                    // Show custom toast with album name and navigation
                    setAddToAlbumProgress({
                        open: true,
                        phase: "done",
                        albumId: collection.id,
                        albumName: collection.name,
                    });
                } catch (e) {
                    onGenericError(e);
                    // Do not show the toast on failure; handled by generic error notification
                } finally {
                    pendingSingleFileAdd.current = undefined;
                    hideLoadingBar();
                }
            };

            const handleCreate = () => {
                setPostCreateAlbumOp("add");
                showAlbumNameInput();
            };

            handleOpenCollectionSelector({
                action: "add",
                sourceCollectionSummaryID,
                onSelectCollection: (collection) =>
                    void handleSelect(collection),
                onCreateCollection: handleCreate,
                onCancel: () => {
                    pendingSingleFileAdd.current = undefined;
                },
            });
        },
        [handleOpenCollectionSelector, remotePull, onGenericError],
    );

    const showAppDownloadFooter =
        state.collectionFiles.length < 30 && !isInSearchMode;

    const fileListFooter = useMemo(
        () => (showAppDownloadFooter ? createAppDownloadFooter() : undefined),
        [showAppDownloadFooter],
    );

    const hasActiveFileSelection =
        selected.count > 0 && selected.collectionID === activeCollectionID;
    const showSelectionBar =
        hasActiveFileSelection &&
        !suppressContextSelectionBar &&
        !(isContextMenuOpen && selected.count === 1);

    if (!user) {
        // Don't render until we dispatch "mount" with the logged in user.
        //
        // Tag: [Note: Gallery children can assume user]
        return <div></div>;
    }

    return (
        <FullScreenDropZone
            message={
                watchFolderView ? t("watch_folder_dropzone_hint") : undefined
            }
            disabled={shouldDisableDropzone}
            onDrop={setDragAndDropFiles}
        >
            {blockingLoad && <TranslucentLoadingOverlay />}
            <PlanSelector
                {...planSelectorVisibilityProps}
                setLoading={(v) => setBlockingLoad(v)}
            />
            <CollectionSelector
                open={openCollectionSelector}
                onClose={handleCloseCollectionSelector}
                attributes={collectionSelectorAttributes}
                collectionSummaries={
                    collectionSelectorAttributes?.showHiddenCollections
                        ? state.hiddenCollectionSummaries
                        : normalCollectionSummaries
                }
                collectionForCollectionSummaryID={(id) =>
                    findCollectionCreatingUncategorizedIfNeeded(
                        state.collections,
                        id,
                    )
                }
            />
            <DownloadStatusNotifications
                {...{ saveGroups, onRemoveSaveGroup }}
                onShowCollectionSummary={
                    handleDownloadStatusNotificationsShowCollectionSummary
                }
            />
            <FixCreationTime
                {...fixCreationTimeVisibilityProps}
                files={fixCreationTimeFiles}
                onRemotePull={remotePull}
            />
            <NavbarBase
                sx={[
                    {
                        mb: "12px",
                        px: "24px",
                        "@media (width < 720px)": { px: "4px" },
                    },
                    showSelectionBar && { borderColor: "accent.main" },
                ]}
            >
                {showSelectionBar ? (
                    <SelectedFileOptions
                        barMode={barMode}
                        isInSearchMode={isInSearchMode}
                        collection={
                            isInSearchMode ? undefined : activeCollection
                        }
                        collectionSummary={
                            isInSearchMode ? undefined : activeCollectionSummary
                        }
                        selectedFileCount={selected.count}
                        selectedOwnFileCount={selected.ownCount}
                        selectedFavoriteCount={selectedFavoriteCount}
                        onClearSelection={clearSelection}
                        onRemoveFilesFromCollection={
                            handleRemoveFilesFromCollection
                        }
                        onOpenCollectionSelector={handleOpenCollectionSelector}
                        onSelectAll={handleSelectAll}
                        isAllSelected={isAllSelectedInView}
                        {...{
                            createOnCreateForCollectionOp,
                            createOnSelectForCollectionOp,
                            createFileOpHandler,
                            onShowAssignPersonDialog: showAddPersonAction
                                ? showContextMenuAssignPerson
                                : undefined,
                        }}
                        onEditLocation={showEditLocation}
                    />
                ) : barMode == "hidden-albums" ? (
                    <SectionNavbarContents
                        title={t("section_hidden")}
                        onBack={() => dispatch({ type: "showAlbums" })}
                        onUpload={openUploader}
                    />
                ) : !isInSearchMode && isInArchiveSection ? (
                    <SectionNavbarContents
                        title={t("section_archive")}
                        onBack={() => dispatch({ type: "showAlbums" })}
                        onUpload={openUploader}
                    />
                ) : (
                    <NormalNavbarContents
                        {...{ isInSearchMode }}
                        onSidebar={showSidebar}
                        onUpload={openUploader}
                        onShowSearchInput={() =>
                            dispatch({ type: "enterSearchMode" })
                        }
                        onSelectSearchOption={handleSelectSearchOption}
                        onSelectPeople={() => dispatch({ type: "showPeople" })}
                        onSelectPerson={handleSelectPerson}
                    />
                )}
            </NavbarBase>
            {isFirstLoad && <FirstLoadMessage />}
            {isOffline && <OfflineMessage />}

            <GalleryBarAndListHeader
                {...{
                    user,
                    // TODO: These are incorrect assertions, the types of the
                    // component need to be updated.
                    activeCollection: activeCollection!,
                    activeCollectionID: activeCollectionID!,
                    files: activeCollection
                        ? activeCollectionFiles
                        : filteredFiles,
                    mapFileSource,
                    activePerson,
                    setFileListHeader,
                    saveGroups,
                    canCreateAlbum: !isInArchiveSection,
                    onAddSaveGroup,
                    onMarkTempDeleted: handleMarkTempDeleted,
                    onAddFileToCollection: handleAddSingleFileToCollection,
                    onRemoteFilesPull: remoteFilesPull,
                    onVisualFeedback: handleVisualFeedback,
                    fileNormalCollectionIDs,
                    collectionNameByID,
                    onSelectCollection: handleSelectCollection,
                    canSetAlbumCover: isOwnedAlbumEligibleForCover,
                    onSetAlbumCover: handleOpenPickCoverPhotoDialog,
                }}
                mode={barMode}
                shouldHide={isInSearchMode}
                barCollectionSummaries={barCollectionSummaries}
                emailByUserID={state.emailByUserID}
                shareSuggestionEmails={state.shareSuggestionEmails}
                people={
                    (state.view?.type == "people"
                        ? state.view.visiblePeople
                        : undefined) ?? []
                }
                allPeople={
                    (state.view?.type == "people"
                        ? state.view.people
                        : undefined) ?? []
                }
                onChangeMode={handleChangeBarMode}
                setBlockingLoad={setBlockingLoad}
                setActiveCollectionID={handleShowCollectionSummaryWithID}
                hasActiveFileSelection={hasActiveFileSelection}
                onRemotePull={remotePull}
                onSelectPerson={handleSelectPerson}
            />

            <Upload
                {...{
                    user,
                    dragAndDropFiles,
                    uploadTypeSelectorIntent,
                    uploadTypeSelectorView,
                }}
                isFirstUpload={haveOnlySystemCollections(
                    normalCollectionSummaries,
                )}
                activeCollection={activeCollection}
                closeUploadTypeSelector={setUploadTypeSelectorView.bind(
                    null,
                    false,
                )}
                setLoading={setBlockingLoad}
                setShouldDisableDropzone={setShouldDisableDropzone}
                onRemotePull={remotePull}
                onRemoteFilesPull={remoteFilesPull}
                onOpenCollectionSelector={handleOpenCollectionSelector}
                onCloseCollectionSelector={handleCloseCollectionSelector}
                onUploadFile={(file) => dispatch({ type: "uploadFile", file })}
                onShowPlanSelector={showPlanSelector}
                onShowSessionExpiredDialog={showSessionExpiredDialog}
                isInHiddenSection={barMode == "hidden-albums"}
            />
            <Sidebar
                {...sidebarVisibilityProps}
                onClose={handleSidebarClose}
                normalCollectionSummaries={normalCollectionSummaries}
                uncategorizedCollectionSummaryID={
                    state.uncategorizedCollectionSummaryID
                }
                pendingAction={pendingSidebarAction}
                onActionHandled={handleSidebarActionHandled}
                onShowPlanSelector={showPlanSelector}
                onShowCollectionSummary={handleSidebarShowCollectionSummary}
                onShowExport={showExport}
                onAuthenticateUser={authenticateUser}
            />
            <WhatsNew {...whatsNewVisibilityProps} />
            <AssignPersonDialog
                {...contextMenuAssignPersonProps}
                people={namedPeople}
                title={t("add_a_person")}
                onSelectPerson={handleContextMenuSelectPerson}
            />
            {!isInSearchMode &&
            !isFirstLoad &&
            !state.collectionFiles.length &&
            activeCollectionID === PseudoCollectionID.all ? (
                isInternalUser ? (
                    <GalleryEmptyStateV2
                        isUploadInProgress={uploadManager.isUploadInProgress()}
                        onUpload={openUploader}
                    />
                ) : (
                    <GalleryEmptyState
                        isUploadInProgress={uploadManager.isUploadInProgress()}
                        onUpload={openUploader}
                    />
                )
            ) : !isInSearchMode &&
              !isFirstLoad &&
              state.view?.type == "people" &&
              !state.view.activePerson ? (
                <PeopleEmptyState />
            ) : (
                <FileListWithViewer
                    mode={barMode}
                    modePlus={isInSearchMode ? "search" : barMode}
                    header={fileListHeader}
                    footer={fileListFooter}
                    user={user}
                    files={filteredFiles}
                    mapFileSource={mapFileSource}
                    enableDownload={true}
                    disableGrouping={state.searchSuggestion?.type == "clip"}
                    enableSelect={true}
                    selected={selected}
                    setSelected={setSelected}
                    // TODO: Incorrect assertion, need to update the type
                    activeCollectionID={activeCollectionID!}
                    activeCollectionSummary={activeCollectionSummary}
                    activeCollection={activeCollection}
                    activePersonID={activePerson?.id}
                    isInIncomingSharedCollection={activeCollectionSummary?.attributes.has(
                        "sharedIncoming",
                    )}
                    isInHiddenSection={barMode == "hidden-albums"}
                    onContextMenuAction={handleContextMenuAction}
                    onContextMenuOpenChange={setIsContextMenuOpen}
                    suppressSelectionUI={suppressContextSelectionBar}
                    showAddPersonAction={showAddPersonAction}
                    showEditLocationAction={selected.ownCount > 0}
                    {...{
                        favoriteFileIDs,
                        collectionNameByID,
                        fileNormalCollectionIDs,
                        fileCollectionIDs,
                        hiddenCollectionIDs,
                        pendingFavoriteUpdates,
                        pendingVisibilityUpdates,
                        onAddSaveGroup,
                    }}
                    collectionSummaries={normalCollectionSummaries}
                    emailByUserID={state.emailByUserID}
                    onToggleFavorite={handleFileViewerToggleFavorite}
                    onFileVisibilityUpdate={
                        handleFileViewerFileVisibilityUpdate
                    }
                    onSendLink={handleFileViewerSendLink}
                    onMarkTempDeleted={handleMarkTempDeleted}
                    onSetOpenFileViewer={setIsFileViewerOpen}
                    onRemotePull={remotePull}
                    onRemoteFilesPull={remoteFilesPull}
                    onVisualFeedback={handleVisualFeedback}
                    onSelectCollection={handleSelectCollection}
                    onSelectPerson={handleSelectPerson}
                    onAddFileToCollection={handleAddSingleFileToCollection}
                    pendingFileIndex={pendingFileNavigation?.fileIndex}
                    pendingFileSidebar={pendingFileNavigation?.sidebar}
                    pendingHighlightCommentID={pendingFileNavigation?.commentID}
                    onPendingNavigationConsumed={
                        handlePendingNavigationConsumed
                    }
                />
            )}
            {activeCollection && (
                <PickCoverPhotoDialog
                    {...pickCoverPhotoDialogVisibilityProps}
                    collection={activeCollection}
                    files={activeCollectionFiles}
                    user={user}
                    canResetToDefault={
                        (activeCollection.pubMagicMetadata?.data.coverID ?? 0) >
                        0
                    }
                    onUseSelectedPhoto={handleUseSelectedCoverPhoto}
                    onResetToDefault={handleResetCollectionCover}
                />
            )}
            <Export {...exportVisibilityProps} {...{ collectionNameByID }} />
            <AuthenticateUser
                open={authenticateUserVisibilityProps.open}
                onClose={handleCloseAuthenticateUser}
                onAuthenticate={handleAuthenticate}
            />
            <SingleInputDialog
                {...albumNameInputVisibilityProps}
                title={t("new_album")}
                label={t("album_name")}
                submitButtonTitle={t("create")}
                onClose={() => {
                    // If the user dismisses the album name dialog without
                    // submitting, clear any pending single-file add so that it
                    // doesn't leak into a future album creation.
                    pendingSingleFileAdd.current = undefined;
                    albumNameInputVisibilityProps.onClose();
                }}
                onSubmit={handleAlbumNameSubmit}
            />
            <QuickLinkCreatedNotification
                open={publicLinkToast.open}
                onCopy={() => {
                    if (publicLinkToast.url) {
                        void navigator.clipboard.writeText(publicLinkToast.url);
                    }
                }}
                onClose={() =>
                    setPublicLinkToast((prev) => ({ ...prev, open: false }))
                }
            />
            <AlbumAddedNotification
                open={addToAlbumProgress.open}
                onClose={() =>
                    setAddToAlbumProgress((s) => ({ ...s, open: false }))
                }
                phase={addToAlbumProgress.phase}
                albumName={addToAlbumProgress.albumName}
            />
            <EditLocationDialog
                {...editLocationVisibilityProps}
                files={selectedFilesInView}
                onConfirm={handleEditLocationConfirm}
            />
        </FullScreenDropZone>
    );
};

export default Page;

const FirstLoadMessage: React.FC = () => (
    <CenteredRow>
        <Typography variant="small" sx={{ color: "text.muted" }}>
            {t("initial_load_delay_warning")}
        </Typography>
    </CenteredRow>
);

const OfflineMessage: React.FC = () => (
    <Typography
        variant="small"
        sx={{ bgcolor: "background.paper", p: 2, mb: 1, textAlign: "center" }}
    >
        {t("offline_message")}
    </Typography>
);

/**
 * Preload all three variants of a responsive image.
 */
const preloadImage = (imgBasePath: string) => {
    const srcset: string[] = [];
    for (let i = 1; i <= 3; i++) srcset.push(`${imgBasePath}/${i}x.png ${i}x`);
    new Image().srcset = srcset.join(",");
};

type NormalNavbarContentsProps = SearchBarProps & {
    /**
     * Called when the user activates the sidebar icon.
     */
    onSidebar: () => void;
    /**
     * Called when the user activates the upload button.
     */
    onUpload: () => void;
};

const NormalNavbarContents: React.FC<NormalNavbarContentsProps> = ({
    onSidebar,
    onUpload,
    ...props
}) => (
    <>
        {!props.isInSearchMode && <SidebarButton onClick={onSidebar} />}
        <SearchBar {...props} />
        {!props.isInSearchMode && <UploadButton onClick={onUpload} />}
    </>
);

const SidebarButton: React.FC<ButtonishProps> = ({ onClick }) => (
    <IconButton {...{ onClick }}>
        <MenuIcon />
    </IconButton>
);

const UploadButton: React.FC<ButtonishProps> = ({ onClick }) => {
    const disabled = uploadManager.isUploadInProgress();
    const isSmallWidth = useIsSmallWidth();

    const icon = <HugeiconsIcon icon={Upload01Icon} size={20} />;

    return (
        <>
            {isSmallWidth ? (
                <IconButton {...{ onClick, disabled }}>{icon}</IconButton>
            ) : (
                <FocusVisibleButton
                    color="secondary"
                    startIcon={icon}
                    sx={{ borderRadius: "16px" }}
                    {...{ onClick, disabled }}
                >
                    {t("upload")}
                </FocusVisibleButton>
            )}
        </>
    );
};

interface SectionNavbarContentsProps {
    title: string;
    onBack: () => void;
    onUpload: () => void;
}

const SectionNavbarContents: React.FC<SectionNavbarContentsProps> = ({
    title,
    onBack,
    onUpload,
}) => (
    <Stack
        direction="row"
        sx={(theme) => ({
            gap: "24px",
            flex: 1,
            alignItems: "center",
            background: theme.vars.palette.background.default,
        })}
    >
        <IconButton onClick={onBack}>
            <ArrowBackIcon />
        </IconButton>
        <Typography sx={{ flex: 1 }}>{title}</Typography>
        <UploadButton onClick={onUpload} />
    </Stack>
);

/**
 * When the payments app redirects back to us after a plan purchase or update
 * completes, it sets various query parameters to relay the status of the action
 * back to us.
 *
 * Check if these query parameters exist, and if so, act on them appropriately.
 */
const handleSubscriptionCompletionRedirectIfNeeded = async (
    showMiniDialog: (attributes: MiniDialogAttributes) => void,
    showLoadingBar: () => void,
    router: NextRouter,
) => {
    const { session_id: sessionID, status, reason } = router.query;

    if (status == "success") {
        try {
            const subscription = await verifyStripeSubscription(sessionID);
            showMiniDialog({
                title: t("thank_you"),
                message: (
                    <Trans
                        i18nKey="subscription_purchase_success"
                        values={{ date: subscription.expiryTime }}
                    />
                ),
                continue: { text: t("ok") },
                cancel: false,
            });
        } catch (e) {
            log.error("Subscription verification failed", e);
            showMiniDialog(
                errorDialogAttributes(t("subscription_verification_error")),
            );
        }
    } else if (status == "fail") {
        log.error(`Subscription purchase failed`, reason);
        switch (reason) {
            case "canceled":
                showMiniDialog({
                    message: t("subscription_purchase_cancelled"),
                    continue: { text: t("ok"), color: "primary" },
                    cancel: false,
                });
                break;
            case "requires_payment_method":
                showMiniDialog({
                    title: t("update_payment_method"),
                    message: t("update_payment_method_message"),
                    continue: {
                        text: t("update_payment_method"),
                        action: () => {
                            showLoadingBar();
                            return redirectToCustomerPortal();
                        },
                    },
                });
                break;
            case "authentication_failed":
                showMiniDialog({
                    title: t("update_payment_method"),
                    message: t("payment_method_authentication_failed"),
                    continue: {
                        text: t("update_payment_method"),
                        action: () => {
                            showLoadingBar();
                            return redirectToCustomerPortal();
                        },
                    },
                });
                break;
            default:
                showMiniDialog(
                    errorDialogAttributes(t("subscription_purchase_failed")),
                );
        }
    }
};

const createAppDownloadFooter = (): FileListHeaderOrFooter => ({
    component: (
        <Typography
            variant="small"
            sx={{
                alignSelf: "flex-end",
                marginInline: "auto",
                marginBlock: 0.75,
                textAlign: "center",
                color: "text.faint",
            }}
        >
            <Trans
                i18nKey={"install_mobile_app"}
                components={{
                    a: (
                        <Link
                            href="https://play.google.com/store/apps/details?id=io.ente.photos"
                            target="_blank"
                            rel="noopener"
                        />
                    ),
                    b: (
                        <Link
                            href="https://apps.apple.com/in/app/ente-photos/id1542026904"
                            target="_blank"
                            rel="noopener"
                        />
                    ),
                }}
            />
        </Typography>
    ),
    height: 90,
});
