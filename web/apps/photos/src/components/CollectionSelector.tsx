import {
    CollectionDialogTileButton as AlbumButton,
    CollectionDialogTileCover as AlbumCover,
    CollectionDialogSearchField as SearchField,
} from "@/components/CollectionDialog/Primitives";
import {
    collectionDialogFullScreenQuery,
    collectionDialogHeaderActionsSx as headerActionsSx,
    collectionDialogHeaderRowSx as headerRowSx,
    collectionDialogHeaderSx as headerSx,
    collectionDialogIconButtonSx as iconButtonSx,
    collectionDialogNoResultsSx as noResultsSx,
    collectionDialogPaperSx as paperSx,
    collectionDialogTitleSx as titleSx,
} from "@/components/CollectionDialog/styles";
import { CollectionsSortOptions } from "@/components/CollectionsSortOptions";
import {
    Cancel01Icon,
    Image01Icon,
    ImageAdd02Icon,
} from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import ArchiveIcon from "@mui/icons-material/Archive";
import FavoriteIcon from "@mui/icons-material/Favorite";
import PushPinIcon from "@mui/icons-material/PushPin";
import {
    Box,
    Dialog,
    IconButton,
    Stack,
    Tab,
    Tabs,
    Typography,
    useMediaQuery,
    type Theme,
} from "@mui/material";
import { CenteredFill } from "ente-base/components/containers";
import type { ModalVisibilityProps } from "ente-base/components/utils/modal";
import { isSxArray } from "ente-base/components/utils/sx";
import type { Collection } from "ente-media/collection";
import { ItemCard } from "ente-new/photos/components/Tiles";
import {
    canAddToCollection,
    canMoveToCollection,
    collectionsSortBy,
    sortCollectionSummaries,
    type CollectionsSortBy,
    type CollectionSummaries,
    type CollectionSummary,
} from "ente-new/photos/services/collection-summary";
import { includes } from "ente-utils/type-guards";
import { t } from "i18next";
import React, { useCallback, useEffect, useMemo, useState } from "react";

type CollectionSelectorAction =
    "upload" | "add" | "move" | "restore" | "unhide";

export interface CollectionSelectorAttributes {
    action: CollectionSelectorAction;
    sourceCollectionSummaryID?: number;
    activeCollectionID?: number;
    showHiddenCollections?: boolean;
    onCreateCollection: () => void;
    onSelectCollection: (collection: Collection) => void;
    onCancel?: () => void;
}

type CollectionSelectorProps = ModalVisibilityProps & {
    onExited?: () => void;
    attributes: CollectionSelectorAttributes | undefined;
    collectionSummaries: CollectionSummaries;
    // Every listed summary must map to a real or on-demand collection.
    collectionForCollectionSummaryID: (
        collectionID: number,
    ) => Promise<Collection>;
};

