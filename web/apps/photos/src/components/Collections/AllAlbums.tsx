// TODO: Audit this file.
import {
    CreateAlbumTile,
    CollectionDialogSearchField as SearchField,
    CollectionTileButton as TileButton,
    CollectionTileTextOverlay as TileTextOverlay,
} from "@/components/CollectionDialog/Primitives";
import {
    collectionDialogBodyMutedSx as bodyMutedSx,
    collectionDialogFullScreenQuery,
    collectionDialogDividerSx as dividerSx,
    collectionDialogHeaderActionsSx as headerActionsSx,
    collectionDialogHeaderRowSx as headerRowSx,
    collectionDialogHeaderSx as headerSx,
    collectionDialogIconButtonSx as iconButtonSx,
    collectionDialogNoResultsSx as noResultsSx,
    collectionDialogPaperSx as paperSx,
    collectionDialogSurfaceStroke as surfaceStroke,
    collectionDialogSurfaceStrokeDark as surfaceStrokeDark,
    collectionDialogTitleSx as titleSx,
} from "@/components/CollectionDialog/styles";
import { CollectionsSortOptions } from "@/components/CollectionsSortOptions";
import type { RemotePullOpts } from "@/components/gallery";
import { StarIcon } from "@/components/icons/StarIcon";
import { Delete02Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import ArrowForwardIcon from "@mui/icons-material/ArrowForward";
import CloseIcon from "@mui/icons-material/Close";
import PushPinIcon from "@mui/icons-material/PushPin";
import {
    Box,
    Button,
    Dialog,
    DialogTitle,
    IconButton,
    Paper,
    Snackbar,
    Stack,
    ToggleButton,
    ToggleButtonGroup,
    Tooltip,
    Typography,
    useMediaQuery,
    type SxProps,
    type Theme,
} from "@mui/material";
import { ensureLocalUser } from "ente-accounts/services/user";
import { FilledIconButton } from "ente-base/components/mui";
import { SingleInputDialog } from "ente-base/components/SingleInputDialog";
import { useModalVisibility } from "ente-base/components/utils/modal";
import { useBaseContext } from "ente-base/context";
import { SlideUpTransition } from "ente-new/photos/components/mui/SlideUpTransition";
import { ItemCard } from "ente-new/photos/components/Tiles";
import {
    createAlbum,
    createHiddenAlbum,
    deleteCollection,
    isArchivedCollection,
    isDefaultHiddenCollection,
} from "ente-new/photos/services/collection";
import {
    isBulkDeletableEmptyAlbum,
    type CollectionsSortBy,
    type CollectionSummary,
} from "ente-new/photos/services/collection-summary";
import {
    savedCollectionFiles,
    savedCollections,
} from "ente-new/photos/services/photos-fdb";
import { usePhotosAppContext } from "ente-new/photos/types/context";
import { t } from "i18next";
import memoize from "memoize-one";
import React, { useEffect, useMemo, useRef, useState } from "react";
import AutoSizer from "react-virtualized-auto-sizer";
import {
    areEqual,
    FixedSizeList,
    type ListChildComponentProps,
} from "react-window";

type AlbumFilter = "all" | "shared" | "received" | "links" | "empty-albums";

const albumFilters: {
    value: AlbumFilter;
    label: () => string;
    title: () => string;
}[] = [
    { value: "all", label: () => t("all"), title: () => t("all_albums") },
    {
        value: "shared",
        label: () => t("shared_albums_label"),
        title: () => t("shared_albums_title"),
    },
    {
        value: "received",
        label: () => t("received_albums_label"),
        title: () => t("received_albums_title"),
    },
    {
        value: "links",
        label: () => t("links_albums_label"),
        title: () => t("links_albums_title"),
    },
    {
        value: "empty-albums",
        label: () => t("empty_albums"),
        title: () => t("empty_albums_title"),
    },
];

const matchesAlbumFilter = (
    cs: CollectionSummary,
    albumFilter: AlbumFilter,
) => {
    switch (albumFilter) {
        case "all":
            return true;
        case "shared":
            return (
                !cs.attributes.has("sharedIncoming") &&
                !cs.attributes.has("quickLink") &&
                (cs.attributes.has("sharedOutgoing") ||
                    cs.attributes.has("sharedViaLink"))
            );
        case "received":
            return cs.attributes.has("sharedIncoming");
        case "links":
            return cs.attributes.has("quickLink");
        case "empty-albums":
            return isBulkDeletableEmptyAlbum(cs);
    }
};

interface AllAlbums {
    open: boolean;
    onClose: () => void;
    collectionSummaries: CollectionSummary[];
    onSelectCollectionID: (id: number) => void;
    collectionsSortBy: CollectionsSortBy;
    onChangeCollectionsSortBy: (by: CollectionsSortBy) => void;
    isInHiddenSection: boolean;
    canCreateAlbum: boolean;
    onRemotePull: (opts?: RemotePullOpts) => Promise<void>;
}

export const AllAlbums: React.FC<AllAlbums> = ({
    collectionSummaries,
    open,
    onClose,
    onSelectCollectionID,
    collectionsSortBy,
    onChangeCollectionsSortBy,
    isInHiddenSection,
    canCreateAlbum,
    onRemotePull,
}) => {
    const fullScreen = useMediaQuery(collectionDialogFullScreenQuery);
    const [searchTerm, setSearchTerm] = useState("");
    const [albumFilter, setAlbumFilter] = useState<AlbumFilter>("all");
    const { showMiniDialog } = useBaseContext();
    const { showNotification } = usePhotosAppContext();
    const { show: showAlbumNameInput, props: albumNameInputVisibilityProps } =
        useModalVisibility();
    const [albumCreatedToast, setAlbumCreatedToast] = useState<{
        open: boolean;
        albumId?: number;
        albumName?: string;
    }>({ open: false });

    const handleExited = () => {
        setSearchTerm("");
        setAlbumFilter("all");
    };

    const onCollectionClick = (collectionID: number) => {
        onSelectCollectionID(collectionID);
        onClose();
    };

    const handleCreateAlbum = (albumName: string) => {
        onClose();

        void (async () => {
            try {
                const newAlbum = isInHiddenSection
                    ? await createHiddenAlbum(albumName)
                    : await createAlbum(albumName);
                await onRemotePull();

                setAlbumCreatedToast({
                    open: true,
                    albumId: newAlbum.id,
                    albumName: albumName,
                });
            } catch {
                showNotification({
                    color: "critical",
                    title: t("generic_error_retry"),
                });
            }
        })();
    };

    const emptyAlbumCandidates = useMemo(
        () => collectionSummaries.filter(isBulkDeletableEmptyAlbum),
        [collectionSummaries],
    );
    const hasEnoughEmptyAlbums = emptyAlbumCandidates.length >= 3;

    const showDeleteEmptyAlbums =
        !isInHiddenSection &&
        hasEnoughEmptyAlbums &&
        albumFilter == "empty-albums" &&
        !searchTerm.trim();

    const visibleAlbumFilters = useMemo(
        () =>
            albumFilters.filter(({ value }) => {
                if (value == "all") return true;
                if (value == "empty-albums") return hasEnoughEmptyAlbums;

                return collectionSummaries.some((cs) =>
                    matchesAlbumFilter(cs, value),
                );
            }),
        [collectionSummaries, hasEnoughEmptyAlbums],
    );

    const activeFilterTitle = (
        albumFilters.find(({ value }) => value == albumFilter) ??
        albumFilters[0]!
    ).title();

    useEffect(() => {
        if (!visibleAlbumFilters.some(({ value }) => value == albumFilter)) {
            setAlbumFilter("all");
        }
    }, [albumFilter, visibleAlbumFilters]);

    const deleteEmptyAlbums = async (candidateIDs: number[]) => {
        let failedCount = 0;
        let confirmedCandidateIDs: number[];

        try {
            await onRemotePull({ strict: true });

            const [collections, collectionFiles] = await Promise.all([
                savedCollections(),
                savedCollectionFiles(),
            ]);
            const candidateIDSet = new Set(candidateIDs);
            const nonEmptyCollectionIDs = new Set(
                collectionFiles.map((file) => file.collectionID),
            );
            const userID = ensureLocalUser().id;
            confirmedCandidateIDs = collections
                .filter(
                    (collection) =>
                        candidateIDSet.has(collection.id) &&
                        !nonEmptyCollectionIDs.has(collection.id) &&
                        (collection.type == "album" ||
                            collection.type == "folder") &&
                        collection.owner.id == userID &&
                        !collection.sharees.length &&
                        !collection.publicURLs.length &&
                        !isArchivedCollection(collection) &&
                        !isDefaultHiddenCollection(collection),
                )
                .map((collection) => collection.id);
        } catch {
            showNotification({
                color: "critical",
                title: t("delete_empty_albums_failed", {
                    count: candidateIDs.length,
                }),
            });
            return;
        }

        if (!confirmedCandidateIDs.length) return;

        for (const id of confirmedCandidateIDs) {
            try {
                await deleteCollection(id, { keepFiles: true });
            } catch {
                failedCount++;
            }
        }

        let refreshFailed = false;
        try {
            await onRemotePull({ strict: true });
        } catch {
            refreshFailed = true;
        }

        if (failedCount > 0) {
            showNotification({
                color: "critical",
                title: t("delete_empty_albums_failed", { count: failedCount }),
            });
        } else if (refreshFailed) {
            showNotification({
                color: "critical",
                title: t("delete_empty_albums_refresh_failed"),
            });
        }
    };

    const handleDeleteEmptyAlbums = () => {
        const candidateIDs = emptyAlbumCandidates.map((cs) => cs.id);
        showMiniDialog({
            title: t("delete_empty_albums_title"),
            message: t("delete_empty_albums_message", {
                count: candidateIDs.length,
            }),
            continue: {
                text: t("delete"),
                color: "critical",
                action: () => deleteEmptyAlbums(candidateIDs),
            },
        });
    };

    const filteredCollectionSummaries = useMemo(() => {
        const albumFilteredCollectionSummaries =
            isInHiddenSection || albumFilter == "all"
                ? collectionSummaries
                : collectionSummaries.filter((cs) =>
                      matchesAlbumFilter(cs, albumFilter),
                  );

        if (!searchTerm.trim()) {
            return albumFilteredCollectionSummaries;
        }
        const searchLower = searchTerm.toLowerCase();
        return albumFilteredCollectionSummaries.filter((cs) =>
            cs.name.toLowerCase().includes(searchLower),
        );
    }, [albumFilter, collectionSummaries, isInHiddenSection, searchTerm]);

    const showCreateButton = useMemo(() => {
        if (!canCreateAlbum) return false;
        if (!isInHiddenSection && albumFilter != "all") return false;
        if (!searchTerm.trim()) {
            return true;
        }
        const searchLower = searchTerm.toLowerCase();
        const createText = t("new_album").toLowerCase();
        return createText.includes(searchLower);
    }, [albumFilter, canCreateAlbum, isInHiddenSection, searchTerm]);

    return (
        <>
            <Dialog
                {...{ open, onClose }}
                fullScreen={fullScreen}
                maxWidth={false}
                sx={dialogSx}
                slots={{ transition: SlideUpTransition }}
                slotProps={{
                    paper: { sx: paperSx },
                    transition: { onExited: handleExited },
                }}
            >
                <Stack sx={headerSx}>
                    <Stack direction="row" sx={headerRowSx}>
                        <Stack sx={{ minWidth: 0, gap: "2px" }}>
                            <Typography sx={titleSx}>
                                {isInHiddenSection
                                    ? t("all_hidden_albums")
                                    : activeFilterTitle}
                            </Typography>
                            <Typography sx={bodyMutedSx}>
                                {t("albums_count", {
                                    count: filteredCollectionSummaries.length,
                                })}
                            </Typography>
                        </Stack>
                        <Stack direction="row" sx={headerActionsSx}>
                            <CollectionsSortOptions
                                activeSortBy={collectionsSortBy}
                                onChangeSortBy={onChangeCollectionsSortBy}
                                nestedInDialog
                                variant="v2"
                            />
                            <IconButton
                                aria-label={t("close")}
                                onClick={onClose}
                                sx={iconButtonSx}
                            >
                                <CloseIcon sx={{ fontSize: 18 }} />
                            </IconButton>
                        </Stack>
                    </Stack>
                    {!isInHiddenSection && visibleAlbumFilters.length > 1 && (
                        <ToggleButtonGroup
                            exclusive
                            value={albumFilter}
                            aria-label={t("filter_albums")}
                            onChange={(_, nextValue: AlbumFilter | null) => {
                                if (nextValue) setAlbumFilter(nextValue);
                            }}
                            sx={filterPillsSx}
                        >
                            {visibleAlbumFilters.map((filter) => (
                                <ToggleButton
                                    key={filter.value}
                                    value={filter.value}
                                >
                                    {filter.label()}
                                </ToggleButton>
                            ))}
                        </ToggleButtonGroup>
                    )}
                    <SearchField value={searchTerm} onChange={setSearchTerm} />
                </Stack>
                <Box sx={dividerSx} />
                <AllAlbumsContent
                    collectionSummaries={filteredCollectionSummaries}
                    onCollectionClick={onCollectionClick}
                    hasSearchQuery={!!searchTerm.trim()}
                    showCreateButton={showCreateButton}
                    onCreateAlbum={showAlbumNameInput}
                    reserveFooterSpace={showDeleteEmptyAlbums}
                />
                {showDeleteEmptyAlbums && (
                    <Box sx={sweepFooterSx}>
                        <Button
                            startIcon={
                                <HugeiconsIcon
                                    icon={Delete02Icon}
                                    size={22}
                                    strokeWidth={1.5}
                                />
                            }
                            onClick={handleDeleteEmptyAlbums}
                            sx={sweepButtonSx}
                        >
                            {t("delete_empty_albums")}
                        </Button>
                    </Box>
                )}
            </Dialog>
            <SingleInputDialog
                {...albumNameInputVisibilityProps}
                variant="v2"
                title={t("new_album")}
                label={t("album_name")}
                submitButtonTitle={t("create")}
                onSubmit={handleCreateAlbum}
            />
            <Snackbar
                open={albumCreatedToast.open}
                anchorOrigin={{ horizontal: "right", vertical: "bottom" }}
            >
                <Paper sx={{ width: "min(360px, 100svw)" }}>
                    <DialogTitle>
                        <Stack
                            direction="row"
                            sx={{
                                justifyContent: "space-between",
                                alignItems: "center",
                            }}
                        >
                            <Box>
                                <Typography variant="h3">
                                    {t("album_created")}
                                </Typography>
                                <Typography
                                    sx={[bodyMutedSx, { marginTop: "4px" }]}
                                >
                                    {albumCreatedToast.albumName &&
                                    albumCreatedToast.albumName.length > 16
                                        ? albumCreatedToast.albumName.substring(
                                              0,
                                              16,
                                          ) + "..."
                                        : albumCreatedToast.albumName}
                                </Typography>
                            </Box>
                            <Stack direction="row" sx={{ gap: 1 }}>
                                <FilledIconButton
                                    onClick={() => {
                                        if (albumCreatedToast.albumId) {
                                            onSelectCollectionID(
                                                albumCreatedToast.albumId,
                                            );
                                        }
                                        setAlbumCreatedToast((prev) => ({
                                            ...prev,
                                            open: false,
                                        }));
                                    }}
                                >
                                    <ArrowForwardIcon />
                                </FilledIconButton>
                                <FilledIconButton
                                    onClick={() =>
                                        setAlbumCreatedToast((prev) => ({
                                            ...prev,
                                            open: false,
                                        }))
                                    }
                                >
                                    <CloseIcon />
                                </FilledIconButton>
                            </Stack>
                        </Stack>
                    </DialogTitle>
                </Paper>
            </Snackbar>
        </>
    );
};

const sweepInset = 12;
const sweepButtonRadius = 20;
const dialogSx: SxProps<Theme> = {
    "& .MuiDialog-container": { justifyContent: "flex-end" },
    "& .MuiDialog-paper": {
        borderRadius: `${sweepButtonRadius + sweepInset}px`,
        [`@media ${collectionDialogFullScreenQuery}`]: { borderRadius: 0 },
    },
};
const sweepFooterSx = {
    position: "absolute",
    insetInline: 0,
    bottom: `${sweepInset}px`,
    px: `${sweepInset}px`,
    display: "flex",
    pointerEvents: "none",
};
const sweepButtonSx: SxProps<Theme> = (theme) => ({
    pointerEvents: "auto",
    flex: 1,
    height: 52,
    borderRadius: `${sweepButtonRadius}px`,
    border: `1px solid ${surfaceStroke}`,
    backgroundColor: "fixed.white",
    color: "fixed.black",
    fontSize: 14,
    lineHeight: "20px",
    fontWeight: 500,
    letterSpacing: "inherit",
    boxShadow: "0 2px 8px rgba(0 0 0 / 0.08)",
    "&:hover": { backgroundColor: "#eaeaea" },
    ...theme.applyStyles("dark", { borderColor: surfaceStrokeDark }),
});

const filterPillsSx = (theme: Theme) => ({
    display: "flex",
    gap: "8px",
    "& .MuiToggleButtonGroup-grouped": {
        flex: "1 1 0",
        minWidth: 0,
        marginLeft: "0 !important",
        padding: "10px 12px",
        border: 0,
        borderRadius: "16px !important",
        color: "text.muted",
        backgroundColor: "background.paper",
        fontSize: "14px",
        lineHeight: "20px",
        fontWeight: 500,
        letterSpacing: "-0.011em",
        textTransform: "none",
        whiteSpace: "nowrap",
        overflow: "hidden",
        textOverflow: "ellipsis",
        transition: theme.transitions.create("background-color", {
            duration: 120,
        }),
        "&:hover": { backgroundColor: "fill.faintHover", color: "text.base" },
        "&:focus-visible": {
            outline: `1px solid ${theme.vars.palette.stroke.base}`,
            outlineOffset: 2,
        },
        ...theme.applyStyles("dark", {
            "&:not(.Mui-selected)": {
                backgroundColor: "rgba(255 255 255 / 0.12)",
            },
        }),
        "&.Mui-selected": {
            backgroundColor: "accent.main",
            color: "accent.contrastText",
        },
        "&.Mui-selected:hover": { backgroundColor: "accent.dark" },
    },
});
const GridColumns = 3;
const GridGap = 8;
const GridPaddingInline = 20;
const GridPaddingBlockStart = 16;
const GridPaddingBlockEnd = 20;
const GridFooterHeight = 88;

interface ItemData {
    collectionRowList: (CollectionSummary | "create")[][];
    onCollectionClick: (id: number) => void;
    onCreateAlbum: () => void;
    tileSize: number;
}

const createItemData = memoize(
    (
        collectionRowList: (CollectionSummary | "create")[][],
        onCollectionClick: (id: number) => void,
        onCreateAlbum: () => void,
        tileSize: number,
    ) => ({ collectionRowList, onCollectionClick, onCreateAlbum, tileSize }),
);

const AlbumsRow = React.memo(
    ({
        data,
        index,
        style,
        isScrolling,
    }: ListChildComponentProps<ItemData>) => {
        const {
            collectionRowList,
            onCollectionClick,
            onCreateAlbum,
            tileSize,
        } = data;
        const collectionRow = collectionRowList[index]!;
        return (
            <div style={style}>
                <Stack
                    direction="row"
                    sx={{
                        "--tile-size": `${tileSize}px`,
                        px: `${GridPaddingInline}px`,
                        gap: `${GridGap}px`,
                        height: tileSize,
                    }}
                >
                    {collectionRow.map((item) =>
                        item === "create" ? (
                            <CreateAlbumTile
                                key="create"
                                onClick={onCreateAlbum}
                            />
                        ) : (
                            <AlbumCard
                                key={item.id}
                                isScrolling={isScrolling}
                                onCollectionClick={onCollectionClick}
                                collectionSummary={item}
                            />
                        ),
                    )}
                </Stack>
            </div>
        );
    },
    areEqual,
);

interface AllAlbumsContentProps {
    collectionSummaries: CollectionSummary[];
    onCollectionClick: (id: number) => void;
    hasSearchQuery: boolean;
    showCreateButton: boolean;
    onCreateAlbum: () => void;
    reserveFooterSpace: boolean;
}

const AllAlbumsContent: React.FC<AllAlbumsContentProps> = ({
    collectionSummaries,
    onCollectionClick,
    hasSearchQuery,
    showCreateButton,
    onCreateAlbum,
    reserveFooterSpace,
}) => {
    const refreshInProgress = useRef(false);
    const shouldRefresh = useRef(false);

    const [collectionRowList, setCollectionRowList] = useState<
        (CollectionSummary | "create")[][]
    >([]);

    useEffect(() => {
        const main = () => {
            if (refreshInProgress.current) {
                shouldRefresh.current = true;
                return;
            }
            refreshInProgress.current = true;

            const collectionRowList: (CollectionSummary | "create")[][] = [];
            let index = 0;

            if (showCreateButton) {
                const firstRow: (CollectionSummary | "create")[] = ["create"];
                for (
                    let i = 1;
                    i < GridColumns && index < collectionSummaries.length;
                    i++
                ) {
                    firstRow.push(collectionSummaries[index++]!);
                }
                collectionRowList.push(firstRow);
            }

            while (index < collectionSummaries.length) {
                const collectionRow: (CollectionSummary | "create")[] = [];
                for (
                    let i = 0;
                    i < GridColumns && index < collectionSummaries.length;
                    i++
                ) {
                    collectionRow.push(collectionSummaries[index++]!);
                }
                collectionRowList.push(collectionRow);
            }
            setCollectionRowList(collectionRowList);
            refreshInProgress.current = false;
            if (shouldRefresh.current) {
                shouldRefresh.current = false;
                setTimeout(main, 0);
            }
        };
        main();
    }, [collectionSummaries, showCreateButton]);

    if (
        hasSearchQuery &&
        collectionSummaries.length === 0 &&
        !showCreateButton
    ) {
        return (
            <Box sx={noResultsSx}>
                <Typography sx={bodyMutedSx}>{t("no_results")}</Typography>
            </Box>
        );
    }

    return (
        <Box
            sx={{
                flex: 1,
                minHeight: 0,
                pt: `${GridPaddingBlockStart}px`,
                pb: `${reserveFooterSpace ? GridFooterHeight : GridPaddingBlockEnd}px`,
            }}
        >
            <AutoSizer>
                {({ width, height }) => {
                    const tileSize = Math.max(
                        0,
                        Math.floor(
                            (width -
                                2 * GridPaddingInline -
                                (GridColumns - 1) * GridGap) /
                                GridColumns,
                        ),
                    );
                    return (
                        <FixedSizeList
                            {...{ width, height }}
                            itemCount={collectionRowList.length}
                            itemSize={tileSize + GridGap}
                            itemData={createItemData(
                                collectionRowList,
                                onCollectionClick,
                                onCreateAlbum,
                                tileSize,
                            )}
                        >
                            {AlbumsRow}
                        </FixedSizeList>
                    );
                }}
            </AutoSizer>
        </Box>
    );
};

interface AlbumCardProps {
    collectionSummary: CollectionSummary;
    onCollectionClick: (collectionID: number) => void;
    isScrolling?: boolean;
}

const AlbumCard: React.FC<AlbumCardProps> = ({
    onCollectionClick,
    collectionSummary,
    isScrolling,
}) => {
    const isFavorite = collectionSummary.type === "userFavorites";
    const isPinned = collectionSummary.attributes.has("pinned");

    return (
        <ItemCard
            TileComponent={TileButton}
            coverFile={collectionSummary.coverFile}
            onClick={() => onCollectionClick(collectionSummary.id)}
            isScrolling={isScrolling}
        >
            <TileTextOverlay>
                <Tooltip title={collectionSummary.name} arrow>
                    <Typography sx={albumNameSx}>
                        {collectionSummary.name}
                    </Typography>
                </Tooltip>
                <Typography sx={albumCountSx}>
                    {t("photos_count", { count: collectionSummary.fileCount })}
                </Typography>
            </TileTextOverlay>
            {(isFavorite || isPinned) && (
                <Box
                    sx={{
                        position: "absolute",
                        bottom: 8,
                        right: 8,
                        display: "flex",
                        gap: 0.5,
                    }}
                >
                    {isFavorite && (
                        <StarIcon sx={{ fontSize: 20, color: "white" }} />
                    )}
                    {isPinned && (
                        <PushPinIcon sx={{ fontSize: 20, color: "white" }} />
                    )}
                </Box>
            )}
        </ItemCard>
    );
};

const albumNameSx = {
    fontSize: 14,
    lineHeight: "20px",
    fontWeight: 500,
    overflow: "hidden",
    textOverflow: "ellipsis",
    display: "-webkit-box",
    WebkitLineClamp: 3,
    WebkitBoxOrient: "vertical",
};
const albumCountSx = {
    fontSize: 12,
    lineHeight: "16px",
    fontWeight: 500,
    opacity: 0.7,
};
