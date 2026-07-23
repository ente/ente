import {
    CleanIcon,
    Delete02Icon,
    ModernTvIcon,
    RemoveCircleIcon,
} from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import ArchiveOutlinedIcon from "@mui/icons-material/ArchiveOutlined";
import CheckIcon from "@mui/icons-material/Check";
import DeleteOutlinedIcon from "@mui/icons-material/DeleteOutlined";
import EditIcon from "@mui/icons-material/Edit";
import ImageOutlinedIcon from "@mui/icons-material/ImageOutlined";
import LinkIcon from "@mui/icons-material/Link";
import LogoutIcon from "@mui/icons-material/Logout";
import MapOutlinedIcon from "@mui/icons-material/MapOutlined";
import MoreHorizIcon from "@mui/icons-material/MoreHoriz";
import PublicIcon from "@mui/icons-material/Public";
import PushPinIcon from "@mui/icons-material/PushPin";
import PushPinOutlinedIcon from "@mui/icons-material/PushPinOutlined";
import SortIcon from "@mui/icons-material/Sort";
import TvIcon from "@mui/icons-material/Tv";
import UnarchiveIcon from "@mui/icons-material/Unarchive";
import VisibilityOffOutlinedIcon from "@mui/icons-material/VisibilityOffOutlined";
import VisibilityOutlinedIcon from "@mui/icons-material/VisibilityOutlined";
import { Box, IconButton, Menu, Stack, Tooltip } from "@mui/material";
import { SpacedRow } from "ente-base/components/containers";
import { ActivityIndicator } from "ente-base/components/mui/ActivityIndicator";
import {
    OverflowMenu,
    OverflowMenuOption,
} from "ente-base/components/OverflowMenu";
import { SingleInputDialog } from "ente-base/components/SingleInputDialog";
import { useModalVisibility } from "ente-base/components/utils/modal";
import { useBaseContext } from "ente-base/context";
import type { AddSaveGroup } from "ente-gallery/components/utils/save-groups";
import { downloadAndSaveCollectionFiles } from "ente-gallery/services/save";
import { uniqueFilesByID } from "ente-gallery/utils/file";
import {
    CollectionOrder,
    CollectionSubType,
    type Collection,
} from "ente-media/collection";
import type { EnteFile } from "ente-media/file";
import { ItemVisibility } from "ente-media/file-metadata";
import type { RemotePullOpts } from "ente-new/photos/components/gallery";
import {
    GalleryItemsHeaderAdapter,
    GalleryItemsSummary,
} from "ente-new/photos/components/gallery/ListHeader";
import { StarIcon } from "ente-new/photos/components/icons/StarIcon";
import { useSettingsSnapshot } from "ente-new/photos/components/utils/use-snapshot";
import {
    cleanUncategorized,
    defaultHiddenCollectionUserFacingName,
    deleteCollection,
    deleteShareURL,
    findDefaultHiddenCollectionIDs,
    isHiddenCollection,
    leaveSharedCollection,
    renameCollection,
    updateCollectionOrder,
    updateCollectionSortOrder,
    updateCollectionVisibility,
    updateShareeCollectionOrder,
} from "ente-new/photos/services/collection";
import {
    PseudoCollectionID,
    type CollectionSummary,
    type CollectionSummaryType,
} from "ente-new/photos/services/collection-summary";
import {
    savedCollectionFiles,
    savedCollections,
} from "ente-new/photos/services/photos-fdb";
import { updateMapEnabled } from "ente-new/photos/services/settings";
import { emptyTrash } from "ente-new/photos/services/trash";
import { usePhotosAppContext } from "ente-new/photos/types/context";
import { t } from "i18next";
import React, { useCallback, useRef } from "react";
import { Trans } from "react-i18next";
import type { FileListWithViewerProps } from "../FileListWithViewer";
import { CollectionMapDialog } from "./CollectionMapDialog";

export interface CollectionHeaderProps extends Pick<
    FileListWithViewerProps,
    | "onMarkTempDeleted"
    | "onAddFileToCollection"
    | "onRemoteFilesPull"
    | "onVisualFeedback"
    | "fileNormalCollectionIDs"
    | "collectionNameByID"
    | "emailByUserID"
    | "onSelectCollection"
    | "onSelectPerson"
> {
    collectionSummary: CollectionSummary;
    activeCollection: Collection | undefined;
    files: EnteFile[];
    mapFileSource?: FileListWithViewerProps["mapFileSource"];
    setActiveCollectionID: (collectionID: number) => void;
    isActiveCollectionDownloadInProgress: () => boolean;
    /**
     * Called when an operation (e.g. renaming a collection) completes and wants
     * to perform a full remote pull.
     */
    onRemotePull: (opts?: RemotePullOpts) => Promise<void>;
    onCollectionShare: () => void;
    onCollectionManageLink: () => void;
    onCollectionCast: () => void;
    canSetAlbumCover: boolean;
    onSetAlbumCover: () => void;
    hasActiveFileSelection: boolean;
    /**
     * A function that can be used to create a UI notification to track the
     * progress of user-initiated download, and to cancel it if needed.
     */
    onAddSaveGroup: AddSaveGroup;
}

/**
 * A header shown at the top of the list of photos in the gallery, when the
 * gallery is showing a collection.
 */
