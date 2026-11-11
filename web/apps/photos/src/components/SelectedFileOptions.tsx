import type { CollectionSelectorAttributes } from "@/components/CollectionSelector";
import {
    headerIconButtonSize,
    headerIconButtonSx,
    headerIconSize,
} from "@/components/gallery/header-styles";
import type { GalleryBarMode } from "@/components/gallery/reducer";
import {
    getAvailableFileActions,
    type FileContextAction,
} from "@/utils/file-actions";
import {
    AddSquareIcon,
    ArrowRight02Icon,
    Clock02Icon,
    Delete02Icon,
    Download01Icon,
    Download05Icon,
    Location01Icon,
    Navigation03Icon,
    RemoveCircleIcon,
    StarIcon,
    StarOffIcon,
    Time04Icon,
    Unarchive03Icon,
    UserAdd02Icon,
    ViewIcon,
    ViewOffSlashIcon,
} from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import CheckCircleIcon from "@mui/icons-material/CheckCircle";
import CheckCircleOutlinedIcon from "@mui/icons-material/CheckCircleOutlined";
import CloseIcon from "@mui/icons-material/Close";
import MoreHorizIcon from "@mui/icons-material/MoreHoriz";
import {
    Box,
    Button,
    IconButton,
    Tooltip,
    Typography,
    useMediaQuery,
    useTheme,
} from "@mui/material";
import { ContextMenu, ContextMenuItem } from "ente-base/components/ContextMenu";
import { SpacedRow } from "ente-base/components/containers";
import { useBaseContext } from "ente-base/context";
import type { Collection } from "ente-media/collection";
import type { CollectionSummary } from "ente-new/photos/services/collection-summary";
import { t } from "i18next";
import { useId, useLayoutEffect, useRef, useState } from "react";

const selectionToolbarGap = 8;
const selectionActionGap = 4;

export type FileOp =
    | "sendLink"
    | "download"
    | "fixTime"
    | "favorite"
    | "unfavorite"
    | "archive"
    | "unarchive"
    | "hide"
    | "trash"
    | "deletePermanently";

export type CollectionOp = "add" | "move" | "restore" | "unhide";

interface SelectedFileOptionsProps {
    barMode?: GalleryBarMode;
    isInSearchMode: boolean;
    selectedCollection?: Collection;
    collection: Collection | undefined;
    collectionSummary: CollectionSummary | undefined;
    selectedFileCount: number;
    selectedOwnFileCount: number;
    selectedFavoriteCount: number;
    onClearSelection: () => void;
    onDelete: () => void;
    onRemoveFilesFromCollection: (collection: Collection) => void;
    onOpenCollectionSelector: (
        attributes: CollectionSelectorAttributes,
    ) => void;
    createOnCreateForCollectionOp: (op: CollectionOp) => () => void;
    createOnSelectForCollectionOp: (
        op: CollectionOp,
    ) => (selectedCollection: Collection) => void;
    createFileOpHandler: (op: FileOp) => () => void;
    onShowAssignPersonDialog?: () => void;
    onEditLocation?: () => void;
    onSelectAll: () => void;
    isAllSelected: boolean;
}

