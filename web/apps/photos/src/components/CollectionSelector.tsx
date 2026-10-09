import {
    CreateAlbumTile,
    CollectionDialogSearchField as SearchField,
    CollectionTileButton as TileButton,
    CollectionTileTextOverlay as TopGradientOverlay,
} from "@/components/CollectionDialog/Primitives";
import {
    collectionDialogFullScreenQuery,
    collectionDialogBodyMutedSx as countSx,
    collectionDialogDividerSx as dividerSx,
    collectionDialogHeaderActionsSx as headerActionsSx,
    collectionDialogHeaderRowSx as headerRowSx,
    collectionDialogHeaderSx as headerSx,
    collectionDialogIconButtonSx as iconButtonSx,
    collectionDialogNoResultsSx as noResultsSx,
    collectionDialogPaperSx as paperSx,
    collectionDialogTitleSx as titleSx,
} from "@/components/CollectionDialog/styles";
import { CollectionsSortOptions } from "@/components/CollectionsSortOptions";
import ArchiveIcon from "@mui/icons-material/Archive";
import CloseIcon from "@mui/icons-material/Close";
import FavoriteIcon from "@mui/icons-material/Favorite";
import PushPinIcon from "@mui/icons-material/PushPin";
import {
    Box,
    Dialog,
    IconButton,
    Stack,
    Tooltip,
    Typography,
    useMediaQuery,
} from "@mui/material";
import type { ModalVisibilityProps } from "ente-base/components/utils/modal";
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
    const [sortBy, setSortBy] =
        useCollectionSelectorSortByLocalState("name-asc");
    const [filteredCollections, setFilteredCollections] = useState<
        CollectionSummary[]
    >([]);

    const handleExited = useCallback(() => {
        setSearchTerm("");
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

                const isUserFavorites =
                    collectionSummary.type === "userFavorites";
                if (
                    attributes.action === "add" ||
                    attributes.action === "move"
                ) {
                    return (
                        canAddToCollection(collectionSummary) &&
                        !isUserFavorites
                    );
                }
                if (attributes.action === "upload") {
                    return (
                        (canAddToCollection(collectionSummary) ||
                            collectionSummary.type === "uncategorized") &&
                        !isUserFavorites
                    );
                }
                if (attributes.action === "restore") {
                    return (
                        (canMoveToCollection(collectionSummary) ||
                            collectionSummary.type === "uncategorized") &&
                        !isUserFavorites
                    );
                }
                return (
                    canMoveToCollection(collectionSummary) && !isUserFavorites
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
        if (!searchTerm.trim()) return filteredCollections;
        const searchLower = searchTerm.toLowerCase();
        return filteredCollections.filter((collectionSummary) =>
            collectionSummary.name.toLowerCase().includes(searchLower),
        );
    }, [filteredCollections, searchTerm]);

    const showCreateButton =
        !searchTerm.trim() ||
        t("create_albums").toLowerCase().includes(searchTerm.toLowerCase());

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
                paper: { sx: paperSx },
                transition: { onExited: handleExited },
            }}
        >
            <Stack sx={headerSx}>
                <Stack direction="row" sx={headerRowSx}>
                    <Stack sx={{ minWidth: 0, gap: "2px" }}>
                        <Typography sx={titleSx}>
                            {collectionSelectorTitle(action)}
                        </Typography>
                        <Typography sx={countSx}>
                            {searchTerm
                                ? `${searchFilteredCollections.length} / ${filteredCollections.length} ${t("albums")}`
                                : t("albums_count", {
                                      count: filteredCollections.length,
                                  })}
                        </Typography>
                    </Stack>
                    <Stack direction="row" sx={headerActionsSx}>
                        <CollectionsSortOptions
                            activeSortBy={sortBy}
                            onChangeSortBy={setSortBy}
                            nestedInDialog
                            variant="v2"
                        />
                        <IconButton
                            aria-label={t("close")}
                            onClick={handleClose}
                            sx={iconButtonSx}
                        >
                            <CloseIcon sx={{ fontSize: 18 }} />
                        </IconButton>
                    </Stack>
                </Stack>
                <SearchField value={searchTerm} onChange={setSearchTerm} />
            </Stack>
            <Box sx={dividerSx} />
            {searchFilteredCollections.length === 0 && !showCreateButton ? (
                <Box sx={noResultsSx}>
                    <Typography sx={{ color: "text.muted" }}>
                        {t("no_results")}
                    </Typography>
                </Box>
            ) : (
                <Box sx={gridSx}>
                    {showCreateButton && (
                        <CreateAlbumTile onClick={onCreateCollection} />
                    )}
                    {searchFilteredCollections.map((collectionSummary) => (
                        <CollectionSummaryButton
                            key={collectionSummary.id}
                            collectionSummary={collectionSummary}
                            onClick={handleCollectionSummaryClick}
                        />
                    ))}
                </Box>
            )}
        </Dialog>
    );
};

const collectionSelectorTitle = (action: CollectionSelectorAction) => {
    switch (action) {
        case "upload":
            return t("upload_to_album");
        case "add":
            return t("add_to_album");
        case "move":
            return t("move_to_album");
        case "restore":
            return t("restore_to_album");
        case "unhide":
            return t("unhide_to_album");
    }
};

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

const gridSx = {
    flex: 1,
    minHeight: 0,
    p: "16px 20px 20px",
    display: "grid",
    gridTemplateColumns: "repeat(3, minmax(0, 1fr))",
    gridAutoRows: "max-content",
    gap: "8px",
    alignContent: "start",
    overflowY: "auto",
};
interface CollectionSummaryButtonProps {
    collectionSummary: CollectionSummary;
    onClick: (collectionSummaryID: number) => void;
}

const CollectionSummaryButton: React.FC<CollectionSummaryButtonProps> = ({
    collectionSummary,
    onClick,
}) => {
    const isFavorite = collectionSummary.type === "userFavorites";
    const isPinned =
        collectionSummary.attributes.has("pinned") ||
        collectionSummary.attributes.has("shareePinned");
    const isArchived = collectionSummary.attributes.has("archived");

    return (
        <ItemCard
            TileComponent={TileButton}
            coverFile={collectionSummary.coverFile}
            onClick={() => onClick(collectionSummary.id)}
        >
            <TopGradientOverlay>
                <Tooltip title={collectionSummary.name} arrow>
                    <Typography
                        sx={{
                            fontSize: 14,
                            lineHeight: "20px",
                            fontWeight: 500,
                            overflow: "hidden",
                            textOverflow: "ellipsis",
                            display: "-webkit-box",
                            WebkitLineClamp: 3,
                            WebkitBoxOrient: "vertical",
                        }}
                    >
                        {collectionSummary.name}
                    </Typography>
                </Tooltip>
            </TopGradientOverlay>
            {(isFavorite || isPinned || isArchived) && (
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
                        <FavoriteIcon sx={{ fontSize: 20, color: "white" }} />
                    )}
                    {isPinned && (
                        <PushPinIcon sx={{ fontSize: 20, color: "white" }} />
                    )}
                    {isArchived && (
                        <ArchiveIcon sx={{ fontSize: 20, color: "white" }} />
                    )}
                </Box>
            )}
        </ItemCard>
    );
};