export const CollectionHeader: React.FC<CollectionHeaderProps> = (props) => {
    const { collectionSummary } = props;

    const { name, type, attributes, fileCount } = collectionSummary;

    const EndIcon = () => {
        if (attributes.has("archived")) return <ArchiveOutlinedIcon />;
        if (attributes.has("sharedOnlyViaLink")) return <LinkIcon />;
        if (attributes.has("shared"))
            return (
                <Box sx={{ mt: "-1px" }}>
                    <SmallShareIcon />
                </Box>
            );
        if (attributes.has("userFavorites"))
            return <StarIcon fontSize="small" />;
        return <></>;
    };

    return (
        <GalleryItemsHeaderAdapter>
            <SpacedRow>
                <GalleryItemsSummary
                    name={name}
                    fileCount={fileCount}
                    endIcon={<EndIcon />}
                />
                {shouldShowOptions(type) && (
                    <CollectionHeaderOptions {...props} />
                )}
            </SpacedRow>
        </GalleryItemsHeaderAdapter>
    );
};

const shouldShowOptions = (type: CollectionSummaryType) =>
    type != "all" && type != "archiveItems";

const CollectionHeaderOptions: React.FC<CollectionHeaderProps> = ({
    activeCollection,
    collectionSummary,
    files,
    mapFileSource,
    setActiveCollectionID,
    onRemotePull,
    onCollectionShare,
    onCollectionManageLink,
    onCollectionCast,
    canSetAlbumCover,
    onSetAlbumCover,
    hasActiveFileSelection,
    onAddSaveGroup,
    isActiveCollectionDownloadInProgress,
    onMarkTempDeleted,
    onAddFileToCollection,
    onRemoteFilesPull,
    onVisualFeedback,
    fileNormalCollectionIDs,
    collectionNameByID,
    emailByUserID,
    onSelectCollection,
    onSelectPerson,
}) => {
    const { showMiniDialog, onGenericError } = useBaseContext();
    const { showLoadingBar, hideLoadingBar, showNotification } =
        usePhotosAppContext();
    const { mapEnabled } = useSettingsSnapshot();
    const overflowMenuIconRef = useRef<SVGSVGElement | null>(null);

    const { show: showSortOrderMenu, props: sortOrderMenuVisibilityProps } =
        useModalVisibility();
    const { show: showAlbumNameInput, props: albumNameInputVisibilityProps } =
        useModalVisibility();
    const { show: showMapDialog, props: mapDialogVisibilityProps } =
        useModalVisibility();

    const { type: collectionSummaryType, fileCount } = collectionSummary;
    const isQuickLinkAlbum =
        activeCollection?.magicMetadata?.data.subType ==
        CollectionSubType.quicklink;

    /**
     * Return a new function by wrapping an async function in an error handler,
     * showing the global loading bar when the function runs, and syncing with
     * remote on completion.
     */
    const wrap = useCallback(
        (f: () => Promise<void>) => {
            const wrapped = async () => {
                showLoadingBar();
                try {
                    await f();
                } catch (e) {
                    onGenericError(e);
                } finally {
                    void onRemotePull({ silent: true });
                    hideLoadingBar();
                }
            };
            return (): void => void wrapped();
        },
        [showLoadingBar, hideLoadingBar, onGenericError, onRemotePull],
    );

    const handleRenameCollection = useCallback(
        async (newName: string) => {
            if (!activeCollection) return;
            if (activeCollection.name !== newName) {
                await renameCollection(activeCollection, newName);
                void onRemotePull({ silent: true });
            }
        },
        [activeCollection, onRemotePull],
    );

    const hasAlbumFiles = fileCount > 0;

    const confirmDeleteCollection = () => {
        if (hasAlbumFiles) {
            showMiniDialog({
                title: t("delete_album_title"),
                message: (
                    <Trans
                        i18nKey={"delete_album_message"}
                        components={{
                            a: (
                                <Box
                                    component={"span"}
                                    sx={{ color: "text.base" }}
                                />
                            ),
                        }}
                    />
                ),
                continue: {
                    text: t("keep_photos"),
                    color: "primary",
                    action: deleteCollectionButKeepFiles,
                },
                secondary: {
                    text: t("delete_photos"),
                    color: "critical",
                    action: deleteCollectionAlongWithFiles,
                },
            });
            return;
        }

        showMiniDialog({
            title: t("delete_album_title"),
            message: (
                <Trans
                    i18nKey={"delete_album_message_no_photos"}
                    components={{
                        a: (
                            <Box
                                component={"span"}
                                sx={{ color: "text.base" }}
                            />
                        ),
                    }}
                />
            ),
            continue: {
                text: t("delete_album"),
                color: "critical",
                action: deleteCollectionAlongWithFiles,
            },
        });
    };

    const deleteCollectionAlongWithFiles = wrap(async () => {
        if (!activeCollection) return;
        await deleteCollection(activeCollection.id);
        setActiveCollectionID(PseudoCollectionID.all);
    });

    const deleteCollectionButKeepFiles = wrap(async () => {
        if (!activeCollection) return;
        await deleteCollection(activeCollection.id, { keepFiles: true });
        setActiveCollectionID(PseudoCollectionID.all);
    });

    const confirmEmptyTrash = () =>
        showMiniDialog({
            title: t("empty_trash_title"),
            message: t("empty_trash_message"),
            continue: {
                text: t("empty_trash"),
                color: "critical",
                action: doEmptyTrash,
            },
        });

    const doEmptyTrash = wrap(async () => {
        await emptyTrash();
        setActiveCollectionID(PseudoCollectionID.all);
    });

    const confirmCleanUncategorized = () =>
        showMiniDialog({
            title: t("clean_uncategorized"),
            message: t("clean_uncategorized_message"),
            continue: {
                text: t("clean_uncategorized"),
                color: "primary",
                action: doCleanUncategorized,
            },
        });

    const doCleanUncategorized = wrap(async () => {
        if (!activeCollection) return;
        const count = await cleanUncategorized(activeCollection);
        showNotification({
            color: "secondary",
            title: t("clean_uncategorized_success", { count }),
        });
    });

    const _downloadCollection = async () => {
        if (isActiveCollectionDownloadInProgress()) return;

        if (collectionSummaryType == "hiddenItems") {
            const defaultHiddenCollectionsIDs = findDefaultHiddenCollectionIDs(
                await savedCollections(),
            );
            const collectionFiles = await savedCollectionFiles();
            const defaultHiddenCollectionFiles = uniqueFilesByID(
                collectionFiles.filter((file) =>
                    defaultHiddenCollectionsIDs.has(file.collectionID),
                ),
            );
            await downloadAndSaveCollectionFiles(
                defaultHiddenCollectionUserFacingName,
                PseudoCollectionID.hiddenItems,
                defaultHiddenCollectionFiles,
                true,
                onAddSaveGroup,
            );
        } else if (activeCollection) {
            await downloadAndSaveCollectionFiles(
                activeCollection.name,
                activeCollection.id,
                (await savedCollectionFiles()).filter(
                    (file) => file.collectionID == activeCollection.id,
                ),
                isHiddenCollection(activeCollection),
                onAddSaveGroup,
            );
        }
    };

    const downloadCollection = () =>
        void _downloadCollection().catch(onGenericError);

    const archiveAlbum = wrap(async () => {
        if (!activeCollection) return;
        await updateCollectionVisibility(
            activeCollection,
            ItemVisibility.archived,
        );
    });

    const unarchiveAlbum = wrap(async () => {
        if (!activeCollection) return;
        await updateCollectionVisibility(
            activeCollection,
            ItemVisibility.visible,
        );
    });

    const confirmLeaveSharedAlbum = () =>
        showMiniDialog({
            title: t("leave_shared_album_title"),
            message: t("leave_shared_album_message"),
            continue: {
                text: t("leave_shared_album"),
                color: "critical",
                action: leaveSharedAlbum,
            },
        });

    const leaveSharedAlbum = wrap(async () => {
        if (!activeCollection) return;
        await leaveSharedCollection(activeCollection.id);
        setActiveCollectionID(PseudoCollectionID.all);
    });

    const pinAlbum = wrap(async () => {
        if (!activeCollection) return;
        await updateCollectionOrder(activeCollection, CollectionOrder.pinned);
    });

    const unpinAlbum = wrap(async () => {
        if (!activeCollection) return;
        await updateCollectionOrder(activeCollection, CollectionOrder.default);
    });

    const pinSharedAlbum = wrap(async () => {
        if (!activeCollection) return;
        await updateShareeCollectionOrder(
            activeCollection,
            CollectionOrder.pinned,
        );
    });

    const unpinSharedAlbum = wrap(async () => {
        if (!activeCollection) return;
        await updateShareeCollectionOrder(
            activeCollection,
            CollectionOrder.default,
        );
    });

    const hideAlbum = wrap(async () => {
        if (!activeCollection) return;
        await updateCollectionVisibility(
            activeCollection,
            ItemVisibility.hidden,
        );
        setActiveCollectionID(PseudoCollectionID.all);
    });

    const unhideAlbum = wrap(async () => {
        if (!activeCollection) return;
        await updateCollectionVisibility(
            activeCollection,
            ItemVisibility.visible,
        );
        setActiveCollectionID(PseudoCollectionID.hiddenItems);
    });

    const removeQuickLink = wrap(async () => {
        if (!activeCollection) return;

        if (isQuickLinkAlbum && activeCollection.sharees.length === 0) {
            await deleteCollection(activeCollection.id, { keepFiles: true });
            setActiveCollectionID(PseudoCollectionID.all);
            return;
        }

        await deleteShareURL(activeCollection.id);
    });

    const changeSortOrderAsc = wrap(async () => {
        if (!activeCollection) return;
        await updateCollectionSortOrder(activeCollection, true);
    });

    const changeSortOrderDesc = wrap(async () => {
        if (!activeCollection) return;
        await updateCollectionSortOrder(activeCollection, false);
    });

    const handleShowMap = useCallback(async () => {
        if (!mapEnabled) {
            try {
                await updateMapEnabled(true);
            } catch (e) {
                onGenericError(e);
                return;
            }
        }
        showMapDialog();
    }, [mapEnabled, onGenericError, showMapDialog]);

    let menuOptions: React.ReactNode[] = [];
    // MUI doesn't let us use fragments to pass multiple menu items, so we need
    // to instead put them in an array. This also necessitates giving each a
    // unique key.
    switch (collectionSummaryType) {
        case "trash":
            menuOptions = fileCount
                ? [<EmptyTrashOption key="trash" onClick={confirmEmptyTrash} />]
                : [];
            break;

        case "userFavorites":
            menuOptions = [];
            break;

        case "uncategorized":
            // Quick options (download + clean) are shown instead of a menu
            break;

        case "hiddenItems":
            menuOptions = [
                fileCount && (
                    <DownloadOption
                        key="download-hidden"
                        onClick={downloadCollection}
                    >
                        {t("download_hidden_items")}
                    </DownloadOption>
                ),
            ];
            break;

        case "sharedIncoming":
            menuOptions = [
                shouldShowMapOption(collectionSummary) && (
                    <OverflowMenuOption
                        key="map"
                        onClick={handleShowMap}
                        startIcon={<MapOutlinedIcon />}
                    >
                        {t("map")}
                    </OverflowMenuOption>
                ),
                // Pin/Unpin for shared incoming collections
                collectionSummary.attributes.has("shareePinned") ? (
                    <OverflowMenuOption
                        key="unpin"
                        onClick={unpinSharedAlbum}
                        startIcon={<PushPinOutlinedIcon />}
                    >
                        {t("unpin_album")}
                    </OverflowMenuOption>
                ) : (
                    <OverflowMenuOption
                        key="pin"
                        onClick={pinSharedAlbum}
                        startIcon={<PushPinIcon />}
                    >
                        {t("pin_album")}
                    </OverflowMenuOption>
                ),
                collectionSummary.attributes.has("archived") ? (
                    <OverflowMenuOption
                        key="unarchive"
                        onClick={unarchiveAlbum}
                        startIcon={<UnarchiveIcon />}
                    >
                        {t("unarchive_album")}
                    </OverflowMenuOption>
                ) : (
                    <OverflowMenuOption
                        key="archive"
                        onClick={archiveAlbum}
                        startIcon={<ArchiveOutlinedIcon />}
                    >
                        {t("archive_album")}
                    </OverflowMenuOption>
                ),

                activeCollection ? (
                    isHiddenCollection(activeCollection) ? (
                        <OverflowMenuOption
                            key="unhide"
                            onClick={unhideAlbum}
                            startIcon={<VisibilityOutlinedIcon />}
                        >
                            {t("unhide_collection")}
                        </OverflowMenuOption>
                    ) : (
                        <OverflowMenuOption
                            key="hide"
                            onClick={hideAlbum}
                            startIcon={<VisibilityOffOutlinedIcon />}
                        >
                            {t("hide_collection")}
                        </OverflowMenuOption>
                    )
                ) : undefined,
                <OverflowMenuOption
                    key="leave"
                    startIcon={<LogoutIcon />}
                    onClick={confirmLeaveSharedAlbum}
                >
                    {t("leave_album")}
                </OverflowMenuOption>,
                <OverflowMenuOption
                    key="cast"
                    startIcon={<TvIcon />}
                    onClick={onCollectionCast}
                >
                    {t("cast_album_to_tv")}
                </OverflowMenuOption>,
            ];
            break;

        default:
            if (isQuickLinkAlbum) {
                menuOptions = [
                    shouldShowMapOption(collectionSummary) && (
                        <OverflowMenuOption
                            key="map"
                            onClick={handleShowMap}
                            startIcon={<MapOutlinedIcon />}
                        >
                            {t("map")}
                        </OverflowMenuOption>
                    ),
                    <OverflowMenuOption
                        key="sort"
                        onClick={showSortOrderMenu}
                        startIcon={<SortIcon />}
                    >
                        {t("sort_by")}
                    </OverflowMenuOption>,
                    <OverflowMenuOption
                        key="cast"
                        startIcon={<TvIcon />}
                        onClick={onCollectionCast}
                    >
                        {t("cast_album_to_tv")}
                    </OverflowMenuOption>,
                    <OverflowMenuOption
                        key="remove-link"
                        onClick={removeQuickLink}
                        startIcon={
                            <HugeiconsIcon
                                icon={RemoveCircleIcon}
                                size={20}
                                strokeWidth={1.5}
                            />
                        }
                    >
                        {t("remove_link")}
                    </OverflowMenuOption>,
                ];
                break;
            }
            menuOptions = [
                <OverflowMenuOption
                    key="rename"
                    onClick={showAlbumNameInput}
                    startIcon={<EditIcon />}
                >
                    {t("rename_album")}
                </OverflowMenuOption>,
                canSetAlbumCover && (
                    <OverflowMenuOption
                        key="set-cover"
                        onClick={onSetAlbumCover}
                        startIcon={<ImageOutlinedIcon />}
                    >
                        {t("set_cover")}
                    </OverflowMenuOption>
                ),
                <OverflowMenuOption
                    key="sort"
                    onClick={showSortOrderMenu}
                    startIcon={<SortIcon />}
                >
                    {t("sort_by")}
                </OverflowMenuOption>,
                shouldShowMapOption(collectionSummary) && (
                    <OverflowMenuOption
                        key="map"
                        onClick={handleShowMap}
                        startIcon={<MapOutlinedIcon />}
                    >
                        {t("map")}
                    </OverflowMenuOption>
                ),
                collectionSummary.attributes.has("pinned") ? (
                    <OverflowMenuOption
                        key="unpin"
                        onClick={unpinAlbum}
                        startIcon={<PushPinOutlinedIcon />}
                    >
                        {t("unpin_album")}
                    </OverflowMenuOption>
                ) : (
                    <OverflowMenuOption
                        key="pin"
                        onClick={pinAlbum}
                        startIcon={<PushPinIcon />}
                    >
                        {t("pin_album")}
                    </OverflowMenuOption>
                ),
                ...(!activeCollection || !isHiddenCollection(activeCollection)
                    ? [
                          collectionSummary.attributes.has("archived") ? (
                              <OverflowMenuOption
                                  key="unarchive"
                                  onClick={unarchiveAlbum}
                                  startIcon={<UnarchiveIcon />}
                              >
                                  {t("unarchive_album")}
                              </OverflowMenuOption>
                          ) : (
                              <OverflowMenuOption
                                  key="archive"
                                  onClick={archiveAlbum}
                                  startIcon={<ArchiveOutlinedIcon />}
                              >
                                  {t("archive_album")}
                              </OverflowMenuOption>
                          ),
                      ]
                    : []),
                activeCollection && isHiddenCollection(activeCollection) ? (
                    <OverflowMenuOption
                        key="unhide"
                        onClick={unhideAlbum}
                        startIcon={<VisibilityOutlinedIcon />}
                    >
                        {t("unhide_collection")}
                    </OverflowMenuOption>
                ) : (
                    <OverflowMenuOption
                        key="hide"
                        onClick={hideAlbum}
                        startIcon={<VisibilityOffOutlinedIcon />}
                    >
                        {t("hide_collection")}
                    </OverflowMenuOption>
                ),
                <OverflowMenuOption
                    key="delete"
                    startIcon={<DeleteOutlinedIcon />}
                    onClick={confirmDeleteCollection}
                >
                    {t("delete_album")}
                </OverflowMenuOption>,
                <OverflowMenuOption
                    key="share"
                    onClick={onCollectionShare}
                    startIcon={<ShareIcon />}
                >
                    {t("share_album")}
                </OverflowMenuOption>,
                <OverflowMenuOption
                    key="cast"
                    startIcon={<TvIcon />}
                    onClick={onCollectionCast}
                >
                    {t("cast_album_to_tv")}
                </OverflowMenuOption>,
            ];
            break;
    }

    const validMenuOptions = menuOptions.filter((o) => !!o);

    return (
        <Box sx={{ display: "inline-flex", gap: "16px" }}>
            <QuickOptions
                collectionSummary={collectionSummary}
                isQuickLinkAlbum={isQuickLinkAlbum}
                hasActiveFileSelection={hasActiveFileSelection}
                isDownloadInProgress={isActiveCollectionDownloadInProgress}
                onMapClick={handleShowMap}
                onEmptyTrashClick={confirmEmptyTrash}
                onDownloadClick={downloadCollection}
                onShareClick={
                    isQuickLinkAlbum
                        ? onCollectionManageLink
                        : onCollectionShare
                }
                onCastClick={onCollectionCast}
                onCleanUncategorizedClick={confirmCleanUncategorized}
            />
            {validMenuOptions.length > 0 && (
                <OverflowMenu
                    ariaID="collection-options"
                    triggerButtonIcon={
                        <MoreHorizIcon ref={overflowMenuIconRef} />
                    }
                >
                    {validMenuOptions}
                </OverflowMenu>
            )}
            <CollectionSortOrderMenu
                {...sortOrderMenuVisibilityProps}
                overflowMenuIconRef={overflowMenuIconRef}
                sortAsc={activeCollection?.pubMagicMetadata?.data.asc ?? false}
                onAscClick={changeSortOrderAsc}
                onDescClick={changeSortOrderDesc}
            />
            <CollectionMapDialog
                {...mapDialogVisibilityProps}
                collectionSummary={collectionSummary}
                activeCollection={activeCollection}
                files={files}
                mapFileSource={mapFileSource}
                onRemotePull={onRemotePull}
                onAddSaveGroup={onAddSaveGroup}
                onMarkTempDeleted={onMarkTempDeleted}
                onAddFileToCollection={onAddFileToCollection}
                onRemoteFilesPull={onRemoteFilesPull}
                onVisualFeedback={onVisualFeedback}
                fileNormalCollectionIDs={fileNormalCollectionIDs}
                collectionNameByID={collectionNameByID}
                emailByUserID={emailByUserID}
                onSelectCollection={onSelectCollection}
                onSelectPerson={onSelectPerson}
            />
            <SingleInputDialog
                {...albumNameInputVisibilityProps}
                title={t("rename_album")}
                label={t("album_name")}
                initialValue={activeCollection?.name}
                submitButtonColor="primary"
                submitButtonTitle={t("rename")}
                onSubmit={handleRenameCollection}
            />
        </Box>
    );
};