export const SelectedFileOptions: React.FC<SelectedFileOptionsProps> = ({
    barMode,
    isInSearchMode,
    collection,
    collectionSummary,
    selectedFileCount,
    selectedOwnFileCount,
    selectedFavoriteCount,
    onClearSelection,
    onDelete,
    onRemoveFilesFromCollection,
    onOpenCollectionSelector,
    createOnCreateForCollectionOp,
    createOnSelectForCollectionOp,
    createFileOpHandler,
    onShowAssignPersonDialog,
    onEditLocation,
    onSelectAll,
    isAllSelected,
}) => {
    const { showMiniDialog } = useBaseContext();
    const isCompactViewport = useMediaQuery(useTheme().breakpoints.down("md"));
    const toolbarRef = useRef<HTMLDivElement>(null);
    const selectionControlsRef = useRef<HTMLDivElement>(null);
    const [actionsOverflow, setActionsOverflow] = useState(false);

    const handleFavorite = createFileOpHandler("favorite");
    const handleUnfavorite = createFileOpHandler("unfavorite");
    const handleFixTime = createFileOpHandler("fixTime");
    const handleDownload = createFileOpHandler("download");
    const handleSendLink = createFileOpHandler("sendLink");
    const handleArchive = createFileOpHandler("archive");
    const handleUnarchive = createFileOpHandler("unarchive");

    const handleRestore = () =>
        onOpenCollectionSelector({
            action: "restore",
            onCreateCollection: createOnCreateForCollectionOp("restore"),
            onSelectCollection: createOnSelectForCollectionOp("restore"),
        });

    const handleDeletePermanently = () =>
        showMiniDialog({
            title: t("delete_files_title"),
            kind: "warning",
            message: t("delete_files_message"),
            continue: {
                text: t("delete"),
                color: "critical",
                action: createFileOpHandler("deletePermanently"),
            },
        });

    const handleAddToCollection = () =>
        onOpenCollectionSelector({
            action: "add",
            sourceCollectionSummaryID: collectionSummary?.id,
            showHiddenCollections: barMode == "hidden-albums",
            onCreateCollection: createOnCreateForCollectionOp("add"),
            onSelectCollection: createOnSelectForCollectionOp("add"),
        });

    const isSharedIncoming =
        collectionSummary?.attributes.has("sharedIncoming");
    const isSharedOutgoing =
        collectionSummary?.attributes.has("sharedOutgoing");
    const isRemovingOthers = selectedFileCount != selectedOwnFileCount;
    const hasOnlyOwnFiles = selectedOwnFileCount > 0 && !isRemovingOthers;
    const favoriteAction =
        selectedFavoriteCount === 0
            ? "favorite"
            : selectedFavoriteCount === selectedFileCount
              ? "unfavorite"
              : "none";

    const handleRemoveFromCollection = () => {
        if (!collection) return;
        const remove = () => onRemoveFilesFromCollection(collection);

        if (isSharedIncoming) {
            if (isRemovingOthers) {
                showMiniDialog({
                    title: t("remove_from_album"),
                    message: t("remove_from_album_others_message"),
                    continue: {
                        text: t("remove"),
                        color: "critical",
                        action: remove,
                    },
                    cancel: t("cancel"),
                });
            } else {
                remove();
            }
            return;
        }

        if (isSharedOutgoing && isRemovingOthers) {
            showMiniDialog({
                title: t("remove_from_album"),
                message: t("remove_from_album_others_message"),
                continue: {
                    text: t("remove"),
                    color: "critical",
                    action: remove,
                },
            });
            return;
        }

        const onlyUserFiles = !isRemovingOthers;
        showMiniDialog({
            title: t("remove_from_album"),
            message: onlyUserFiles
                ? t("confirm_remove_message")
                : t("confirm_remove_incl_others_message"),
            continue: {
                text: t("yes_remove"),
                color: onlyUserFiles ? "primary" : "critical",
                action: remove,
            },
        });
    };

    const handleMoveToCollection = () => {
        onOpenCollectionSelector({
            action: "move",
            sourceCollectionSummaryID: collectionSummary?.id,
            showHiddenCollections: barMode == "hidden-albums",
            onCreateCollection: createOnCreateForCollectionOp("move"),
            onSelectCollection: createOnSelectForCollectionOp("move"),
        });
    };

    const handleHide = createFileOpHandler("hide");

    const handleUnhide = () => {
        onOpenCollectionSelector({
            action: "unhide",
            onCreateCollection: createOnCreateForCollectionOp("unhide"),
            onSelectCollection: createOnSelectForCollectionOp("unhide"),
        });
    };

    const toolbarActions = getAvailableFileActions({
        barMode,
        isInSearchMode,
        collectionSummary,
        hasOwnFiles: selectedOwnFileCount > 0,
        hasOnlyOwnFiles,
        showAddPerson: !!onShowAssignPersonDialog,
        showEditLocation: !!onEditLocation && hasOnlyOwnFiles,
    }).flatMap((action): FileContextAction[] => {
        if (action !== "favorite" && action !== "unfavorite") return [action];
        return favoriteAction === "none" ? [] : [favoriteAction];
    });

    const actionDetails = {
        sendLink: {
            label: t("send_link"),
            icon: Navigation03Icon,
            onClick: handleSendLink,
        },
        download: {
            label: t("download"),
            icon: Download01Icon,
            onClick: handleDownload,
        },
        fixTime: {
            label: t("fix_creation_time"),
            icon: Time04Icon,
            onClick: handleFixTime,
        },
        editLocation: {
            label: t("edit_location"),
            icon: Location01Icon,
            onClick: onEditLocation,
        },
        favorite: {
            label: t("favorite"),
            icon: StarIcon,
            onClick: handleFavorite,
        },
        unfavorite: {
            label: t("un_favorite"),
            icon: StarOffIcon,
            onClick: handleUnfavorite,
        },
        archive: {
            label: t("archive"),
            icon: Download05Icon,
            onClick: handleArchive,
        },
        unarchive: {
            label: t("unarchive"),
            icon: Unarchive03Icon,
            onClick: handleUnarchive,
        },
        hide: { label: t("hide"), icon: ViewOffSlashIcon, onClick: handleHide },
        unhide: { label: t("unhide"), icon: ViewIcon, onClick: handleUnhide },
        trash: { label: t("delete"), icon: Delete02Icon, onClick: onDelete },
        deletePermanently: {
            label: t("delete_permanently"),
            icon: Delete02Icon,
            onClick: handleDeletePermanently,
        },
        restore: {
            label: t("restore"),
            icon: Clock02Icon,
            onClick: handleRestore,
        },
        addToAlbum: {
            label: t("add"),
            icon: AddSquareIcon,
            onClick: handleAddToCollection,
        },
        moveToAlbum: {
            label: t("move"),
            icon: ArrowRight02Icon,
            onClick: handleMoveToCollection,
        },
        removeFromAlbum: {
            label: t("remove"),
            icon: RemoveCircleIcon,
            onClick: handleRemoveFromCollection,
        },
        addPerson: {
            label: t("add_a_person"),
            icon: UserAdd02Icon,
            onClick: onShowAssignPersonDialog,
        },
    } satisfies Record<
        FileContextAction,
        Omit<SelectionAction, "id" | "destructive">
    >;
    const actions = toolbarActions.map((id): SelectionAction => ({
        id,
        ...actionDetails[id],
        destructive: id === "trash" || id === "deletePermanently",
    }));
    const actionCount = actions.length;

    useLayoutEffect(() => {
        const toolbar = toolbarRef.current;
        const selectionControls = selectionControlsRef.current;
        if (!toolbar || !selectionControls || !actionCount) return;

        const actionRowWidth =
            actionCount * headerIconButtonSize +
            (actionCount - 1) * selectionActionGap;
        const measure = () => {
            const availableWidth =
                toolbar.getBoundingClientRect().width -
                selectionControls.getBoundingClientRect().width -
                selectionToolbarGap;
            setActionsOverflow(actionRowWidth > availableWidth);
        };

        measure();
        const observer = new ResizeObserver(measure);
        observer.observe(toolbar);
        observer.observe(selectionControls);
        return () => observer.disconnect();
    }, [actionCount]);

    return (
        <SpacedRow
            ref={toolbarRef}
            sx={{ flex: 1, minWidth: 0, gap: `${selectionToolbarGap}px` }}
        >
            <SpacedRow
                ref={selectionControlsRef}
                sx={{ gap: 1, flexShrink: 0 }}
            >
                <IconButton
                    onClick={onClearSelection}
                    aria-label={t("close")}
                    sx={headerIconButtonSx}
                >
                    <CloseIcon />
                </IconButton>
                <Typography>
                    {selectedFileCount == selectedOwnFileCount
                        ? t("selected_count", { selected: selectedFileCount })
                        : t("selected_and_yours_count", {
                              selected: selectedFileCount,
                              yours: selectedOwnFileCount,
                          })}
                </Typography>
                <SelectAllToggleButton
                    isAllSelected={isAllSelected}
                    onClick={isAllSelected ? onClearSelection : onSelectAll}
                />
            </SpacedRow>
            {isCompactViewport || actionsOverflow ? (
                <SelectionActionsMenu actions={actions} />
            ) : (
                <Box
                    sx={{
                        display: "flex",
                        flex: 1,
                        minWidth: 0,
                        overflowX: "auto",
                    }}
                >
                    <Box
                        sx={{
                            display: "flex",
                            flexShrink: 0,
                            ml: "auto",
                            gap: `${selectionActionGap}px`,
                            "& .MuiIconButton-root": headerIconButtonSx,
                        }}
                    >
                        {actions.map(
                            ({ id, label, icon, onClick, destructive }) => (
                                <Tooltip key={id} title={label}>
                                    <IconButton
                                        aria-label={label}
                                        onClick={onClick}
                                        sx={
                                            destructive
                                                ? { color: "critical.main" }
                                                : undefined
                                        }
                                    >
                                        <HugeiconsIcon
                                            icon={icon}
                                            aria-hidden
                                        />
                                    </IconButton>
                                </Tooltip>
                            ),
                        )}
                    </Box>
                </Box>
            )}
        </SpacedRow>
    );
};

