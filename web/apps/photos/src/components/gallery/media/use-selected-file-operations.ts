import type { FixCreationTime } from "@/components/FixCreationTime";
import type { FileOp } from "@/components/SelectedFileOptions";
import { useFileMutations } from "@/components/gallery/media/use-file-mutations";
import {
    notifyOthersFilesDialogAttributes,
    notifyUnsupportedSharedFavoritesDialogAttributes,
    trashFilesDialogAttributes,
} from "@/components/utils/dialog-attributes";
import {
    selectedFavoriteCount as countSelectedFavorites,
    getSelectedFiles,
    performFileOp,
    type SelectedState,
} from "@/utils/file";
import { CheckmarkCircle02Icon } from "@hugeicons/core-free-icons";
import { useModalVisibility } from "ente-base/components/utils/modal";
import { useBaseContext } from "ente-base/context";
import type { Location } from "ente-base/types";
import { useSaveGroups } from "ente-gallery/components/utils/save-groups";
import {
    quickLinkNameForFiles,
    resolveQuickLinkURL,
} from "ente-gallery/utils/quick-link";
import type { EnteFile } from "ente-media/file";
import { ItemVisibility } from "ente-media/file-metadata";
import type { AssignPersonDialog } from "ente-new/photos/components/AssignPersonDialog";
import type { EditLocationDialog } from "ente-new/photos/components/EditLocationDialog";
import { useSettingsSnapshot } from "ente-new/photos/components/utils/use-snapshot";
import {
    addToCollection,
    createPublicURL,
    createQuickLinkCollection,
} from "ente-new/photos/services/collection";
import { updateFilesLocation } from "ente-new/photos/services/file";
import {
    addManualFileAssignmentsToPerson,
    isMLEnabled,
} from "ente-new/photos/services/ml";
import type { PeopleState } from "ente-new/photos/services/ml/people";
import { usePhotosAppContext } from "ente-new/photos/types/context";
import { t } from "i18next";
import type { ComponentProps, Dispatch } from "react";
import { useCallback, useMemo, useState } from "react";
import type { RemotePullOpts } from "..";
import type { GalleryAction, GalleryState } from "../reducer";
export const useSelectedFileOperations = ({
    state,
    dispatch,
    peopleState,
    selected,
    filteredFiles,
    quickLinkVisibility,
    clearSelection,
    onAddSaveGroup,
    remotePull,
    mutations,
}: {
    state: GalleryState;
    dispatch: Dispatch<GalleryAction>;
    peopleState: PeopleState | undefined;
    selected: SelectedState;
    filteredFiles: EnteFile[];
    quickLinkVisibility: ItemVisibility;
    clearSelection: () => void;
    onAddSaveGroup: ReturnType<typeof useSaveGroups>["onAddSaveGroup"];
    remotePull: (opts?: RemotePullOpts) => Promise<void>;
    mutations: Pick<
        ReturnType<typeof useFileMutations>,
        | "setPublicLinkToast"
        | "handleFavoriteFileOp"
        | "onSendLinkError"
        | "handleMarkTempDeleted"
    >;
}) => {
    const { user, favoriteFileIDs } = state;
    const { customDomain } = useSettingsSnapshot();
    const { showMiniDialog, onGenericError } = useBaseContext();
    const { showLoadingBar, hideLoadingBar, showNotification } =
        usePhotosAppContext();
    const {
        setPublicLinkToast,
        handleFavoriteFileOp,
        onSendLinkError,
        handleMarkTempDeleted,
    } = mutations;
    const selectedFilesInView = useMemo(
        () => getSelectedFiles(selected, filteredFiles),
        [selected, filteredFiles],
    );
    const [suppressContextSelectionBar, setSuppressContextSelectionBar] =
        useState(false);
    const [fixCreationTimeFiles, setFixCreationTimeFiles] = useState<
        EnteFile[]
    >([]);
    const { show: openAssignPerson, props: contextMenuAssignPersonProps } =
        useModalVisibility();
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
    const { show: showFixCreationTime, props: fixCreationTimeVisibilityProps } =
        useModalVisibility();
    const { show: openEditLocation, props: editLocationVisibilityProps } =
        useModalVisibility();
    const [personSelection, setPersonSelection] = useState<{
        files: EnteFile[];
        clear: () => void;
    }>();
    const [editLocationFiles, setEditLocationFiles] = useState<EnteFile[]>([]);
    const showContextMenuAssignPerson = useCallback(() => {
        setPersonSelection({
            files: selectedFilesInView,
            clear: clearSelection,
        });
        openAssignPerson();
    }, [selectedFilesInView, clearSelection, openAssignPerson]);
    const showEditLocation = useCallback(() => {
        setEditLocationFiles(selectedFilesInView);
        openEditLocation();
    }, [selectedFilesInView, openEditLocation]);
    const createFileOpHandler = useCallback(
        (op: FileOp, options?: { suppressSelectionBar?: boolean }) => () => {
            return (async () => {
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
                            (file) => file.ownerID == user!.id,
                        );
                        if (!ownedSelectedFiles.length) return;
                        if (ownedSelectedFiles.length != selectedFiles.length) {
                            showMiniDialog(notifyOthersFilesDialogAttributes());
                        }

                        const quickLinkCollection =
                            await createQuickLinkCollection(
                                quickLinkNameForFiles(ownedSelectedFiles),
                                quickLinkVisibility,
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

                    // Hide every non-hidden copy, including copies outside this view.
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

                    if (
                        op != "download" &&
                        ownedSelectedFiles.length != selectedFiles.length
                    ) {
                        showMiniDialog(notifyOthersFilesDialogAttributes());
                    }
                    clearSelection();
                    await remotePull({ silent: true, source: `file-op:${op}` });
                } catch (e) {
                    if (op == "trash") {
                        throw e;
                    } else if (op == "sendLink") {
                        onSendLinkError(e);
                    } else {
                        onGenericError(e);
                    }
                } finally {
                    if (options?.suppressSelectionBar) {
                        setSuppressContextSelectionBar(false);
                    }
                    hideLoadingBar();
                }
            })();
        },
        [
            selected,
            filteredFiles,
            quickLinkVisibility,
            user,
            showMiniDialog,
            showLoadingBar,
            hideLoadingBar,
            customDomain,
            setPublicLinkToast,
            clearSelection,
            remotePull,
            state.collectionFiles,
            state.hiddenFileIDs,
            handleFavoriteFileOp,
            onAddSaveGroup,
            handleMarkTempDeleted,
            dispatch,
            showFixCreationTime,
            onSendLinkError,
            onGenericError,
        ],
    );
    const handleAddPersonToSelectedFiles = useCallback(
        async (personID: string) => {
            showLoadingBar();
            try {
                const selectedFiles = personSelection?.files ?? [];
                await addManualFileAssignmentsToPerson(
                    personID,
                    selectedFiles.map((f) => f.id),
                );
                personSelection?.clear();
                const personName = namedPeople.find(
                    (p) => p.id === personID,
                )?.name;
                showNotification({
                    color: "secondary",
                    startIcon: CheckmarkCircle02Icon,
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
            personSelection,
            showNotification,
            namedPeople,
            showLoadingBar,
            hideLoadingBar,
            onGenericError,
        ],
    );
    const handleContextMenuSelectPerson = useCallback(
        (personID: string) => {
            contextMenuAssignPersonProps.onClose();
            void handleAddPersonToSelectedFiles(personID);
        },
        [contextMenuAssignPersonProps, handleAddPersonToSelectedFiles],
    );
    const handleEditLocationConfirm = useCallback(
        async (location: Location) => {
            const userFiles = editLocationFiles.filter(
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
        [editLocationFiles, user, remotePull],
    );
    const selectedCount = selected.count;
    const selectedOwnCount = selected.ownCount;
    const handleDeleteFiles = useCallback(
        (suppressSelectionBar = false) => {
            if (selectedOwnCount === 0) return;
            showMiniDialog(
                trashFilesDialogAttributes(
                    selectedOwnCount,
                    createFileOpHandler("trash", { suppressSelectionBar }),
                ),
            );
        },
        [selectedOwnCount, createFileOpHandler, showMiniDialog],
    );
    const selectedFavoriteCount = useMemo(
        () => countSelectedFavorites(selected, favoriteFileIDs),
        [favoriteFileIDs, selected],
    );
    const fixCreationTimeProps: ComponentProps<typeof FixCreationTime> = {
        ...fixCreationTimeVisibilityProps,
        files: fixCreationTimeFiles,
        onRemotePull: remotePull,
    };
    const assignPersonDialogProps: ComponentProps<typeof AssignPersonDialog> = {
        ...contextMenuAssignPersonProps,
        people: namedPeople,
        title: t("add_a_person"),
        onSelectPerson: handleContextMenuSelectPerson,
    };
    const editLocationDialogProps: ComponentProps<typeof EditLocationDialog> = {
        ...editLocationVisibilityProps,
        files: editLocationFiles,
        onConfirm: handleEditLocationConfirm,
    };
    return {
        suppressContextSelectionBar,
        showAddPersonAction,
        fixCreationTimeVisibilityProps,
        showEditLocation,
        showContextMenuAssignPerson,
        createFileOpHandler,
        handleDeleteFiles,
        selectedFavoriteCount,
        selectedCount,
        selectedOwnCount,
        fixCreationTimeProps,
        assignPersonDialogProps,
        editLocationDialogProps,
    };
};