/** Props for a generic option. */
interface OptionProps {
    onClick: () => void;
}

interface QuickOptionsProps {
    collectionSummary: CollectionSummary;
    isQuickLinkAlbum: boolean;
    hasActiveFileSelection: boolean;
    isDownloadInProgress: () => boolean;
    onMapClick: () => void;
    onEmptyTrashClick: () => void;
    onDownloadClick: () => void;
    onShareClick: () => void;
    onCastClick: () => void;
    onCleanUncategorizedClick: () => void;
}

const QuickOptions: React.FC<QuickOptionsProps> = ({
    onMapClick,
    onEmptyTrashClick,
    onDownloadClick,
    onShareClick,
    onCastClick,
    onCleanUncategorizedClick,
    collectionSummary,
    isQuickLinkAlbum,
    hasActiveFileSelection,
    isDownloadInProgress,
}) => (
    <Stack direction="row" sx={{ alignItems: "center", gap: "16px" }}>
        {showEmptyTrashQuickOption(collectionSummary) && (
            <EmptyTrashQuickOption onClick={onEmptyTrashClick} />
        )}
        {showDownloadQuickOption(collectionSummary) &&
            collectionSummary.fileCount > 0 &&
            (isDownloadInProgress() ? (
                <ActivityIndicator size="20px" sx={{ m: "12px" }} />
            ) : (
                <DownloadQuickOption
                    collectionSummary={collectionSummary}
                    disabled={hasActiveFileSelection}
                    onClick={onDownloadClick}
                />
            ))}
        {showCleanUncategorizedQuickOption(collectionSummary) && (
            <CleanUncategorizedQuickOption
                onClick={onCleanUncategorizedClick}
            />
        )}
        {showMapQuickOption(collectionSummary) && (
            <MapQuickOption onClick={onMapClick} />
        )}
        {showShareQuickOption(collectionSummary) && (
            <ShareQuickOption
                collectionSummary={collectionSummary}
                isQuickLinkAlbum={isQuickLinkAlbum}
                onClick={onShareClick}
            />
        )}
        {showCastQuickOption(collectionSummary) && (
            <CastQuickOption onClick={onCastClick} />
        )}
    </Stack>
);