interface SelectionAction {
    id: FileContextAction;
    label: string;
    icon: typeof Download01Icon;
    onClick: (() => void) | undefined;
    destructive: boolean;
}

const SelectionActionsMenu = ({ actions }: { actions: SelectionAction[] }) => {
    const menuID = useId();
    const [anchorEl, setAnchorEl] = useState<HTMLButtonElement | null>(null);
    if (!actions.length) return null;

    return (
        <>
            <IconButton
                id={`${menuID}-trigger`}
                aria-label={t("more_options")}
                aria-haspopup="menu"
                aria-expanded={!!anchorEl}
                aria-controls={anchorEl ? menuID : undefined}
                onClick={(event) => setAnchorEl(event.currentTarget)}
                sx={{ ...headerIconButtonSx, ml: "auto" }}
            >
                <MoreHorizIcon />
            </IconButton>
            <ContextMenu
                anchorEl={anchorEl}
                open={!!anchorEl}
                onClose={() => setAnchorEl(null)}
                anchorOrigin={{ vertical: "bottom", horizontal: "right" }}
                transformOrigin={{ vertical: "top", horizontal: "right" }}
                slotProps={{
                    list: {
                        id: menuID,
                        "aria-labelledby": `${menuID}-trigger`,
                    },
                }}
            >
                {actions.map(({ id, label, icon, onClick, destructive }) => (
                    <ContextMenuItem
                        key={id}
                        destructive={destructive}
                        onClick={() => {
                            setAnchorEl(null);
                            onClick?.();
                        }}
                    >
                        <HugeiconsIcon
                            icon={icon}
                            size={headerIconSize}
                            aria-hidden
                        />
                        {label}
                    </ContextMenuItem>
                ))}
            </ContextMenu>
        </>
    );
};

interface SelectAllToggleButtonProps {
    isAllSelected: boolean;
    onClick: () => void;
}

const SelectAllToggleButton: React.FC<SelectAllToggleButtonProps> = ({
    isAllSelected,
    onClick,
}) => (
    <Tooltip title={isAllSelected ? t("deselect_all") : t("select_all")}>
        <Button
            onClick={onClick}
            size="small"
            color="secondary"
            sx={{
                textTransform: "none",
                minWidth: "auto",
                px: 2,
                ml: 2,
                borderRadius: 9999,
                "& .MuiButton-endIcon > svg": {
                    width: headerIconSize,
                    height: headerIconSize,
                },
            }}
            endIcon={
                isAllSelected ? (
                    <CheckCircleIcon fontSize="small" />
                ) : (
                    <CheckCircleOutlinedIcon
                        fontSize="small"
                        sx={{ color: "text.muted" }}
                    />
                )
            }
        >
            {t("all")}
        </Button>
    </Tooltip>
);
