import { CollectionMapDialog } from "@/components/Collections/CollectionMapDialog";
import { uploadManager } from "@/services/upload-manager";
import { IconButton, Tooltip, styled } from "@mui/material";
import { useColorScheme, useTheme } from "@mui/material/styles";
import { useModalVisibility } from "ente-base/components/utils/modal";
import { useBaseContext } from "ente-base/context";
import { isSameDay } from "ente-base/date";
import { formattedDate } from "ente-base/i18n-date";
import type { AddSaveGroup } from "ente-gallery/components/utils/save-groups";
import {
    FileViewer,
    type FileViewerInitialSidebar,
    type FileViewerProps,
} from "ente-gallery/components/viewer/FileViewer";
import { downloadAndSaveFiles } from "ente-gallery/services/save";
import type { Collection } from "ente-media/collection";
import type { EnteFile } from "ente-media/file";
import { fileCreationPhotoDate, fileFileName } from "ente-media/file-metadata";
import type { RemotePullOpts } from "ente-new/photos/components/gallery";
import { useSettingsSnapshot } from "ente-new/photos/components/utils/use-snapshot";
import { moveToTrash } from "ente-new/photos/services/collection";
import type { CollectionSummary } from "ente-new/photos/services/collection-summary";
import { PseudoCollectionID } from "ente-new/photos/services/collection-summary";
import { updateMapEnabled } from "ente-new/photos/services/settings";
import { usePhotosAppContext } from "ente-new/photos/types/context";
import { t } from "i18next";
import { useCallback, useEffect, useMemo, useState } from "react";
import AutoSizer from "react-virtualized-auto-sizer";
import {
    FileList,
    type FileListAnnotatedFile,
    type FileListProps,
} from "./FileList";

export type FileListWithViewerProps = {
    /**
     * The list of files to show.
     */
    files: EnteFile[];
    /**
     * Additional source data for deriving Map View files. Defaults to using
     * {@link files} directly.
     */
    mapFileSource?: {
        collectionFiles: EnteFile[];
        favoriteFileIDs: Set<number>;
        hiddenFileIDs: Set<number>;
        archivedFileIDs: Set<number>;
        tempDeletedFileIDs: Set<number>;
        tempHiddenFileIDs: Set<number>;
    };
    enableDownload?: boolean;
    enableImageEditing?: boolean;
    /**
     * Called when the component wants to mark the given files as deleted in the
     * the in-memory, unsynced, state maintained by the top level gallery.
     *
     * For more details, see {@link unsyncedFavoriteUpdates} in the gallery
     * reducer's documentation.
     */
    onMarkTempDeleted?: (files: EnteFile[]) => void;
    /**
     * Called when the visibility of the file viewer dialog changes.
     */
    onSetOpenFileViewer?: (open: boolean) => void;
    /**
     * Called when an action in the file viewer requires us to perform a full
     * pull from remote.
     */
    onRemotePull: (opts?: RemotePullOpts) => Promise<void>;
    activeCollectionSummary?: CollectionSummary;
    activeCollection?: Collection;
    /**
     * If set, the file viewer will open to this file index on mount/update.
     * Set to undefined after the navigation is complete.
     */
    pendingFileIndex?: number;
    /**
     * The sidebar to open when navigating to a file from feed.
     */
    pendingFileSidebar?: FileViewerInitialSidebar;
    /**
     * The comment ID to highlight when navigating from feed.
     */
    pendingHighlightCommentID?: string;
    /**
     * Called after the pending navigation is consumed.
     */
    onPendingNavigationConsumed?: () => void;
    /**
     * A function that can be used to create a UI notification to track the
     * progress of user-initiated download, and to cancel it if needed.
     */
    onAddSaveGroup: AddSaveGroup;

    onAddFileToCollection?: (
        file: EnteFile,
        sourceCollectionSummaryID?: number,
    ) => void;
    /**
     * Called when the list scrolls, providing the current scroll offset.
     */
    onScroll?: (scrollOffset: number) => void;
    /**
     * Called when the visible date at the top of the viewport changes.
     */
    onVisibleDateChange?: (date: string | undefined) => void;
} & Pick<
    FileListProps,
    | "mode"
    | "modePlus"
    | "header"
    | "footer"
    | "disableGrouping"
    | "enableSelect"
    | "selected"
    | "setSelected"
    | "activeCollectionID"
    | "activePersonID"
    | "favoriteFileIDs"
    | "emailByUserID"
    | "listBorderRadius"
    | "onContextMenuAction"
    | "onContextMenuOpenChange"
    | "showAddPersonAction"
    | "showEditLocationAction"
    | "suppressSelectionUI"