const showEmptyTrashQuickOption = ({ type, fileCount }: CollectionSummary) =>
    type == "trash" && fileCount > 0;

const EmptyTrashQuickOption: React.FC<OptionProps> = ({ onClick }) => (
    <Tooltip title={t("empty_trash")}>
        <IconButton onClick={onClick}>
            <HugeiconsIcon icon={Delete02Icon} size={22} strokeWidth={1.5} />
        </IconButton>
    </Tooltip>
);

const showCleanUncategorizedQuickOption = ({
    type,
    fileCount,
}: CollectionSummary) => type == "uncategorized" && fileCount > 0;

const CleanUncategorizedQuickOption: React.FC<OptionProps> = ({ onClick }) => (
    <Tooltip title={t("clean_uncategorized")}>
        <IconButton onClick={onClick}>
            <HugeiconsIcon icon={CleanIcon} size={22} strokeWidth={1.5} />
        </IconButton>
    </Tooltip>
);

const MapQuickOption: React.FC<OptionProps> = ({ onClick }) => (
    <Tooltip title={t("map")}>
        <IconButton onClick={onClick}>
            <Box
                sx={{
                    width: 24,
                    height: 24,
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "center",
                }}
            >
                <PublicIcon />
            </Box>
        </IconButton>
    </Tooltip>
);

