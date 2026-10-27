import type { RemotePullOpts } from "@/components/gallery";
import { downloadAndSaveCollectionFiles } from "@/services/save";
import {
    CleanIcon,
    Delete02Icon,
    Download04Icon,
    Download05Icon,
    Edit02Icon,
    Logout01Icon,
    MapIcon,
    ModernTvIcon,
    PinIcon,
    PinOffIcon,
    PlaySquareIcon,
    RemoveCircleIcon,
    Sorting05Icon,
    StarIcon,
    Unarchive03Icon,
    ViewIcon,
    ViewOffSlashIcon,
} from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import ArchiveOutlinedIcon from "@mui/icons-material/ArchiveOutlined";
import CheckIcon from "@mui/icons-material/Check";
import LinkIcon from "@mui/icons-material/Link";
import MoreHorizIcon from "@mui/icons-material/MoreHoriz";
import PublicIcon from "@mui/icons-material/Public";
import {
    Box,
    IconButton,
    Stack,
    Tooltip,
    useMediaQuery,
    useTheme,
} from "@mui/material";
import { SpacedRow } from "ente-base/components/containers";
import { ContextMenu, ContextMenuItem } from "ente-base/components/ContextMenu";
import { ActivityIndicator } from "ente-base/components/mui/ActivityIndicator";
import { useIsSmallWidth } from "ente-base/components/utils/hooks";
import { useModalVisibility } from "ente-base/components/utils/modal";
import { useBaseContext } from "ente-base/context";
import type { AddSaveGroup } from "ente-gallery/components/utils/save-groups";
import { uniqueFilesByID } from "ente-gallery/utils/file";
import {
    CollectionOrder,
    CollectionSubType,
    type Collection,
} from "ente-media/collection";
import type { CollectionSortBy } from "ente-media/collection-sort";
import { ItemVisibility } from "ente-media/file-metadata";
import {
    AlbumDescription,
    GalleryItemsCoverTile,
    GalleryItemsHeaderAdapter,
    GalleryItemsSummary,
} from "ente-new/photos/components/gallery/ListHeader";
import { ItemCard } from "ente-new/photos/components/Tiles";
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
import React, { useCallback, useRef, useState } from "react";
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
    onCollectionSlideshow: () => void;
    onEditAlbumDetails: () => void;
    hasActiveFileSelection: boolean;
    onAddSaveGroup: AddSaveGroup;
    onShowMap: () => void;
    onBackToAlbums: () => void;
    onDescriptionHeightChange?: (height: number) => void;
}

export const CollectionHeader: React.FC<CollectionHeaderProps> = (props) => {
    const { activeCollection, collectionSummary, onDescriptionHeightChange } =
        props;
    const showCover = useMediaQuery(useTheme().breakpoints.up("sm"));

    const { name, type, attributes, fileCount } = collectionSummary;
    const isAlbum = isAlbumSummary(collectionSummary);
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
            return (
                <HugeiconsIcon
                    icon={StarIcon}
                    size="1em"
                    fill="currentColor"
                    aria-hidden
                />
            );
        return <></>;
    };

    return (
        <GalleryItemsHeaderAdapter>
            <SpacedRow
                sx={
                    isAlbum
                        ? {
                              display: "grid",
                              gridTemplateColumns: "minmax(0, 1fr) auto",
                              gridTemplateAreas:
                                  '"summary actions" "description description"',
                              columnGap: 2,
                              alignItems: "start",
                          }
                        : { gap: 2, alignItems: "center" }
                }
            >
                <Stack
                    direction="row"
                    sx={{
                        gap: isAlbum ? 2 : 1,
                        alignItems: "center",
                        minWidth: 0,
                        ...(isAlbum && { gridArea: "summary" }),
                    }}
                >
                    {isAlbum && showCover && (
                        <Box
                            aria-hidden
                            sx={{ flexShrink: 0, alignSelf: "flex-start" }}
                        >
                            <ItemCard
                                key={`${collectionSummary.id}-${collectionSummary.coverFile?.id ?? "empty"}`}
                                TileComponent={GalleryItemsCoverTile}
                                coverFile={collectionSummary.coverFile}
                            />
                        </Box>
                    )}
                    <GalleryItemsSummary
                        nameProps={
                            isAlbum
                                ? { sx: { overflowWrap: "anywhere" } }
                                : undefined
                        }
                        name={name}
                        description={isAlbum ? undefined : description}
                        descriptionMaxWidth={480}
                        onDescriptionHeightChange={
                            isAlbum ? undefined : onDescriptionHeightChange
                        }
                        fileCount={fileCount}
                        endIcon={<EndIcon />}
                    />
                </Stack>
                {shouldShowOptions(type) && (
                    <Box sx={isAlbum ? { gridArea: "actions" } : undefined}>
                        <CollectionHeaderOptions {...props} />
                    </Box>
                )}
                {isAlbum && (
                    <AlbumDescription
                        description={description}
                        onHeightChange={onDescriptionHeightChange}
                        sx={{
                            gridArea: "description",
                            pt: 1,
                            maxWidth: 480,
                            color: "text.faint",
                        }}
                    />
                )}
            </SpacedRow>
        </GalleryItemsHeaderAdapter>
    );
};

