import type { FileListHeaderOrFooter } from "@/components/FileList";
import { FileListWithViewer } from "@/components/FileListWithViewer";
import { SelectedFileOptions } from "@/components/SelectedFileOptions";
import { externalLink } from "@/utils/link";
import { Box, Typography } from "@mui/material";
import { ItemVisibility } from "ente-media/file-metadata";
import { useCollectionOperations } from "./hooks/use-collection-operations";
import { useFileContextActions } from "./hooks/use-file-context-actions";
import { useGallerySelection } from "./hooks/use-gallery-selection";
import { useSelectedFileOperations } from "./hooks/use-selected-file-operations";
import { useSelectionShortcuts } from "./hooks/use-selection-shortcuts";
import type { GalleryMediaSource } from "./section-types";

import {
    useCallback,
    useEffect,
    useMemo,
    useRef,
    useState,
    type ReactNode,
} from "react";
import { Trans } from "react-i18next";

import type { GallerySectionProps } from "./section-types";
type GalleryMediaProps = Pick<
    GallerySectionProps,
    "library" | "operations" | "navigation"
> & {
    source: GalleryMediaSource;
    header?: FileListHeaderOrFooter;
    children?: (hasSelection: boolean) => ReactNode;
};

export const GalleryMedia = (props: GalleryMediaProps) => {
    const { source, navigation } = props;
    const scope = JSON.stringify([
        source.mode,
        source.modePlus,
        source.activeCollectionID,
        source.activePersonID,
        navigation.overlay?.suggestion?.type,
        navigation.overlay?.suggestion?.label,
    ]);
    return <GalleryMediaContent key={scope} {...props} />;
};