const showDownloadQuickOption = ({ type, attributes }: CollectionSummary) =>
    type == "album" ||
    type == "folder" ||
    type == "uncategorized" ||
    type == "hiddenItems" ||
    attributes.has("favorites") ||
    attributes.has("shared");

const showMapQuickOption = (collectionSummary: CollectionSummary) =>
    collectionSummary.type == "userFavorites" &&
    shouldShowMapOption(collectionSummary);

const shouldShowMapOption = ({ type, fileCount }: CollectionSummary) =>
    fileCount > 0 &&
    type !== "all" &&
    type !== "archiveItems" &&
    type !== "trash" &&
    type !== "hiddenItems";

type DownloadQuickOptionProps = OptionProps & {
    collectionSummary: CollectionSummary;
    disabled?: boolean;
};

const DownloadIcon: React.FC = () => (
    <svg
        width="22"
        height="22"
        viewBox="0 0 24 24"
        fill="none"
        xmlns="http://www.w3.org/2000/svg"
        stroke="currentColor"
        strokeWidth="1.5"
        strokeLinecap="round"
        strokeLinejoin="round"
    >
        <path d="M2.99969 17.0002C2.99969 17.9302 2.99969 18.3952 3.10192 18.7767C3.37932 19.8119 4.18796 20.6206 5.22324 20.898C5.60474 21.0002 6.06972 21.0002 6.99969 21.0002L16.9997 21.0002C17.9297 21.0002 18.3947 21.0002 18.7762 20.898C19.8114 20.6206 20.6201 19.8119 20.8975 18.7767C20.9997 18.3952 20.9997 17.9302 20.9997 17.0002" />
        <path d="M16.4998 11.5002C16.4998 11.5002 13.1856 16.0002 11.9997 16.0002C10.8139 16.0002 7.49976 11.5002 7.49976 11.5002M11.9997 15.0002V3.00016" />
    </svg>
);