const isAlbumSummary = ({ type }: CollectionSummary) =>
    type == "album" || type == "folder" || type == "sharedIncoming";

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
    onCollectionSlideshow,
    onEditAlbumDetails,
    hasActiveFileSelection,
    onAddSaveGroup,
    isActiveCollectionDownloadInProgress,
    onShowMap,
}) => {
    const { showMiniDialog, onGenericError } = useBaseContext();
    const { showLoadingBar, hideLoadingBar, showNotification } =
        usePhotosAppContext();
    const [menuAnchorEl, setMenuAnchorEl] = useState<HTMLElement | null>(null);
    const isSmallWidth = useIsSmallWidth();
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
                kind: "info",
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
            kind: "info",
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
            kind: "warning",
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

    const changeSortOrder = (sortBy: CollectionSortBy, asc: boolean) => {
        wrap(async () => {
            if (!activeCollection) return;
            await updateCollectionSortOrder(activeCollection, asc, sortBy);
        })();
    };

    let menuOptions: React.ReactNode[] = [];
    // MUI rejects fragments here, so return keyed arrays.
    switch (collectionSummaryType) {
        case "trash":
            break;

        case "userFavorites":
            menuOptions = [];
            break;

        case "uncategorized":
            break;

        case "hiddenItems":
            break;

        case "sharedIncoming":
            menuOptions = [
                shouldShowMapOption(collectionSummary) && (
                    <ContextMenuItem key="map" onClick={onShowMap}>
                        <HugeiconsIcon icon={MapIcon} size={20} />
                        {t("map")}
                    </ContextMenuItem>
                ),
                collectionSummary.attributes.has("shareePinned") ? (
                    <ContextMenuItem key="unpin" onClick={unpinSharedAlbum}>
                        <HugeiconsIcon icon={PinOffIcon} size={20} />
                        {t("unpin_album")}
                    </ContextMenuItem>
                ) : (
                    <ContextMenuItem key="pin" onClick={pinSharedAlbum}>
                        <HugeiconsIcon icon={PinIcon} size={20} />
                        {t("pin_album")}
                    </ContextMenuItem>
                ),
                collectionSummary.attributes.has("archived") ? (
                    <ContextMenuItem key="unarchive" onClick={unarchiveAlbum}>
                        <HugeiconsIcon icon={Unarchive03Icon} size={20} />
                        {t("unarchive_album")}
                    </ContextMenuItem>
                ) : (
                    <ContextMenuItem key="archive" onClick={archiveAlbum}>
                        <HugeiconsIcon icon={Download05Icon} size={20} />
                        {t("archive_album")}
                    </ContextMenuItem>
                ),

                activeCollection ? (
                    isHiddenCollection(activeCollection) ? (
                        <ContextMenuItem key="unhide" onClick={unhideAlbum}>
                            <HugeiconsIcon icon={ViewIcon} size={20} />
                            {t("unhide_collection")}
                        </ContextMenuItem>
                    ) : (
                        <ContextMenuItem key="hide" onClick={hideAlbum}>
                            <HugeiconsIcon icon={ViewOffSlashIcon} size={20} />
                            {t("hide_collection")}
                        </ContextMenuItem>
                    )
                ) : undefined,
                <ContextMenuItem key="leave" onClick={confirmLeaveSharedAlbum}>
                    <HugeiconsIcon icon={Logout01Icon} size={20} />
                    {t("leave_album")}
                </ContextMenuItem>,
                <ContextMenuItem key="cast" onClick={onCollectionCast}>
                    <HugeiconsIcon icon={ModernTvIcon} size={20} />
                    {t("cast_album_to_tv")}
                </ContextMenuItem>,
            ];
            break;

        default:
            if (isQuickLinkAlbum) {
                menuOptions = [
                    shouldShowMapOption(collectionSummary) && (
                        <ContextMenuItem key="map" onClick={onShowMap}>
                            <HugeiconsIcon icon={MapIcon} size={20} />
                            {t("map")}
                        </ContextMenuItem>
                    ),
                    <ContextMenuItem key="sort" onClick={showSortOrderMenu}>
                        <HugeiconsIcon icon={Sorting05Icon} size={20} />
                        {t("sort_by")}
                    </ContextMenuItem>,
                    <ContextMenuItem key="cast" onClick={onCollectionCast}>
                        <HugeiconsIcon icon={ModernTvIcon} size={20} />
                        {t("cast_album_to_tv")}
                    </ContextMenuItem>,
                    <ContextMenuItem
                        key="remove-link"
                        onClick={removeQuickLink}
                    >
                        <HugeiconsIcon
                            icon={RemoveCircleIcon}
                            size={20}
                            strokeWidth={1.5}
                        />
                        {t("remove_link")}
                    </ContextMenuItem>,
                ];
                break;
            }
            menuOptions = [
                activeCollection && (
                    <ContextMenuItem
                        key="edit-details"
                        onClick={onEditAlbumDetails}
                    >
                        <HugeiconsIcon icon={Edit02Icon} size={20} />
                        {t("edit_details")}
                    </ContextMenuItem>
                ),
                <ContextMenuItem key="sort" onClick={showSortOrderMenu}>
                    <HugeiconsIcon icon={Sorting05Icon} size={20} />
                    {t("sort_by")}
                </ContextMenuItem>,
                shouldShowMapOption(collectionSummary) && (
                    <ContextMenuItem key="map" onClick={onShowMap}>
                        <HugeiconsIcon icon={MapIcon} size={20} />
                        {t("map")}
                    </ContextMenuItem>
                ),
                collectionSummary.attributes.has("pinned") ? (
                    <ContextMenuItem key="unpin" onClick={unpinAlbum}>
                        <HugeiconsIcon icon={PinOffIcon} size={20} />
                        {t("unpin_album")}
                    </ContextMenuItem>
                ) : (
                    <ContextMenuItem key="pin" onClick={pinAlbum}>
                        <HugeiconsIcon icon={PinIcon} size={20} />
                        {t("pin_album")}
                    </ContextMenuItem>
                ),
                ...(!activeCollection || !isHiddenCollection(activeCollection)
                    ? [
                          collectionSummary.attributes.has("archived") ? (
                              <ContextMenuItem
                                  key="unarchive"
                                  onClick={unarchiveAlbum}
                              >
                                  <HugeiconsIcon
                                      icon={Unarchive03Icon}
                                      size={20}
                                  />
                                  {t("unarchive_album")}
                              </ContextMenuItem>
                          ) : (
                              <ContextMenuItem
                                  key="archive"
                                  onClick={archiveAlbum}
                              >
                                  <HugeiconsIcon
                                      icon={Download05Icon}
                                      size={20}
                                  />
                                  {t("archive_album")}
                              </ContextMenuItem>
                          ),
                      ]
                    : []),
                activeCollection && isHiddenCollection(activeCollection) ? (
                    <ContextMenuItem key="unhide" onClick={unhideAlbum}>
                        <HugeiconsIcon icon={ViewIcon} size={20} />
                        {t("unhide_collection")}
                    </ContextMenuItem>
                ) : (
                    <ContextMenuItem key="hide" onClick={hideAlbum}>
                        <HugeiconsIcon icon={ViewOffSlashIcon} size={20} />
                        {t("hide_collection")}
                    </ContextMenuItem>
                ),
                <ContextMenuItem
                    key="delete"
                    destructive
                    onClick={confirmDeleteCollection}
                >
                    <HugeiconsIcon icon={Delete02Icon} size={20} />
                    {t("delete_album")}
                </ContextMenuItem>,
                <ContextMenuItem key="cast" onClick={onCollectionCast}>
                    <HugeiconsIcon icon={ModernTvIcon} size={20} />
                    {t("cast_album_to_tv")}
                </ContextMenuItem>,
            ];
            break;
    }

    if (isSmallWidth) {
        menuOptions.unshift(
            collectionSummaryType != "hiddenItems" &&
                showDownloadQuickOption(collectionSummary) &&
                fileCount > 0 && (
                    <ContextMenuItem
                        key="download"
                        disabled={
                            hasActiveFileSelection ||
                            isActiveCollectionDownloadInProgress()
                        }
                        onClick={downloadCollection}
                    >
                        {isActiveCollectionDownloadInProgress() ? (
                            <ActivityIndicator size="20px" />
                        ) : (
                            <HugeiconsIcon
                                icon={Download04Icon}
                                size={22}
                                strokeWidth={1.5}
                                aria-hidden
                            />
                        )}
                        {downloadOptionLabel(collectionSummary)}
                    </ContextMenuItem>
                ),
            showShareQuickOption(collectionSummary) && (
                <ContextMenuItem
                    key="share"
                    onClick={
                        isQuickLinkAlbum
                            ? onCollectionManageLink
                            : onCollectionShare
                    }
                >
                    {isQuickLinkAlbum ? <LinkIcon /> : <ShareIcon />}
                    {shareOptionLabel(collectionSummary, isQuickLinkAlbum)}
                </ContextMenuItem>
            ),
        );
    }

    if (activeCollection)
        menuOptions.push(
            <ContextMenuItem key="slideshow" onClick={onCollectionSlideshow}>
                <HugeiconsIcon icon={PlaySquareIcon} size={20} />
                {t("slideshow")}
            </ContextMenuItem>,
        );
    const validMenuOptions = menuOptions.filter((o) => !!o);

    return (
        <Box
            sx={{
                display: "inline-flex",
                gap: "16px",
                flexShrink: 0,
                mt: isAlbumSummary(collectionSummary)
                    ? { xs: 0, sm: "3px" }
                    : 0,
            }}
        >
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
                <>
                    <IconButton
                        aria-label={t("more_options")}
                        id="collection-options-trigger"
                        aria-controls={
                            menuAnchorEl ? "collection-options" : undefined
                        }
                        aria-haspopup="true"
                        aria-expanded={menuAnchorEl ? "true" : undefined}
                        onClick={(event) =>
                            setMenuAnchorEl(event.currentTarget)
                        }
                    >
                        <MoreHorizIcon ref={overflowMenuIconRef} />
                    </IconButton>
                    <ContextMenu
                        id="collection-options"
                        anchorEl={menuAnchorEl}
                        open={!!menuAnchorEl}
                        onClose={() => setMenuAnchorEl(null)}
                        onClick={() => setMenuAnchorEl(null)}
                        slotProps={{
                            list: {
                                "aria-labelledby": "collection-options-trigger",
                            },
                        }}
                        anchorOrigin={{
                            vertical: "bottom",
                            horizontal: "right",
                        }}
                        transformOrigin={{
                            vertical: "top",
                            horizontal: "right",
                        }}
                    >
                        {validMenuOptions}
                    </ContextMenu>
                </>
            )}
            <CollectionSortOrderMenu
                {...sortOrderMenuVisibilityProps}
                overflowMenuIconRef={overflowMenuIconRef}
                sortAsc={activeCollection?.pubMagicMetadata?.data.asc ?? false}
                sortBy={
                    activeCollection?.pubMagicMetadata?.data.sortBy ===
                    "fileName"
                        ? "fileName"
                        : "date"
                }
                onSort={changeSortOrder}
            />
        </Box>
    );
};

