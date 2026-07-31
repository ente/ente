import CloseIcon from "@mui/icons-material/Close";
import FavoriteIcon from "@mui/icons-material/Favorite";
import PushPinIcon from "@mui/icons-material/PushPin";
import SearchIcon from "@mui/icons-material/Search";
import {
    Box,
    Dialog,
    DialogContent,
    DialogTitle,
    Divider,
    InputAdornment,
    Stack,
    styled,
    TextField,
    Tooltip,
    Typography,
    useMediaQuery,
} from "@mui/material";
import { FilledIconButton } from "ente-base/components/mui";
import type { ModalVisibilityProps } from "ente-base/components/utils/modal";
import type { Collection } from "ente-media/collection";
import { CollectionsSortOptions } from "ente-new/photos/components/CollectionsSortOptions";
import {
    ItemCard,
    LargeTileButton,
    LargeTileCreateNewButton,
    LargeTileTextOverlay,
} from "ente-new/photos/components/Tiles";
import {
    canAddToCollection,
    canMoveToCollection,
    collectionsSortBy,
    sortCollectionSummaries,
    type CollectionsSortBy,
    type CollectionSummaries,
    type CollectionSummary,
} from "ente-new/photos/services/collection-summary";
import { enableV2 } from "ente-new/photos/utils/feature-flags";
import { includes } from "ente-utils/type-guards";
import { t } from "i18next";
import React, {
    useCallback,
    useEffect,
    useMemo,
    useRef,
    useState,
} from "react";
import { CollectionSelectorV2 } from "./CollectionSelectorV2";

export type CollectionSelectorAction =
    | "upload"
    | "add"
    | "move"
    | "restore"
    | "unhide";

export interface CollectionSelectorAttributes {
    /**
     * The {@link action} modifies the title of the dialog, and also removes
     * some system collections that don't might not make sense for that
     * particular action.
     */
    action: CollectionSelectorAction;
    /**
     * Some actions, like "add" and "move", happen in the context of an existing
     * collection summary.
     *
     * In such cases, the ID of the collection summary can be set as the
     * {@link sourceCollectionID} to omit showing it in the list again.
     */
    sourceCollectionSummaryID?: number;
    /**
     * If set, this collection will be shown first in the list.
     *
     * This is useful for the "upload" action, where the user is viewing a
     * specific collection and might want to upload to it.
     */
    activeCollectionID?: number;
    /**
     * If true, only show hidden albums in the collection selector.
     *
     * This is used when uploading from the hidden albums section.
     */
    showHiddenCollections?: boolean;
    /**
     * Callback invoked when the user selects the option to create a new
     * collection.
     */
    onCreateCollection: () => void;
    /**
     * Callback invoked when the user selects one the existing collections
     * listed in the dialog.
     */
    onSelectCollection: (collection: Collection) => void;
    /**
     * Callback invoked when the user cancels the collection selection dialog.
     */
    onCancel?: () => void;
}

export type CollectionSelectorProps = ModalVisibilityProps & {
    /** Callback fired after the selector has finished closing. */
    onExited?: () => void;
    /**
     * The same {@link CollectionSelector} can be used for different
     * purposes by customizing the {@link attributes} prop before opening it.
     */
    attributes: CollectionSelectorAttributes | undefined;
    /**
     * The collections to list.
     *
     * The picker does not list all of the collection summaries, it filters
     * these provided list down to values which make sense for the
     * {@link attribute}'s {@link action}.
     *
     * See: [Note: Picking from selectable collection summaries].
     */
    collectionSummaries: CollectionSummaries;
    /**
     * A function to map from a collection summary ID to a {@link Collection}.
     *
     * This is invoked when the user makes a selection, to convert the ID of the
     * selected collection summary into a collection object that can be passed
     * as the {@link callback} property of {@link CollectionSelectorAttributes}.
     *
     * [Note: Picking from selectable collection summaries]
     *
     * In general, not all pseudo collections can be converted into a
     * collection. For example, there is no underlying collection corresponding
     * to the "All" pseudo collection. However, the implementation of
     * {@link CollectionSelector} is such that it filters the provided
     * {@link collectionSummaries} to only show those which, when selected, can
     * be mapped to an (existing or on-demand created) collection.
     */
    collectionForCollectionSummaryID: (
        collectionID: number,
    ) => Promise<Collection>;
};