const DownloadQuickOption: React.FC<DownloadQuickOptionProps> = ({
    collectionSummary: { type },
    disabled,
    onClick,
}) => (
    <Tooltip
        title={
            type == "userFavorites"
                ? t("download_favorites")
                : type == "uncategorized"
                  ? t("download_uncategorized")
                  : type == "hiddenItems"
                    ? t("download_hidden_items")
                    : t("download_album")
        }
    >
        <span>
            <IconButton disabled={disabled} onClick={onClick}>
                <Box
                    sx={{
                        width: 24,
                        height: 24,
                        display: "flex",
                        alignItems: "center",
                        justifyContent: "center",
                    }}
                >
                    <DownloadIcon />
                </Box>
            </IconButton>
        </span>
    </Tooltip>
);

export const FeedIcon: React.FC = () => (
    <svg
        width="23"
        height="20"
        viewBox="0 0 23 20"
        fill="none"
        xmlns="http://www.w3.org/2000/svg"
    >
        <path
            d="M9.7998 0.5C10.2416 0.5 10.5996 0.857977 10.5996 1.2998C10.5996 1.74163 10.2416 2.09961 9.7998 2.09961H4.7998C3.03249 2.09961 1.59961 3.53249 1.59961 5.2998V14.2998C1.59961 16.0671 3.0325 17.5 4.7998 17.5H13.7998C15.5671 17.5 17 16.0671 17 14.2998V11.7998C17 11.358 17.358 11 17.7998 11C18.2416 11 18.5996 11.358 18.5996 11.7998V14.2998C18.5996 16.9507 16.4507 19.0996 13.7998 19.0996H4.7998C2.14883 19.0996 0 16.9507 0 14.2998V5.2998C0 2.64884 2.14884 0.5 4.7998 0.5H9.7998Z"
            fill="currentColor"
        />
        <path
            d="M13.2998 13.5C13.7416 13.5 14.0996 13.858 14.0996 14.2998C14.0996 14.7416 13.7416 15.0996 13.2998 15.0996H4.2998C3.85798 15.0996 3.5 14.7416 3.5 14.2998C3.5 13.858 3.85798 13.5 4.2998 13.5H13.2998Z"
            fill="currentColor"
        />
        <path
            d="M10.2998 10.5C10.7416 10.5 11.0996 10.858 11.0996 11.2998C11.0996 11.7416 10.7416 12.0996 10.2998 12.0996H4.2998C3.85798 12.0996 3.5 11.7416 3.5 11.2998C3.5 10.858 3.85798 10.5 4.2998 10.5H10.2998Z"
            fill="currentColor"
        />
        <path
            d="M20.6523 6.12012C21.3761 5.2635 22.0996 4.13144 22.0996 2.93848C22.0995 1.38141 20.9626 0 19.2998 0C18.621 0 17.9847 0.205224 17.2998 0.749023C16.6149 0.205224 15.9787 0 15.2998 0C13.637 0 12.5001 1.38141 12.5 2.93848C12.5 4.13144 13.2236 5.2635 13.9473 6.12012C14.698 7.00866 15.5878 7.76218 16.1758 8.21484C16.8431 8.72865 17.7565 8.72865 18.4238 8.21484C19.0119 7.76218 19.9016 7.00866 20.6523 6.12012Z"
            fill="currentColor"
        />
    </svg>
);