> &
    Pick<
        FileViewerProps,
        | "user"
        | "isInIncomingSharedCollection"
        | "isInHiddenSection"
        | "fileNormalCollectionIDs"
        | "fileCollectionIDs"
        | "hiddenCollectionIDs"
        | "collectionSummaries"
        | "collectionNameByID"
        | "pendingFavoriteUpdates"
        | "pendingVisibilityUpdates"
        | "onRemoteFilesPull"
        | "onVisualFeedback"
        | "onToggleFavorite"
        | "onFileVisibilityUpdate"
        | "onSendLink"
        | "onSelectCollection"
        | "onSelectPerson"
    >;

/**
 * A list of files (represented by their thumbnails), along with a file viewer
 * that opens on activating the thumbnail (and also allows the user to navigate
 * through this list of files).
 */
export const FileListWithViewer: React.FC<FileListWithViewerProps> = ({
    mode,
    modePlus,
    header,
    footer,
    user,
    files,
    enableDownload,
    enableImageEditing = true,
    disableGrouping,
    enableSelect,
    selected,
    setSelected,
    activeCollectionID,
    activePersonID,
    activeCollectionSummary,
    activeCollection,
    favoriteFileIDs,
    emailByUserID,
    listBorderRadius,
    onContextMenuAction,
    onContextMenuOpenChange,
    showAddPersonAction,
    showEditLocationAction,
    suppressSelectionUI,
    isInIncomingSharedCollection,
    isInHiddenSection,
    fileNormalCollectionIDs,
    fileCollectionIDs,
    hiddenCollectionIDs,
    collectionSummaries,
    collectionNameByID,
    pendingFavoriteUpdates,
    pendingVisibilityUpdates,
    onSetOpenFileViewer,
    onRemotePull,
    onRemoteFilesPull,
    onVisualFeedback,
    onAddSaveGroup,
    onToggleFavorite,
    onFileVisibilityUpdate,
    onSendLink,
    onMarkTempDeleted,
    onSelectCollection,
    onSelectPerson,
    onAddFileToCollection,
    onScroll,
    onVisibleDateChange,
    pendingFileIndex,
    pendingFileSidebar,
    pendingHighlightCommentID,
    onPendingNavigationConsumed,
    mapFileSource,
}) => {
    const [openFileViewer, setOpenFileViewer] = useState(false);
    const [currentIndex, setCurrentIndex] = useState(0);
    const [initialSidebar, setInitialSidebar] = useState<
        FileViewerInitialSidebar | undefined
    >(undefined);
    const [highlightCommentID, setHighlightCommentID] = useState<
        string | undefined
    >(undefined);
    const { show: showMapDialog, props: mapDialogVisibilityProps } =
        useModalVisibility();
    const { onGenericError } = useBaseContext();
    const { showNotification } = usePhotosAppContext();
    const { mapEnabled } = useSettingsSnapshot();
    const { mode: colorSchemeMode, systemMode } = useColorScheme();
    const theme = useTheme();
    const resolvedMode =
        colorSchemeMode === "system"
            ? systemMode
            : (colorSchemeMode ?? theme.palette.mode);
    const isDarkMode = resolvedMode === "dark";

    // Handle pending navigation from feed item clicks
    useEffect(() => {
        if (pendingFileIndex !== undefined) {
            setCurrentIndex(pendingFileIndex);
            setInitialSidebar(pendingFileSidebar);
            setHighlightCommentID(pendingHighlightCommentID);
            setOpenFileViewer(true);
            onSetOpenFileViewer?.(true);
            onPendingNavigationConsumed?.();
        }
    }, [
        pendingFileIndex,
        pendingFileSidebar,
        pendingHighlightCommentID,
        onSetOpenFileViewer,
        onPendingNavigationConsumed,
    ]);

    // Clear initial sidebar state when file viewer closes
    const handleCloseFileViewerInternal = useCallback(() => {
        setInitialSidebar(undefined);
        setHighlightCommentID(undefined);
        onSetOpenFileViewer?.(false);
        setOpenFileViewer(false);
    }, [onSetOpenFileViewer]);

    const annotatedFiles = useMemo(
        (): FileListAnnotatedFile[] =>
            files.map((file) => ({
                file,
                timelineDateString: fileTimelineDateString(file),
            })),
        [files],
    );

    const handleThumbnailClick = useCallback(
        (index: number) => {
            setCurrentIndex(index);
            setOpenFileViewer(true);
            onSetOpenFileViewer?.(true);
        },
        [onSetOpenFileViewer],
    );

    const handleTriggerRemotePull = useCallback(
        () => void onRemotePull({ source: "file-viewer-action" }),
        [onRemotePull],
    );

    const handleDownload = useCallback(
        (file: EnteFile) =>
            downloadAndSaveFiles([file], fileFileName(file), onAddSaveGroup),
        [onAddSaveGroup],
    );

    const handleDelete = useMemo(() => {
        return onMarkTempDeleted
            ? (file: EnteFile) =>
                  moveToTrash([file]).then(() => onMarkTempDeleted([file]))
            : undefined;
    }, [onMarkTempDeleted]);

    const handleSaveEditedImageCopy = useMemo(() => {
        if (!enableImageEditing) return undefined;
        return (
            editedFile: File,
            collection: Collection,
            enteFile: EnteFile,
        ) => {
            if (uploadManager.isUploadInProgress()) {
                showNotification({
                    color: "critical",
                    title: t("wait_for_active_upload_to_finish"),
                });
                return false;
            }
            uploadManager.prepareForNewUpload();
            uploadManager.showUploadProgressDialog();
            void uploadManager.uploadFile(editedFile, collection, enteFile);
            return true;
        };
    }, [enableImageEditing, showNotification]);

    const shouldShowMapButton =
        modePlus !== "search" &&
        activeCollectionSummary?.type === "all" &&
        (activeCollectionSummary.fileCount > 0 || files.length > 0);

    const handleShowMap = useCallback(async () => {
        if (!activeCollectionSummary) return;
        if (!mapEnabled) {
            try {
                await updateMapEnabled(true);
            } catch (e) {
                onGenericError(e);
                return;
            }
        }
        showMapDialog();
    }, [activeCollectionSummary, mapEnabled, onGenericError, showMapDialog]);

    const headerWithMap = useMemo(() => {
        if (!shouldShowMapButton || !header) return header;
        return {
            ...header,
            component: (
                <HeaderWithMap>
                    <HeaderMain>{header.component}</HeaderMain>
                    <Tooltip title={t("map")}>
                        <IconButton
                            className="map-button"
                            size="small"
                            aria-label={t("map")}
                            onClick={handleShowMap}
                        >
                            <MapIcon
                                src="/images/gallery-globe/globe.svg"
                                alt=""
                                aria-hidden
                                $isDarkMode={isDarkMode}
                            />
                        </IconButton>
                    </Tooltip>
                </HeaderWithMap>
            ),
        };
    }, [header, handleShowMap, isDarkMode, shouldShowMapButton]);

    return (
        <Container>
            <AutoSizer>
                {({ height, width }) => (
                    <FileList
                        {...{ width, height, annotatedFiles }}
                        {...{
                            mode,
                            modePlus,
                            header: headerWithMap,
                            footer,
                            user,
                            disableGrouping,
                            enableSelect,
                            selected,
                            setSelected,
                            activeCollectionID,
                            activePersonID,
                            favoriteFileIDs,
                            emailByUserID,
                            listBorderRadius,
                            onScroll,
                            onVisibleDateChange,
                            collectionSummary: activeCollectionSummary,
                            onContextMenuAction,
                            onContextMenuOpenChange,
                            showAddPersonAction,
                            showEditLocationAction,
                            suppressSelectionUI,
                        }}
                        onItemClick={handleThumbnailClick}
                    />
                )}
            </AutoSizer>
            <FileViewer
                open={openFileViewer}
                onClose={handleCloseFileViewerInternal}
                initialIndex={currentIndex}
                initialSidebar={initialSidebar}
                highlightCommentID={highlightCommentID}
                disableDownload={!enableDownload}
                isInTrashSection={
                    activeCollectionID == PseudoCollectionID.trash
                }
                {...{
                    user,
                    files,
                    isInHiddenSection,
                    isInIncomingSharedCollection,
                    favoriteFileIDs,
                    fileNormalCollectionIDs,
                    fileCollectionIDs,
                    hiddenCollectionIDs,
                    collectionSummaries,
                    collectionNameByID,
                    pendingFavoriteUpdates,
                    pendingVisibilityUpdates,
                    onRemoteFilesPull,
                    onVisualFeedback,
                    onToggleFavorite,
                    onFileVisibilityUpdate,
                    onSendLink,
                    onSelectCollection,
                    onSelectPerson,
                }}
                isCommentsFeatureEnabled
                onTriggerRemotePull={handleTriggerRemotePull}
                onDownload={handleDownload}
                onDelete={handleDelete}
                onSaveEditedImageCopy={handleSaveEditedImageCopy}
                onAddFileToCollection={onAddFileToCollection}
                activeCollectionID={activeCollectionID}
            />
            {shouldShowMapButton && (
                <CollectionMapDialog
                    {...mapDialogVisibilityProps}
                    collectionSummary={activeCollectionSummary}
                    activeCollection={activeCollection}
                    files={files}
                    mapFileSource={mapFileSource}
                    onRemotePull={onRemotePull}
                    {...{
                        onAddSaveGroup,
                        onMarkTempDeleted,
                        onAddFileToCollection,
                        onRemoteFilesPull,
                        onVisualFeedback,
                        fileNormalCollectionIDs,
                        collectionNameByID,
                        emailByUserID,
                        onSelectCollection,
                        onSelectPerson,
                    }}
                />
            )}
        </Container>
    );
};

const Container = styled("div")`
    flex: 1;
    width: 100%;
`;

const HeaderWithMap = styled("div")`
    display: flex;
    align-items: center;
    justify-content: flex-start;
    gap: 12px;
    width: 100%;
    & > .map-button {
        flex-shrink: 0;
        margin-left: auto;
    }
`;

const HeaderMain = styled("div")`
    flex: 1;
    min-width: 0;
`;

const MapIcon = styled("img")<{ $isDarkMode: boolean }>(
    ({ theme, $isDarkMode }) => ({
        display: "block",
        width: 24,
        height: 24,
        filter:
            $isDarkMode || theme.palette.mode === "dark" ? "invert(1)" : "none",
    }),
);

/**
 * See: [Note: Timeline date string]
 */
const fileTimelineDateString = (file: EnteFile) => {
    const date = fileCreationPhotoDate(file);
    return isSameDay(date, new Date())
        ? t("today")
        : isSameDay(date, new Date(Date.now() - 24 * 60 * 60 * 1000))
          ? t("yesterday")
          : formattedDate(date);
};
