import type { CollectionSelectorAttributes } from "@/components/CollectionSelector";
import type { GalleryBarMode } from "@/components/gallery/reducer";
import { StarBorderIcon } from "@/components/icons/StarIcon";
import { StarOffIcon } from "@/components/icons/StarOffIcon";
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
import { Box, Button, IconButton, Tooltip, Typography } from "@mui/material";
import { SpacedRow } from "ente-base/components/containers";
import type { ButtonishProps } from "ente-base/components/mui";
import { useBaseContext } from "ente-base/context";
import type { Collection } from "ente-media/collection";
import type { CollectionSummary } from "ente-new/photos/services/collection-summary";
import { t } from "i18next";

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

    const handleFavorite = createFileOpHandler("favorite");
    const handleUnfavorite = createFileOpHandler("unfavorite");
    const handleFixTime = createFileOpHandler("fixTime");
    const handleDownload = createFileOpHandler("download");
    const handleSendLink = createFileOpHandler("sendLink");
    const handleArchive = createFileOpHandler("archive");
    const handleUnarchive = createFileOpHandler("unarchive");

    const handleDelete = () =>
        showMiniDialog({
            title: t("trash_files_title"),
            message: t("trash_files_message"),
            continue: {
                text: t("move_to_trash"),
                color: "critical",
                action: createFileOpHandler("trash"),
            },
        });

    const handleRestore = () =>
        onOpenCollectionSelector({
            action: "restore",
            onCreateCollection: createOnCreateForCollectionOp("restore"),
            onSelectCollection: createOnSelectForCollectionOp("restore"),
        });

    const handleDeletePermanently = () =>
        showMiniDialog({
            title: t("delete_files_title"),
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
        hasOnlyOwnFiles,
        showAddPerson: !!onShowAssignPersonDialog,
        showEditLocation: !!onEditLocation && hasOnlyOwnFiles,
    }).flatMap((action): FileContextAction[] => {
        if (action !== "favorite" && action !== "unfavorite") return [action];
        return favoriteAction === "none" ? [] : [favoriteAction];
    });

    const renderActionButton = (action: FileContextAction) => {
        switch (action) {
            case "sendLink":
                return <SendLinkButton key={action} onClick={handleSendLink} />;
            case "download":
                return <DownloadButton key={action} onClick={handleDownload} />;
            case "fixTime":
                return <FixTimeButton key={action} onClick={handleFixTime} />;
            case "editLocation":
                return onEditLocation ? (
                    <EditLocationButton key={action} onClick={onEditLocation} />
                ) : null;
            case "favorite":
                return <FavoriteButton key={action} onClick={handleFavorite} />;
            case "unfavorite":
                return (
                    <UnfavoriteButton key={action} onClick={handleUnfavorite} />
                );
            case "archive":
                return <ArchiveButton key={action} onClick={handleArchive} />;
            case "unarchive":
                return (
                    <UnarchiveButton key={action} onClick={handleUnarchive} />
                );
            case "hide":
                return <HideButton key={action} onClick={handleHide} />;
            case "unhide":
                return <UnhideButton key={action} onClick={handleUnhide} />;
            case "trash":
                return <DeleteButton key={action} onClick={handleDelete} />;
            case "deletePermanently":
                return (
                    <DeletePermanentlyButton
                        key={action}
                        onClick={handleDeletePermanently}
                    />
                );
            case "restore":
                return <RestoreButton key={action} onClick={handleRestore} />;
            case "addToAlbum":
                return (
                    <AddToCollectionButton
                        key={action}
                        onClick={handleAddToCollection}
                    />
                );
            case "moveToAlbum":
                return (
                    <MoveToCollectionButton
                        key={action}
                        onClick={handleMoveToCollection}
                    />
                );
            case "removeFromAlbum":
                return (
                    <RemoveFromCollectionButton
                        key={action}
                        onClick={handleRemoveFromCollection}
                    />
                );
            case "addPerson":
                return onShowAssignPersonDialog ? (
                    <AddPersonButton
                        key={action}
                        onClick={onShowAssignPersonDialog}
                    />
                ) : null;
        }
    };

    return (
        <>
            <SpacedRow sx={{ flex: 1, gap: 1, flexWrap: "wrap" }}>
                <IconButton onClick={onClearSelection}>
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

                <Box sx={{ mr: "auto" }} />

                {toolbarActions.map(renderActionButton)}
            </SpacedRow>
        </>
    );
};

const DownloadButton: React.FC<ButtonishProps> = ({ onClick }) => (
    <Tooltip title={t("download")}>
        <IconButton {...{ onClick }}>
            <HugeiconsIcon icon={Download01Icon} />
        </IconButton>
    </Tooltip>
);