const showShareQuickOption = ({ type, attributes }: CollectionSummary) =>
    type == "album" ||
    type == "folder" ||
    attributes.has("favorites") ||
    attributes.has("shared");

const showCastQuickOption = ({ type }: CollectionSummary) =>
    type == "userFavorites";

interface ShareQuickOptionProps {
    collectionSummary: CollectionSummary;
    isQuickLinkAlbum: boolean;
    onClick: () => void;
}

const ShareIcon: React.FC = () => (
    <svg
        width="21"
        height="19"
        viewBox="0 0 22 20"
        fill="none"
        xmlns="http://www.w3.org/2000/svg"
    >
        <path
            d="M13.875 8C13.3918 8 13 8.39175 13 8.875C13 9.35825 13.3918 9.75 13.875 9.75V8.875V8ZM13.875 0C13.3918 0 13 0.391751 13 0.875C13 1.35825 13.3918 1.75 13.875 1.75V0.875V0ZM15.875 11C15.3918 11 15 11.3918 15 11.875C15 12.3582 15.3918 12.75 15.875 12.75V11.875V11ZM17.375 18C16.8918 18 16.5 18.3918 16.5 18.875C16.5 19.3582 16.8918 19.75 17.375 19.75V18.875V18ZM11.875 4.875H11C11 6.60089 9.60086 8 7.875 8V8.875V9.75C10.5673 9.75 12.75 7.56739 12.75 4.875H11.875ZM7.875 8.875V8C6.14911 8 4.75 6.60089 4.75 4.875H3.875H3C3 7.56739 5.18261 9.75 7.875 9.75V8.875ZM3.875 4.875H4.75C4.75 3.14911 6.14911 1.75 7.875 1.75V0.875V0C5.18261 0 3 2.18261 3 4.875H3.875ZM7.875 0.875V1.75C9.60086 1.75 11 3.14911 11 4.875H11.875H12.75C12.75 2.18261 10.5673 0 7.875 0V0.875ZM13.875 8.875V9.75C16.5673 9.75 18.75 7.56739 18.75 4.875H17.875H17C17 6.60089 15.6009 8 13.875 8V8.875ZM17.875 4.875H18.75C18.75 2.18261 16.5673 0 13.875 0V0.875V1.75C15.6009 1.75 17 3.14911 17 4.875H17.875ZM9.875 11.875V11H5.875V11.875V12.75H9.875V11.875ZM5.875 11.875V11C2.63033 11 0 13.6304 0 16.875H0.875H1.75C1.75 14.5968 3.59683 12.75 5.875 12.75V11.875ZM0.875 16.875H0C0 18.4629 1.28719 19.75 2.875 19.75V18.875V18C2.25367 18 1.75 17.4963 1.75 16.875H0.875ZM2.875 18.875V19.75H12.875V18.875V18H2.875V18.875ZM12.875 18.875V19.75C14.4628 19.75 15.75 18.4628 15.75 16.875H14.875H14C14 17.4964 13.4964 18 12.875 18V18.875ZM14.875 16.875H15.75C15.75 13.6304 13.1196 11 9.875 11V11.875V12.75C12.1532 12.75 14 14.5968 14 16.875H14.875ZM15.875 11.875V12.75C18.1532 12.75 20 14.5968 20 16.875H20.875H21.75C21.75 13.6304 19.1196 11 15.875 11V11.875ZM20.875 16.875H20C20 17.4964 19.4964 18 18.875 18V18.875V19.75C20.4628 19.75 21.75 18.4628 21.75 16.875H20.875ZM18.875 18.875V18H17.375V18.875V19.75H18.875V18.875Z"
            fill="currentColor"
        />
    </svg>
);