/**
 * A dialog allowing the user to select one of their existing collections or
 * create a new one.
 *
 * The shared Photos UI flag chooses the restyled
 * {@link CollectionSelectorV2} variant or the classic implementation below.
 * Both share the exact same props and behaviour.
 */
export const CollectionSelector: React.FC<CollectionSelectorProps> = (
    props,
) => {
    return enableV2 ? (
        <CollectionSelectorV2 {...props} />
    ) : (
        <CollectionSelectorClassic {...props} />
    );
};

const CollectionSelectorClassic: React.FC<CollectionSelectorProps> = ({
    open,
    onClose,
    onExited,
    attributes,
    collectionSummaries,
    collectionForCollectionSummaryID,
}) => {
    // Make the dialog fullscreen if the screen is <= the dialog's max width.
    const isFullScreen = useMediaQuery("(max-width: 490px)");

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
        if (!attributes || !open) {
            return;
        }

        const activeCollectionID = attributes.activeCollectionID;
        const filteredCollections = [...collectionSummaries.values()].filter(
            (cs) => {
                if (cs.id === attributes.sourceCollectionSummaryID) {
                    return false;
                } else if (
                    attributes.action == "add" ||
                    attributes.action == "move"
                ) {
                    return canAddToCollection(cs) && cs.type != "userFavorites";
                } else if (attributes.action == "upload") {
                    return (
                        (canAddToCollection(cs) ||
                            cs.type == "uncategorized") &&
                        cs.type != "userFavorites"
                    );
                } else if (attributes.action == "restore") {
                    return (
                        (canMoveToCollection(cs) ||
                            cs.type == "uncategorized") &&
                        cs.type != "userFavorites"
                    );
                } else {
                    // "unhide"
                    return (
                        canMoveToCollection(cs) && cs.type != "userFavorites"
                    );
                }
            },
        );

        const collections = sortCollectionSummaries(filteredCollections, sortBy)
            .sort((a, b) => b.sortPriority - a.sortPriority)
            .sort((a, b) => {
                // Prioritize the active collection (if any) to appear first.
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
        if (!searchTerm.trim()) {
            return filteredCollections;
        }
        const searchLower = searchTerm.toLowerCase();
        return filteredCollections.filter((cs) =>
            cs.name.toLowerCase().includes(searchLower),
        );
    }, [filteredCollections, searchTerm]);

    const showCreateButton = useMemo(() => {
        if (!searchTerm.trim()) {
            return true;
        }
        const searchLower = searchTerm.toLowerCase();
        const createText = t("create_albums").toLowerCase();
        return createText.includes(searchLower);
    }, [searchTerm]);

    if (!filteredCollections.length) {
        return <></>;
    }

    if (!attributes) {
        return <></>;
    }

    const { action, onSelectCollection, onCancel, onCreateCollection } =
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
        <StyledDialog
            open={open}
            onClose={handleClose}
            fullWidth
            fullScreen={isFullScreen}
            slotProps={{
                paper: {
                    sx: {
                        maxWidth: "500px",
                        "@media (min-width: 491px)": { height: "100%" },
                    },
                },
                transition: { onExited: handleExited },
            }}
        >
            <DialogTitle>
                <Stack sx={{ gap: 1.5 }}>
                    <Stack direction="row" sx={{ gap: 1.5 }}>
                        <Stack sx={{ flex: 1 }}>
                            <Box>
                                <Typography variant="h5">
                                    {titleForAction(action)}
                                </Typography>
                                <Typography
                                    variant="small"
                                    sx={{
                                        color: "text.muted",
                                        fontWeight: "regular",
                                    }}
                                >
                                    {searchTerm
                                        ? `${searchFilteredCollections.length} / ${filteredCollections.length} ${t("albums")}`
                                        : t("albums_count", {
                                              count: filteredCollections.length,
                                          })}
                                </Typography>
                            </Box>
                        </Stack>
                        <CollectionsSortOptions
                            activeSortBy={sortBy}
                            onChangeSortBy={setSortBy}
                            nestedInDialog
                        />
                        <FilledIconButton onClick={handleClose}>
                            <CloseIcon />
                        </FilledIconButton>
                    </Stack>
                    <SearchField value={searchTerm} onChange={setSearchTerm} />
                </Stack>
            </DialogTitle>
            <Divider />
            {searchFilteredCollections.length === 0 && !showCreateButton ? (
                <NoResultsContent>
                    <Typography sx={{ color: "text.muted" }}>
                        {t("no_results")}
                    </Typography>
                </NoResultsContent>
            ) : (
                <DialogContent_>
                    {showCreateButton && (
                        <LargeTileCreateNewButton onClick={onCreateCollection}>
                            {t("create_albums")}
                        </LargeTileCreateNewButton>
                    )}
                    {searchFilteredCollections.map((collectionSummary) => (
                        <CollectionSummaryButton
                            key={collectionSummary.id}
                            collectionSummary={collectionSummary}
                            onClick={handleCollectionSummaryClick}
                        />
                    ))}
                </DialogContent_>
            )}
        </StyledDialog>
    );
};

