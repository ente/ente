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
import type { CollectionSelectorAttributes } from "ente-new/photos/components/CollectionSelector";
import type { GalleryBarMode } from "ente-new/photos/components/gallery/reducer";
import { StarBorderIcon } from "ente-new/photos/components/icons/StarIcon";
import { StarOffIcon } from "ente-new/photos/components/icons/StarOffIcon";
import type { CollectionSummary } from "ente-new/photos/services/collection-summary";
import {
    getAvailableFileActions,
    type FileContextAction,
} from "ente-new/photos/utils/file-actions";
import { t } from "i18next";

/**
 * Operations on selected files.
 */
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

/**
 * Operations on selected files that also have an associated collection.
 */
export type CollectionOp = "add" | "move" | "restore" | "unhide";

interface SelectedFileOptionsProps {
    barMode?: GalleryBarMode;
    isInSearchMode: boolean;
    selectedCollection?: Collection;
    /**
     * If {@link collectionSummary} is set and is not a pseudo-collection, then
     * this will be set to the corresponding {@link Collection}.
     */
    collection: Collection | undefined;
    /**
     * The collection summary in whose context the selection happened.
     *
     * This will not be set if we are in the people section, or if we are
     * showing search results.
     */
    collectionSummary: CollectionSummary | undefined;
    /**
     * The total number of files selected by the user.
     */
    selectedFileCount: number;
    /**
     * The subset of {@link selectedFileCount} that are also owned by the user.
     */
    selectedOwnFileCount: number;
    /**
     * The number of selected files that are currently favorited.
     */
    selectedFavoriteCount: number;
    /**
     * Called when the user clears the selection by pressing the cancel button
     * on the selection bar.
     */
    onClearSelection: () => void;
    /**
     * Called when the user wants to remove the selected files from the given
     * {@link collection}.
     */
    onRemoveFilesFromCollection: (collection: Collection) => void;
    /**
     * Callback to open a dialog where the user can choose a collection.
     *
     * The reason for opening the dialog and other properties are passed as the
     * {@link attributes} argument.
     */
    onOpenCollectionSelector: (
        attributes: CollectionSelectorAttributes,
    ) => void;
    /**
     * A function called to obtain a new album creation handler for the provided
     * {@link op}.
     *
     * This function will be passed the operation to be be performed. It will
     * return a new function G can be used as the {@link onCreateCollection}
     * attribute for {@link onOpenCollectionSelector}.
     *
     * Once the user enters the name and a new album with that name gets
     * created, the newly created collection will be passed to G.
     *
     * @param op The operation that should be performed on the selected files
     * using the newly created collection.
     *
     * @returns A function that can be called with to create a new collection
     * and then perform {@link op} on successful creation of the new collection.
     */
    createOnCreateForCollectionOp: (op: CollectionOp) => () => void;
    /**
     * A function called to obtain an existing album selection handler for the
     * provided {@link op}.
     *
     * This function will be passed the operation to be be performed. It will
     * return a new function G can be used as the {@link onSelectCollection}
     * attribute for {@link onOpenCollectionSelector}.
     *
     * Once the user selects a collection, then the selected collection will be
     * passed to G.
     *
     * @param op The operation that should be performed on the selected files,
     * using the selected collection.
     *
     * @returns A function that can be called with a selected collection.
     */
    createOnSelectForCollectionOp: (
        op: CollectionOp,
    ) => (selectedCollection: Collection) => void;
    /**
     * A function called to obtain a handler for the provided {@link op}.
     *
     * This function will be passed the file operation to be performed. It will
     * return a new function G that can be used as a {@link onClick} handler for
     * the button. Calling G will trigger the operation on the selected files.
     *
     * @param op The operation that should be performed on the selected files.
     * @returns
     */
    createFileOpHandler: (op: FileOp) => () => void;
    /**
     * Callback to show the assign person dialog.
     *
     * Similar to {@link onOpenCollectionSelector}, this opens a shared dialog
     * defined in the parent component where the user can select a person to
     * associate with the selected files.
     *
     * If not set, the "Add Person" option will not be shown.
     */
    onShowAssignPersonDialog?: () => void;

    /**
     * Called when the user wants to edit the location of the selected files.
     *
     * Only shown when at least one owned file is selected.
     */
    onEditLocation?: () => void;
    /**
     * Called when the user wants to select all files.
     */
    onSelectAll: () => void;
    /**
     * If true, all files in the current view are selected.
     */
    isAllSelected: boolean;
}

/**
 * The selection bar shown at the top of the viewport when the user has selected
 * one or more files in the photos app gallery.
 */
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