/** A smaller version of ShareIcon for use in the collection header summary. */
const SmallShareIcon: React.FC<React.SVGProps<SVGSVGElement>> = (props) => (
    <svg
        width="15"
        height="14"
        viewBox="0 0 22 20"
        {...props}
        fill="none"
        xmlns="http://www.w3.org/2000/svg"
    >
        <path
            d="M13.875 8C13.3918 8 13 8.39175 13 8.875C13 9.35825 13.3918 9.75 13.875 9.75V8.875V8ZM13.875 0C13.3918 0 13 0.391751 13 0.875C13 1.35825 13.3918 1.75 13.875 1.75V0.875V0ZM15.875 11C15.3918 11 15 11.3918 15 11.875C15 12.3582 15.3918 12.75 15.875 12.75V11.875V11ZM17.375 18C16.8918 18 16.5 18.3918 16.5 18.875C16.5 19.3582 16.8918 19.75 17.375 19.75V18.875V18ZM11.875 4.875H11C11 6.60089 9.60086 8 7.875 8V8.875V9.75C10.5673 9.75 12.75 7.56739 12.75 4.875H11.875ZM7.875 8.875V8C6.14911 8 4.75 6.60089 4.75 4.875H3.875H3C3 7.56739 5.18261 9.75 7.875 9.75V8.875ZM3.875 4.875H4.75C4.75 3.14911 6.14911 1.75 7.875 1.75V0.875V0C5.18261 0 3 2.18261 3 4.875H3.875ZM7.875 0.875V1.75C9.60086 1.75 11 3.14911 11 4.875H11.875H12.75C12.75 2.18261 10.5673 0 7.875 0V0.875ZM13.875 8.875V9.75C16.5673 9.75 18.75 7.56739 18.75 4.875H17.875H17C17 6.60089 15.6009 8 13.875 8V8.875ZM17.875 4.875H18.75C18.75 2.18261 16.5673 0 13.875 0V0.875V1.75C15.6009 1.75 17 3.14911 17 4.875H17.875ZM9.875 11.875V11H5.875V11.875V12.75H9.875V11.875ZM5.875 11.875V11C2.63033 11 0 13.6304 0 16.875H0.875H1.75C1.75 14.5968 3.59683 12.75 5.875 12.75V11.875ZM0.875 16.875H0C0 18.4629 1.28719 19.75 2.875 19.75V18.875V18C2.25367 18 1.75 17.4963 1.75 16.875H0.875ZM2.875 18.875V19.75H12.875V18.875V18H2.875V18.875ZM12.875 18.875V19.75C14.4628 19.75 15.75 18.4628 15.75 16.875H14.875H14C14 17.4964 13.4964 18 12.875 18V18.875ZM14.875 16.875H15.75C15.75 13.6304 13.1196 11 9.875 11V11.875V12.75C12.1532 12.75 14 14.5968 14 16.875H14.875ZM15.875 11.875V12.75C18.1532 12.75 20 14.5968 20 16.875H20.875H21.75C21.75 13.6304 19.1196 11 15.875 11V11.875ZM20.875 16.875H20C20 17.4964 19.4964 18 18.875 18V18.875V19.75C20.4628 19.75 21.75 18.4628 21.75 16.875H20.875ZM18.875 18.875V18H17.375V18.875V19.75H18.875V18.875Z"
            fill="currentColor"
        />
    </svg>
);

const ShareQuickOption: React.FC<ShareQuickOptionProps> = ({
    collectionSummary: { attributes },
    isQuickLinkAlbum,
    onClick,
}) => (
    <Tooltip
        title={
            isQuickLinkAlbum
                ? t("manage_link")
                : attributes.has("userFavorites")
                  ? t("share_favorites")
                  : attributes.has("sharedIncoming")
                    ? t("sharing_details")
                    : attributes.has("shared")
                      ? t("modify_sharing")
                      : t("share_album")
        }
    >
        <IconButton onClick={onClick}>
            <Box
                sx={{
                    width: 24,
                    height: 24,
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "center",
                }}
            >
                {isQuickLinkAlbum ? <LinkIcon /> : <ShareIcon />}
            </Box>
        </IconButton>
    </Tooltip>
);

const CastQuickOption: React.FC<OptionProps> = ({ onClick }) => (
    <Tooltip title={t("cast_to_tv")}>
        <IconButton onClick={onClick}>
            <Box
                sx={{
                    width: 24,
                    height: 24,
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "center",
                }}
            >
                <HugeiconsIcon
                    icon={ModernTvIcon}
                    size={22}
                    strokeWidth={1.8}
                />
            </Box>
        </IconButton>
    </Tooltip>
);

const EmptyTrashOption: React.FC<OptionProps> = ({ onClick }) => (
    <OverflowMenuOption
        color="critical"
        startIcon={
            <HugeiconsIcon icon={Delete02Icon} size={20} strokeWidth={1.5} />
        }
        onClick={onClick}
    >
        {t("empty_trash")}
    </OverflowMenuOption>
);

type DownloadOptionProps = OptionProps & {
    isDownloadInProgress?: () => boolean;
};

const DownloadOption: React.FC<
    React.PropsWithChildren<DownloadOptionProps>
> = ({ isDownloadInProgress, onClick, children }) => (
    <OverflowMenuOption
        startIcon={
            isDownloadInProgress?.() ? (
                <ActivityIndicator size="20px" sx={{ cursor: "not-allowed" }} />
            ) : (
                <DownloadIcon />
            )
        }
        onClick={onClick}
    >
        {children}
    </OverflowMenuOption>
);

interface CollectionSortOrderMenuProps {
    open: boolean;
    onClose: () => void;
    overflowMenuIconRef: React.RefObject<SVGSVGElement | null>;
    sortAsc: boolean;
    onAscClick: () => void;
    onDescClick: () => void;
}

const CollectionSortOrderMenu: React.FC<CollectionSortOrderMenuProps> = ({
    open,
    onClose,
    overflowMenuIconRef,
    sortAsc,
    onAscClick,
    onDescClick,
}) => {
    const handleAscClick = () => {
        onAscClick();
        onClose();
    };

    const handleDescClick = () => {
        onDescClick();
        onClose();
    };

    return (
        <Menu
            id="collection-files-sort"
            anchorEl={overflowMenuIconRef.current}
            open={open}
            onClose={onClose}
            slotProps={{
                list: {
                    disablePadding: true,
                    "aria-labelledby": "collection-files-sort",
                },
            }}
            anchorOrigin={{ vertical: "bottom", horizontal: "right" }}
            transformOrigin={{ vertical: "top", horizontal: "right" }}
        >
            <OverflowMenuOption
                onClick={handleDescClick}
                endIcon={!sortAsc ? <CheckIcon /> : undefined}
            >
                {t("newest_first")}
            </OverflowMenuOption>
            <OverflowMenuOption
                onClick={handleAscClick}
                endIcon={sortAsc ? <CheckIcon /> : undefined}
            >
                {t("oldest_first")}
            </OverflowMenuOption>
        </Menu>
    );
};