const GalleryMediaContent = ({
    library,
    operations,
    navigation,
    source,
    header,
    children,
}: GalleryMediaProps) => {
    const { selected, setSelected, clearSelection } = useGallerySelection(
        source.files,
        library.user?.id,
    );
    const [isContextMenuOpen, setIsContextMenuOpen] = useState(false);
    const [isFileViewerOpen, setIsFileViewerOpen] = useState(false);
    const viewerOpen = useRef(false);
    const onSetOpenFileViewer = useCallback((open: boolean) => {
        viewerOpen.current = open;
        setIsFileViewerOpen(open);
    }, []);
    useEffect(
        () => () => {
            if (viewerOpen.current && document.fullscreenElement)
                void document.exitFullscreen();
        },
        [],
    );
    const collectionActions = useCollectionOperations({
        state: library,
        selected,
        filteredFiles: source.files,
        barMode: source.mode ?? "albums",
        clearSelection,
        remotePull: operations.onRemotePull,
    });
    const fileActions = useSelectedFileOperations({
        state: library,
        dispatch: operations.dispatch,
        peopleState: operations.peopleState,
        selected,
        filteredFiles: source.files,
        quickLinkVisibility:
            source.mode === "hidden-albums"
                ? ItemVisibility.hidden
                : ItemVisibility.visible,
        clearSelection,
        onAddSaveGroup: operations.onAddSaveGroup,
        remotePull: operations.onRemotePull,
        mutations: operations.mutations,
    });
    const isSearch = source.modePlus === "search";
    const onContextMenuAction = useFileContextActions({
        collectionOperations: collectionActions,
        selectedOperations: fileActions,
        activeCollection: isSearch ? undefined : source.activeCollection,
        activeCollectionSummary: isSearch
            ? undefined
            : source.activeCollectionSummary,
        barMode: source.mode ?? "albums",
    });
    const selectAll = useSelectionShortcuts({
        source,
        userID: library.user?.id,
        setSelected,
        clearSelection,
        disabled: operations.selectionDisabled || isFileViewerOpen,
    });
    const showSelectionBar =
        selected.count > 0 &&
        !fileActions.suppressContextSelectionBar &&
        !(isContextMenuOpen && selected.count === 1);
    const fileCollectionIDs = useMemo(
        () =>
            library.collectionFiles.reduce((result, file) => {
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
        [library.collectionFiles],
    );

    const showAppDownloadFooter =
        library.collectionFiles.length < 30 &&
        navigation.overlay?.section !== "search";
    const footer = useMemo(
        () => (showAppDownloadFooter ? createAppDownloadFooter() : undefined),
        [showAppDownloadFooter],
    );
    return (
        <>
            {showSelectionBar && (
                <Box
                    role="toolbar"
                    aria-label="Selected file actions"
                    sx={{
                        flexShrink: 0,
                        display: "flex",
                        mx: { xs: 1, md: 2 },
                        pb: 1.5,
                        mb: 1.5,
                        borderBottom: 1,
                        borderColor: "divider",
                    }}
                >
                    <SelectedFileOptions
                        barMode={source.mode}
                        isInSearchMode={isSearch}
                        collection={
                            isSearch ? undefined : source.activeCollection
                        }
                        collectionSummary={
                            isSearch
                                ? undefined
                                : source.activeCollectionSummary
                        }
                        selectedFileCount={selected.count}
                        selectedOwnFileCount={selected.ownCount}
                        selectedFavoriteCount={
                            fileActions.selectedFavoriteCount
                        }
                        onClearSelection={clearSelection}
                        onDelete={() => fileActions.handleDeleteFiles()}
                        onRemoveFilesFromCollection={
                            collectionActions.handleRemoveFilesFromCollection
                        }
                        onOpenCollectionSelector={
                            collectionActions.handleOpenCollectionSelector
                        }
                        createOnCreateForCollectionOp={
                            collectionActions.createOnCreateForCollectionOp
                        }
                        createOnSelectForCollectionOp={
                            collectionActions.createOnSelectForCollectionOp
                        }
                        createFileOpHandler={fileActions.createFileOpHandler}
                        onShowAssignPersonDialog={
                            fileActions.showAddPersonAction
                                ? fileActions.showContextMenuAssignPerson
                                : undefined
                        }
                        onEditLocation={fileActions.showEditLocation}
                        onSelectAll={selectAll}
                        isAllSelected={
                            source.files.length > 0 &&
                            selected.count === source.files.length
                        }
                    />
                </Box>
            )}
            {children?.(selected.count > 0)}
            <FileListWithViewer
                {...operations}
                {...source}
                selected={selected}
                setSelected={setSelected}
                onContextMenuAction={onContextMenuAction}
                onContextMenuOpenChange={setIsContextMenuOpen}
                suppressSelectionUI={fileActions.suppressContextSelectionBar}
                showAddPersonAction={fileActions.showAddPersonAction}
                onSetOpenFileViewer={onSetOpenFileViewer}
                onAddFileToCollection={
                    collectionActions.handleAddSingleFileToCollection
                }
                user={library.user}
                header={header}
                footer={footer}
                enableDownload
                enableSelect
                isInIncomingSharedCollection={source.activeCollectionSummary?.attributes.has(
                    "sharedIncoming",
                )}
                isInHiddenSection={source.mode == "hidden-albums"}
                showEditLocationAction={selected.ownCount > 0}
                favoriteFileIDs={library.favoriteFileIDs}
                collectionNameByID={library.collectionNameByID}
                fileNormalCollectionIDs={library.fileNormalCollectionIDs}
                fileCollectionIDs={fileCollectionIDs}
                hiddenCollectionIDs={library.hiddenCollectionIDs}
                pendingFavoriteUpdates={library.pendingFavoriteUpdates}
                pendingVisibilityUpdates={library.pendingVisibilityUpdates}
                collectionSummaries={library.normalCollectionSummaries}
                emailByUserID={library.emailByUserID}
                pendingFileIndex={navigation.pendingFileNavigation?.fileIndex}
                pendingFileSidebar={navigation.pendingFileNavigation?.sidebar}
                pendingHighlightCommentID={
                    navigation.pendingFileNavigation?.commentID
                }
            />
            {collectionActions.collectionOperationDialogs}
            {fileActions.selectedFileOperationDialogs}
        </>
    );
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
                i18nKey="install_mobile_app"
                components={{
                    a: externalLink(
                        "https://play.google.com/store/apps/details?id=io.ente.photos",
                    ),
                    b: externalLink(
                        "https://apps.apple.com/in/app/ente-photos/id1542026904",
                    ),
                }}
            />
        </Typography>
    ),
    height: 90,
});
