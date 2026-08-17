import type { RemotePullOpts } from "@/components/gallery";
import { StarIcon } from "@/components/icons/StarIcon";
import { downloadAndSaveCollectionFiles } from "@/services/save";
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
import { useModalVisibility } from "ente-base/components/utils/modal";
import { useBaseContext } from "ente-base/context";
import type { AddSaveGroup } from "ente-gallery/components/utils/save-groups";
import { uniqueFilesByID } from "ente-gallery/utils/file";
import {
    CollectionOrder,
    CollectionSubType,
    type Collection,
} from "ente-media/collection";
import { ItemVisibility } from "ente-media/file-metadata";
import {
    GalleryItemsHeaderAdapter,
    GalleryItemsSummary,
} from "ente-new/photos/components/gallery/ListHeader";
import {
    cleanUncategorized,
    defaultHiddenCollectionUserFacingName,
    deleteCollection,
    deleteShareURL,
    findDefaultHiddenCollectionIDs,
    isHiddenCollection,
    leaveSharedCollection,
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
import { emptyTrash } from "ente-new/photos/services/trash";
import { usePhotosAppContext } from "ente-new/photos/types/context";
import { t } from "i18next";
import React, { useCallback, useRef } from "react";
import { Trans } from "react-i18next";

export interface CollectionHeaderProps {
    collectionSummary: CollectionSummary;
    activeCollection: Collection | undefined;
    setActiveCollectionID: (collectionID: number) => void;
    isActiveCollectionDownloadInProgress: () => boolean;
    onRemotePull: (opts?: RemotePullOpts) => Promise<void>;
    onCollectionShare: () => void;
    onCollectionManageLink: () => void;
    onCollectionCast: () => void;
    onEditAlbumDetails: () => void;
    hasActiveFileSelection: boolean;
    onAddSaveGroup: AddSaveGroup;
    onShowMap: () => void;
    onDescriptionHeightChange?: (height: number) => void;
}

export const CollectionHeader: React.FC<CollectionHeaderProps> = (props) => {
    const { activeCollection, collectionSummary, onDescriptionHeightChange } =
        props;

    const { name, type, attributes, fileCount } = collectionSummary;
    const description =
        activeCollection?.pubMagicMetadata?.data.caption?.trim();

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
                    description={description}
                    descriptionMaxWidth={480}
                    fileCount={fileCount}
                    endIcon={<EndIcon />}
                    onDescriptionHeightChange={onDescriptionHeightChange}
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
    setActiveCollectionID,
    onRemotePull,
    onCollectionShare,
    onCollectionManageLink,
    onCollectionCast,
    onEditAlbumDetails,
    hasActiveFileSelection,
    onAddSaveGroup,
    isActiveCollectionDownloadInProgress,
    onShowMap,
}) => {
    const { showMiniDialog, onGenericError } = useBaseContext();
    const { showLoadingBar, hideLoadingBar, showNotification } =
        usePhotosAppContext();
    const overflowMenuIconRef = useRef<SVGSVGElement | null>(null);

    const { show: showSortOrderMenu, props: sortOrderMenuVisibilityProps } =
        useModalVisibility();

    const { type: collectionSummaryType, fileCount } = collectionSummary;
    const isQuickLinkAlbum =
        activeCollection?.magicMetadata?.data.subType ==
        CollectionSubType.quicklink;

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

    let menuOptions: React.ReactNode[] = [];
    // MUI rejects fragments here, so return keyed arrays.
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
                        onClick={onShowMap}
                        startIcon={<MapOutlinedIcon />}
                    >
                        {t("map")}
                    </OverflowMenuOption>
                ),
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
                            onClick={onShowMap}
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
                activeCollection && (
                    <OverflowMenuOption
                        key="edit-details"
                        onClick={onEditAlbumDetails}
                        startIcon={<EditIcon />}
                    >
                        {t("edit_details")}
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
                        onClick={onShowMap}
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
                onMapClick={onShowMap}
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
        </Box>
    );
};

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