export const CollectionSelector: React.FC<CollectionSelectorProps> = (
    props,
) => {
    const {
        open,
        onClose,
        onExited,
        attributes,
        collectionSummaries,
        collectionForCollectionSummaryID,
    } = props;

    const isFullScreen = useMediaQuery(collectionDialogFullScreenQuery);

    const [searchTerm, setSearchTerm] = useState("");
    const [scrollFade, setScrollFade] = useState(0);
    const [category, setCategory] = useState<
        "all" | "mine" | "shared" | "received"
    >("all");
    const [sortBy, setSortBy] =
        useCollectionSelectorSortByLocalState("name-asc");
    const [filteredCollections, setFilteredCollections] = useState<
        CollectionSummary[]
    >([]);

    const handleExited = useCallback(() => {
        setSearchTerm("");
        setScrollFade(0);
        setCategory("all");
        onExited?.();
    }, [onExited]);

    useEffect(() => {
        if (!attributes || !open) return;

        const activeCollectionID = attributes.activeCollectionID;
        const selectableCollections = [...collectionSummaries.values()].filter(
            (collectionSummary) => {
                if (
                    collectionSummary.id ===
                    attributes.sourceCollectionSummaryID
                ) {
                    return false;
                }

                if (
                    attributes.action === "move" &&
                    attributes.showHiddenCollections &&
                    collectionSummary.type === "hiddenItems"
                ) {
                    return true;
                }

                if (collectionSummary.type === "userFavorites") return false;
                const canSelect =
                    attributes.action === "restore" ||
                    attributes.action === "unhide"
                        ? canMoveToCollection
                        : canAddToCollection;
                return (
                    canSelect(collectionSummary) ||
                    ((attributes.action === "upload" ||
                        attributes.action === "restore") &&
                        collectionSummary.type === "uncategorized")
                );
            },
        );

        const collections = sortCollectionSummaries(
            selectableCollections,
            sortBy,
        )
            .sort((a, b) => b.sortPriority - a.sortPriority)
            .sort((a, b) => {
                if (a.id === activeCollectionID) return -1;
                if (b.id === activeCollectionID) return 1;
                return 0;
            });

        if (collections.length === 0) {
            onClose();
            attributes.onCreateCollection();
            handleExited();
        }

        setFilteredCollections(collections);
    }, [collectionSummaries, attributes, open, onClose, sortBy, handleExited]);

    const searchFilteredCollections = useMemo(() => {
        const searchLower = searchTerm.trim() ? searchTerm.toLowerCase() : "";
        return filteredCollections.filter((collectionSummary) => {
            const { attributes } = collectionSummary;
            const isReceived = attributes.has("sharedIncoming");
            const matchesCategory =
                category == "all" ||
                (category == "mine" && !isReceived) ||
                (category == "shared" &&
                    !isReceived &&
                    (attributes.has("sharedOutgoing") ||
                        attributes.has("sharedViaLink"))) ||
                (category == "received" && isReceived);
            return (
                matchesCategory &&
                collectionSummary.name.toLowerCase().includes(searchLower)
            );
        });
    }, [filteredCollections, searchTerm, category]);

    const showCreateButton =
        (category == "all" || category == "mine") &&
        (!searchTerm.trim() ||
            t("create_albums")
                .toLowerCase()
                .includes(searchTerm.toLowerCase()));

    if (!filteredCollections.length || !attributes) return null;

    const { action, onCancel, onCreateCollection, onSelectCollection } =
        attributes;

    const handleCollectionSummaryClick = async (id: number) => {
        onSelectCollection(await collectionForCollectionSummaryID(id));
        onClose();
    };

    const handleClose = () => {
        onCancel?.();
        onClose();
    };

    return (
        <Dialog
            open={open}
            onClose={handleClose}
            fullScreen={isFullScreen}
            maxWidth={false}
            slotProps={{
                paper: {
                    sx: [
                        ...(isSxArray(paperSx) ? paperSx : [paperSx]),
                        {
                            width: isFullScreen
                                ? "100%"
                                : "min(600px, calc(100svw - 64px))",
                            maxWidth: isFullScreen ? "100%" : 600,
                            maxHeight: isFullScreen
                                ? "100%"
                                : "min(600px, calc(100svh - 64px))",
                            boxSizing: "border-box",
                        },
                    ],
                },
                transition: { onExited: handleExited },
            }}
        >
            <Stack
                sx={{
                    ...headerSx,
                    gap: "20px",
                    pb: 0,
                    position: "relative",
                    zIndex: 1,
                    flexShrink: 0,
                }}
            >
                <Stack
                    direction="row"
                    sx={{ ...headerRowSx, alignItems: "center" }}
                >
                    <Typography
                        sx={{
                            ...titleSx,
                            fontFamily: '"Outfit Variable", sans-serif',
                        }}
                    >
                        {collectionSelectorTitle(action)}
                    </Typography>
                    <Stack direction="row" sx={headerActionsSx}>
                        <CollectionsSortOptions
                            activeSortBy={sortBy}
                            onChangeSortBy={setSortBy}
                            variant="v2"
                        />
                        <IconButton
                            aria-label={t("close")}
                            onClick={handleClose}
                            sx={iconButtonSx}
                        >
                            <HugeiconsIcon icon={Cancel01Icon} size={18} />
                        </IconButton>
                    </Stack>
                </Stack>
                <Stack sx={{ gap: "16px" }}>
                    <SearchField value={searchTerm} onChange={setSearchTerm} />
                    <Tabs
                        value={category}
                        onChange={(_, value: typeof category) =>
                            setCategory(value)
                        }
                        variant="scrollable"
                        scrollButtons="auto"
                        aria-label={t("filter_albums")}
                        sx={categoryTabsSx}
                    >
                        <Tab value="all" label={t("all")} />
                        <Tab value="mine" label="Ente" />
                        <Tab value="shared" label={t("shared_albums_label")} />
                        <Tab
                            value="received"
                            label={t("received_albums_label")}
                        />
                    </Tabs>
                </Stack>
            </Stack>
            {searchFilteredCollections.length === 0 && !showCreateButton ? (
                <Box sx={noResultsSx}>
                    <Typography sx={{ color: "text.muted" }}>
                        {t("no_results")}
                    </Typography>
                </Box>
            ) : (
                <Box
                    sx={gridSx}
                    style={{
                        maskImage: `linear-gradient(to bottom, rgba(0, 0, 0, ${1 - scrollFade}), #000 64px)`,
                    }}
                    onScroll={(event) =>
                        setScrollFade(
                            Math.min(
                                Math.max(event.currentTarget.scrollTop, 0) / 32,
                                1,
                            ),
                        )
                    }
                >
                    {showCreateButton && (
                        <AlbumTile onClick={onCreateCollection} />
                    )}
                    {searchFilteredCollections.map((collectionSummary) => (
                        <AlbumTile
                            key={collectionSummary.id}
                            collectionSummary={collectionSummary}
                            onClick={() =>
                                void handleCollectionSummaryClick(
                                    collectionSummary.id,
                                )
                            }
                        />
                    ))}
                </Box>
            )}
        </Dialog>
    );
};