interface OptionProps {
    disabled?: boolean;
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
}) => {
    const isSmallWidth = useIsSmallWidth();

    return (
        <Stack
            direction="row"
            sx={{
                alignItems: "center",
                gap: "16px",
                "&:empty": { display: "none" },
            }}
        >
            {showEmptyTrashQuickOption(collectionSummary) && (
                <EmptyTrashQuickOption
                    disabled={hasActiveFileSelection}
                    onClick={onEmptyTrashClick}
                />
            )}
            {(!isSmallWidth || collectionSummary.type == "hiddenItems") &&
                showDownloadQuickOption(collectionSummary) &&
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
            {!isSmallWidth && showShareQuickOption(collectionSummary) && (
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
};

const showEmptyTrashQuickOption = ({ type, fileCount }: CollectionSummary) =>
    type == "trash" && fileCount > 0;

const EmptyTrashQuickOption: React.FC<OptionProps> = ({
    disabled,
    onClick,
}) => (
    <Tooltip title={t("empty_trash")}>
        <span>
            <IconButton disabled={disabled} onClick={onClick}>
                <HugeiconsIcon
                    icon={Delete02Icon}
                    size={22}
                    strokeWidth={1.5}
                />
            </IconButton>
        </span>
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
};

const DownloadQuickOption: React.FC<DownloadQuickOptionProps> = ({
    collectionSummary,
    disabled,
    onClick,
}) => (
    <Tooltip title={downloadOptionLabel(collectionSummary)}>
        <span>
            <IconButton
                disabled={disabled}
                onClick={onClick}
                aria-label={downloadOptionLabel(collectionSummary)}
            >
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
                        icon={Download04Icon}
                        size={22}
                        strokeWidth={1.5}
                        aria-hidden
                    />
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

const downloadOptionLabel = ({ type }: CollectionSummary) =>
    type == "userFavorites"
        ? t("download_favorites")
        : type == "uncategorized"
          ? t("download_uncategorized")
          : type == "hiddenItems"
            ? t("download_hidden_items")
            : t("download_album");

const shareOptionLabel = (
    { attributes }: CollectionSummary,
    isQuickLinkAlbum: boolean,
) =>
    isQuickLinkAlbum
        ? t("manage_link")
        : attributes.has("userFavorites")
          ? t("share_favorites")
          : attributes.has("sharedIncoming")
            ? t("sharing_details")
            : attributes.has("shared")
              ? t("modify_sharing")
              : t("share_album");

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
    collectionSummary,
    isQuickLinkAlbum,
    onClick,
}) => (
    <Tooltip title={shareOptionLabel(collectionSummary, isQuickLinkAlbum)}>
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

interface CollectionSortOrderMenuProps {
    open: boolean;
    onClose: () => void;
    overflowMenuIconRef: React.RefObject<SVGSVGElement | null>;
    sortAsc: boolean;
    sortBy: CollectionSortBy;
    onSort: (sortBy: CollectionSortBy, asc: boolean) => void;
}

function CollectionSortOrderMenu({
    open,
    onClose,
    overflowMenuIconRef,
    sortAsc,
    sortBy,
    onSort,
}: CollectionSortOrderMenuProps) {
    const options: { by: CollectionSortBy; asc: boolean; label: string }[] = [
        { by: "date", asc: false, label: t("newest_first") },
        { by: "date", asc: true, label: t("oldest_first") },
        { by: "fileName", asc: true, label: t("album_sort_name_asc") },
        { by: "fileName", asc: false, label: t("album_sort_name_desc") },
    ];
    return (
        <ContextMenu
            id="collection-files-sort"
            anchorEl={overflowMenuIconRef.current}
            open={open}
            onClose={onClose}
            slotProps={{ list: { "aria-label": t("sort_by") } }}
            anchorOrigin={{ vertical: "bottom", horizontal: "right" }}
            transformOrigin={{ vertical: "top", horizontal: "right" }}
        >
            {options.map(({ by, asc, label }) => (
                <ContextMenuItem
                    key={`${by}-${asc}`}
                    onClick={() => {
                        onSort(by, asc);
                        onClose();
                    }}
                >
                    {label}
                    {sortBy === by && sortAsc === asc && (
                        <CheckIcon sx={{ ml: "auto" }} />
                    )}
                </ContextMenuItem>
            ))}
        </ContextMenu>
    );
}