const StyledDialog = styled(Dialog)(({ theme }) => ({
    "& .MuiDialogTitle-root": { padding: theme.spacing(2) },
    "& .MuiDialogContent-root": { padding: theme.spacing(2) },
}));

const DialogContent_ = styled(DialogContent)`
    display: grid;
    grid-template-columns: repeat(auto-fill, 150px);
    gap: 4px;
    align-content: start;

    @media (min-width: 491px) {
        justify-content: center;
    }
`;

const NoResultsContent = styled(DialogContent)`
    display: flex;
    justify-content: center;
    align-items: center;
    min-height: 154px;
`;

const titleForAction = (action: CollectionSelectorAction) => {
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

    return (
        <ItemCard
            TileComponent={LargeTileButton}
            coverFile={collectionSummary.coverFile}
            onClick={() => onClick(collectionSummary.id)}
        >
            <LargeTileTextOverlay>
                <Tooltip title={collectionSummary.name} arrow>
                    <Typography
                        sx={{
                            maxWidth: "240px",
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
            </LargeTileTextOverlay>
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
                        <FavoriteIcon sx={{ fontSize: 20, color: "white" }} />
                    )}
                    {isPinned && (
                        <PushPinIcon sx={{ fontSize: 20, color: "white" }} />
                    )}
                </Box>
            )}
        </ItemCard>
    );
};

interface SearchFieldProps {
    value: string;
    onChange: (value: string) => void;
}

const SearchField: React.FC<SearchFieldProps> = ({ value, onChange }) => {
    const inputRef = useRef<HTMLInputElement>(null);

    const handleClear = () => {
        onChange("");
        inputRef.current?.focus();
    };

    return (
        <TextField
            inputRef={inputRef}
            fullWidth
            size="small"
            placeholder={t("albums_search_hint")}
            value={value}
            onChange={(e) => onChange(e.target.value)}
            autoFocus
            slotProps={{
                input: {
                    startAdornment: (
                        <InputAdornment position="start">
                            <SearchIcon />
                        </InputAdornment>
                    ),
                    endAdornment: value && (
                        <InputAdornment
                            position="end"
                            sx={{ marginRight: "0 !important" }}
                        >
                            <CloseIcon
                                fontSize="small"
                                onClick={handleClear}
                                sx={{
                                    color: "stroke.muted",
                                    cursor: "pointer",
                                    "&:hover": { color: "text.base" },
                                }}
                            />
                        </InputAdornment>
                    ),
                },
            }}
            sx={{
                "& .MuiOutlinedInput-root": {
                    backgroundColor: "background.searchInput",
                    borderColor: "transparent",
                    "&:hover": { borderColor: "accent.light" },
                    "&.Mui-focused": {
                        borderColor: "accent.main",
                        boxShadow: "none",
                    },
                },
                "& .MuiInputBase-input": {
                    color: "text.base",
                    paddingTop: "8.5px !important",
                    paddingBottom: "8.5px !important",
                },
                "& .MuiInputAdornment-root": {
                    color: "stroke.muted",
                    marginTop: "0 !important",
                    marginRight: "8px",
                },
                "& .MuiOutlinedInput-notchedOutline": {
                    borderColor: "transparent",
                },
                "& .MuiInputBase-input::placeholder": {
                    color: "text.muted",
                    opacity: 1,
                },
            }}
        />
    );
};

/**
 * A hook that maintains the collection selector sort order both as in-memory
 * and local storage state.
 */
const useCollectionSelectorSortByLocalState = (
    initialValue: CollectionsSortBy,
) => {
    const key = "collectionSelectorSortBy";

    const [value, setValue] = useState(initialValue);

    useEffect(() => {
        const value = localStorage.getItem(key);
        if (value && includes(collectionsSortBy, value)) setValue(value);
    }, []);

    const setter = (value: CollectionsSortBy) => {
        localStorage.setItem(key, value);
        setValue(value);
    };

    return [value, setter] as const;
};