const SendLinkButton: React.FC<ButtonishProps> = ({ onClick }) => (
    <Tooltip title="Send link">
        <IconButton {...{ onClick }} aria-label="Send link">
            <HugeiconsIcon icon={Navigation03Icon} />
        </IconButton>
    </Tooltip>
);

const FavoriteButton: React.FC<ButtonishProps> = ({ onClick }) => (
    <Tooltip title={t("favorite")}>
        <IconButton {...{ onClick }}>
            <StarBorderIcon fontSize="small" />
        </IconButton>
    </Tooltip>
);

const UnfavoriteButton: React.FC<ButtonishProps> = ({ onClick }) => (
    <Tooltip title={t("un_favorite")}>
        <IconButton {...{ onClick }}>
            <StarOffIcon fontSize="small" />
        </IconButton>
    </Tooltip>
);

const ArchiveButton: React.FC<ButtonishProps> = ({ onClick }) => (
    <Tooltip title={t("archive")}>
        <IconButton {...{ onClick }}>
            <HugeiconsIcon icon={Download05Icon} />
        </IconButton>
    </Tooltip>
);

const UnarchiveButton: React.FC<ButtonishProps> = ({ onClick }) => (
    <Tooltip title={t("unarchive")}>
        <IconButton {...{ onClick }}>
            <HugeiconsIcon icon={Unarchive03Icon} />
        </IconButton>
    </Tooltip>
);

const HideButton: React.FC<ButtonishProps> = ({ onClick }) => (
    <Tooltip title={t("hide")}>
        <IconButton {...{ onClick }}>
            <HugeiconsIcon icon={ViewOffSlashIcon} />
        </IconButton>
    </Tooltip>
);

const UnhideButton: React.FC<ButtonishProps> = ({ onClick }) => (
    <Tooltip title={t("unhide")}>
        <IconButton {...{ onClick }}>
            <HugeiconsIcon icon={ViewIcon} />
        </IconButton>
    </Tooltip>
);

const DeleteButton: React.FC<ButtonishProps> = ({ onClick }) => (
    <Tooltip title={t("delete")}>
        <IconButton {...{ onClick }} sx={{ color: "critical.main" }}>
            <HugeiconsIcon icon={Delete02Icon} />
        </IconButton>
    </Tooltip>
);

const RestoreButton: React.FC<ButtonishProps> = ({ onClick }) => (
    <Tooltip title={t("restore")}>
        <IconButton {...{ onClick }}>
            <HugeiconsIcon icon={Clock02Icon} />
        </IconButton>
    </Tooltip>
);

const DeletePermanentlyButton: React.FC<ButtonishProps> = ({ onClick }) => (
    <Tooltip title={t("delete_permanently")}>
        <IconButton {...{ onClick }} sx={{ color: "critical.main" }}>
            <HugeiconsIcon icon={Delete02Icon} />
        </IconButton>
    </Tooltip>
);

const FixTimeButton: React.FC<ButtonishProps> = ({ onClick }) => (
    <Tooltip title={t("fix_creation_time")}>
        <IconButton {...{ onClick }}>
            <HugeiconsIcon icon={Time04Icon} />
        </IconButton>
    </Tooltip>
);

const EditLocationButton: React.FC<ButtonishProps> = ({ onClick }) => (
    <Tooltip title={t("edit_location")}>
        <IconButton {...{ onClick }}>
            <HugeiconsIcon icon={Location01Icon} />
        </IconButton>
    </Tooltip>
);

const AddToCollectionButton: React.FC<ButtonishProps> = ({ onClick }) => (
    <Tooltip title={t("add")}>
        <IconButton {...{ onClick }}>
            <HugeiconsIcon icon={AddSquareIcon} />
        </IconButton>
    </Tooltip>
);

const AddPersonButton: React.FC<ButtonishProps> = ({ onClick }) => (
    <Tooltip title={t("add_a_person")}>
        <IconButton {...{ onClick }}>
            <HugeiconsIcon icon={UserAdd02Icon} />
        </IconButton>
    </Tooltip>
);

const MoveToCollectionButton: React.FC<ButtonishProps> = ({ onClick }) => (
    <Tooltip title={t("move")}>
        <IconButton {...{ onClick }}>
            <HugeiconsIcon icon={ArrowRight02Icon} />
        </IconButton>
    </Tooltip>
);

const RemoveFromCollectionButton: React.FC<ButtonishProps> = ({ onClick }) => (
    <Tooltip title={t("remove")}>
        <IconButton {...{ onClick }}>
            <HugeiconsIcon icon={RemoveCircleIcon} />
        </IconButton>
    </Tooltip>
);

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
