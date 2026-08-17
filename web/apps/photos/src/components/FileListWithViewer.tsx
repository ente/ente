import type { RemotePullOpts } from "@/components/gallery";
import { downloadAndSaveFiles } from "@/services/save";
import { uploadManager } from "@/services/upload-manager";
import { fileTimelineDateString } from "@/utils/file";
import { IconButton, Tooltip, styled } from "@mui/material";
import { useColorScheme, useTheme } from "@mui/material/styles";
import type { AddSaveGroup } from "ente-gallery/components/utils/save-groups";
import {
    FileViewer,
    type FileViewerInitialSidebar,
    type FileViewerProps,
} from "ente-gallery/components/viewer/FileViewer";
import type { Collection } from "ente-media/collection";
import type { EnteFile } from "ente-media/file";
import { fileFileName } from "ente-media/file-metadata";
import { moveToTrash } from "ente-new/photos/services/collection";
import type { CollectionSummary } from "ente-new/photos/services/collection-summary";
import { PseudoCollectionID } from "ente-new/photos/services/collection-summary";
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
    files: EnteFile[];
    onShowMap?: () => void;
    enableDownload?: boolean;
    enableImageEditing?: boolean;
    onMarkTempDeleted?: (files: EnteFile[]) => void;
    onSetOpenFileViewer?: (open: boolean) => void;
    onRemotePull: (opts?: RemotePullOpts) => Promise<void>;
    activeCollectionSummary?: CollectionSummary;
    pendingFileIndex?: number;
    pendingFileSidebar?: FileViewerInitialSidebar;
    pendingHighlightCommentID?: string;
    onPendingNavigationConsumed?: () => void;
    onAddSaveGroup: AddSaveGroup;

    onAddFileToCollection?: (
        file: EnteFile,
        sourceCollectionSummaryID?: number,
    ) => void;
    onScroll?: (scrollOffset: number) => void;
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
    onShowMap,
}) => {
    const [openFileViewer, setOpenFileViewer] = useState(false);
    const [currentIndex, setCurrentIndex] = useState(0);
    const [initialSidebar, setInitialSidebar] = useState<
        FileViewerInitialSidebar | undefined
    >(undefined);
    const [highlightCommentID, setHighlightCommentID] = useState<
        string | undefined
    >(undefined);
    const { showNotification } = usePhotosAppContext();
    const { mode: colorSchemeMode, systemMode } = useColorScheme();
    const theme = useTheme();
    const resolvedMode =
        colorSchemeMode === "system"
            ? systemMode
            : (colorSchemeMode ?? theme.palette.mode);
    const isDarkMode = resolvedMode === "dark";

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
        !!onShowMap &&
        modePlus !== "search" &&
        activeCollectionSummary?.type === "all" &&
        (activeCollectionSummary.fileCount > 0 || files.length > 0);

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
                            onClick={onShowMap}
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
    }, [header, isDarkMode, onShowMap, shouldShowMapButton]);

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