const collectionSelectorTitle = (action: CollectionSelectorAction) =>
    t(
        {
            upload: "upload_to_album",
            add: "add_to_album",
            move: "move_to_album",
            restore: "restore_to_album",
            unhide: "unhide_to_album",
        }[action],
    );

const useCollectionSelectorSortByLocalState = (
    initialValue: CollectionsSortBy,
) => {
    const key = "collectionSelectorSortBy";
    const [value, setValue] = useState(initialValue);

    useEffect(() => {
        const storedValue = localStorage.getItem(key);
        if (storedValue && includes(collectionsSortBy, storedValue)) {
            setValue(storedValue);
        }
    }, []);

    const setter = (newValue: CollectionsSortBy) => {
        localStorage.setItem(key, newValue);
        setValue(newValue);
    };

    return [value, setter] as const;
};

const categoryTabsSx = (theme: Theme) => ({
    minHeight: 26,
    borderBottom: "1px solid",
    borderColor: "rgba(0 0 0 / 0.04)",
    ...theme.applyStyles("dark", { borderColor: "rgba(255 255 255 / 0.06)" }),
    "& .MuiTabs-list": { gap: "24px", px: "4px" },
    "& .MuiTabs-indicator": {
        height: 2,
        borderRadius: "1px",
        bgcolor: "text.base",
    },
    "& .MuiTab-root": {
        minWidth: 0,
        minHeight: 26,
        p: "0 0 8px",
        fontSize: 13,
        lineHeight: "16px",
        fontWeight: 500,
        textTransform: "none",
        color: "text.muted",
        "&.Mui-selected": { color: "text.base", fontWeight: 600 },
    },
});

const gridSx = {
    flex: 1,
    minHeight: 0,
    p: "16px 20px 20px",
    display: "grid",
    gridTemplateColumns: "repeat(4, minmax(0, 124px))",
    justifyContent: "space-between",
    "@media (width < 600px)": {
        gridTemplateColumns: "repeat(3, minmax(0, 1fr))",
    },
    "@media (width < 360px)": {
        gridTemplateColumns: "repeat(2, minmax(0, 1fr))",
    },
    gridAutoRows: "max-content",
    columnGap: "16px",
    rowGap: "24px",
    alignContent: "start",
    overflowY: "auto",
};
const AlbumTile: React.FC<{
    collectionSummary?: CollectionSummary;
    onClick: () => void;
}> = ({ collectionSummary, onClick }) => {
    const isFavorite = collectionSummary?.type === "userFavorites";
    const isPinned =
        collectionSummary?.attributes.has("pinned") ||
        collectionSummary?.attributes.has("shareePinned");
    const isArchived = collectionSummary?.attributes.has("archived");
    const name = collectionSummary?.name ?? t("new_album");
    const emptyCover = (
        <CenteredFill
            sx={{ position: "absolute", inset: 0, color: "text.muted" }}
        >
            <HugeiconsIcon
                icon={collectionSummary ? Image01Icon : ImageAdd02Icon}
                size={36}
                strokeWidth={1.5}
            />
        </CenteredFill>
    );

    return (
        <AlbumButton
            title={collectionSummary?.name}
            aria-label={collectionSummary ? undefined : name}
            onClick={onClick}
        >
            {collectionSummary ? (
                <ItemCard
                    TileComponent={AlbumCover}
                    coverFile={collectionSummary.coverFile}
                >
                    {!collectionSummary.coverFile && emptyCover}
                    {(isFavorite || isPinned || isArchived) && (
                        <Box
                            sx={{
                                position: "absolute",
                                bottom: 8,
                                left: 8,
                                display: "flex",
                                gap: 0.5,
                                color: "white",
                                filter: "drop-shadow(0 1px 2px rgba(0,0,0,.4))",
                            }}
                        >
                            {isFavorite && (
                                <FavoriteIcon sx={{ fontSize: 16 }} />
                            )}
                            {isPinned && <PushPinIcon sx={{ fontSize: 16 }} />}
                            {isArchived && (
                                <ArchiveIcon sx={{ fontSize: 16 }} />
                            )}
                        </Box>
                    )}
                </ItemCard>
            ) : (
                <AlbumCover>{emptyCover}</AlbumCover>
            )}
            <Stack
                component="span"
                sx={{ minWidth: 0, width: "100%", gap: "2px" }}
            >
                <Typography component="span" noWrap sx={albumNameSx}>
                    {name}
                </Typography>
                {collectionSummary && (
                    <Typography
                        component="span"
                        noWrap
                        sx={{
                            fontSize: 12,
                            lineHeight: "16px",
                            fontWeight: 500,
                            color: "text.muted",
                        }}
                    >
                        {t("album_items_count", {
                            count: collectionSummary.fileCount,
                        })}
                    </Typography>
                )}
            </Stack>
        </AlbumButton>
    );
};

const albumNameSx = { fontSize: 14, lineHeight: "20px", fontWeight: 500 };
