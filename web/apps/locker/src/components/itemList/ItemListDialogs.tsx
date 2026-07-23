import type { LockerCollection } from "@/types";
import CheckCircleRoundedIcon from "@mui/icons-material/CheckCircleRounded";
import {
    Box,
    Button,
    Chip,
    Dialog,
    DialogContent,
    DialogTitle,
    Menu,
    MenuItem,
    Snackbar,
    Stack,
    TextField,
    Typography,
} from "@mui/material";
import { LoadingButton } from "ente-base/components/mui/LoadingButton";
import { t } from "i18next";
import React from "react";
import { LockerFileLinkDialog } from "../LockerFileLinkDialog";
import { lockerDialogPaperSx } from "../lockerDialogStyles";

interface ItemListDialogsProps {
    activeFileLinkItemTitle: string;
    activeFileLinkURL: string | null;
    canNativeShare: boolean;
    closeCollectionFilterMenu: () => void;
    closeFileLinkDialog: () => void;
    clearHomeCollectionSelection: () => void;
    createCollectionError: string | null;
    createCollectionName: string;
    createCollectionOpen: boolean;
    creatingCollection: boolean;
    deleteFileLink: () => void;
    dropdownHomeCollections: LockerCollection[];
    feedbackMessage: string | null;
    homeSelectedCollectionIDs: number[];
    isCreatingFileLink: boolean;
    isDeleteFileLinkConfirmOpen: boolean;
    isDeletingFileLink: boolean;
    onCloseFeedback: () => void;
    onCloseRenameDialog: () => void;
    onCloseRestoreDialog: () => void;
    onCloseCreateCollectionDialog: () => void;
    onConfirmCreateCollection: () => void;
    onConfirmRename: () => void | Promise<void>;
    onConfirmRestore: () => void | Promise<void>;
    onCopyFileLink: () => void;
    onRequestDeleteFileLink: () => void;
    onShareFileLink: () => void;
    onToggleHomeCollection: (collectionID: number) => void;
    renameError: string | null;
    renameCollectionOpen: boolean;
    renamingCollection: boolean;
    renameValue: string;
    restoreCollections: LockerCollection[];
    restoreError: string | null;
    restoreCollectionID: number | null;
    restoreDialogOpen: boolean;
    restoringItem: boolean;
    setCreateCollectionName: (value: string) => void;
    setDeleteFileLinkConfirmOpen: (open: boolean) => void;
    setRenameValue: (value: string) => void;
    setRestoreCollectionID: (collectionID: number) => void;
    collectionFilterAnchorEl: HTMLElement | null;
    fileLinkDialogOpen: boolean;
}

export const ItemListDialogs: React.FC<ItemListDialogsProps> = ({
    activeFileLinkItemTitle,
    activeFileLinkURL,
    canNativeShare,
    closeCollectionFilterMenu,
    closeFileLinkDialog,
    clearHomeCollectionSelection,
    createCollectionError,
    createCollectionName,
    createCollectionOpen,
    creatingCollection,
    deleteFileLink,
    dropdownHomeCollections,
    feedbackMessage,
    homeSelectedCollectionIDs,
    isCreatingFileLink,
    isDeleteFileLinkConfirmOpen,
    isDeletingFileLink,
    onCloseFeedback,
    onCloseRenameDialog,
    onCloseRestoreDialog,
    onCloseCreateCollectionDialog,
    onConfirmCreateCollection,
    onConfirmRename,
    onConfirmRestore,
    onCopyFileLink,
    onRequestDeleteFileLink,
    onShareFileLink,
    onToggleHomeCollection,
    renameError,
    renameCollectionOpen,
    renamingCollection,
    renameValue,
    restoreCollections,
    restoreError,
    restoreCollectionID,
    restoreDialogOpen,
    restoringItem,
    setCreateCollectionName,
    setDeleteFileLinkConfirmOpen,
    setRenameValue,
    setRestoreCollectionID,
    collectionFilterAnchorEl,
    fileLinkDialogOpen,
}) => (
    <>
        <LockerFileLinkDialog
            open={fileLinkDialogOpen}
            itemTitle={activeFileLinkItemTitle}
            url={activeFileLinkURL ?? undefined}
            loading={isCreatingFileLink}
            deleting={isDeletingFileLink}
            showShareAction={canNativeShare}
            onClose={closeFileLinkDialog}
            onCopy={onCopyFileLink}
            onShare={onShareFileLink}
            onDelete={onRequestDeleteFileLink}
        />

        <Dialog
            slotProps={{ paper: { sx: lockerDialogPaperSx } }}
            open={isDeleteFileLinkConfirmOpen}
            onClose={() => {
                if (!isDeletingFileLink) {
                    setDeleteFileLinkConfirmOpen(false);
                }
            }}
            fullWidth
            maxWidth="xs"
        >
            <DialogTitle>{t("deleteShareLinkDialogTitle")}</DialogTitle>
            <DialogContent>
                <Stack sx={{ gap: 2.25 }}>
                    <Typography sx={{ color: "text.muted" }}>
                        {t("deleteShareLinkConfirmation")}
                    </Typography>
                    <Stack direction="row" sx={{ gap: 1 }}>
                        <Button
                            fullWidth
                            color="secondary"
                            disabled={isDeletingFileLink}
                            onClick={() => setDeleteFileLinkConfirmOpen(false)}
                            sx={{ minHeight: 44 }}
                        >
                            {t("cancel")}
                        </Button>
                        <LoadingButton
                            fullWidth
                            color="critical"
                            loading={isDeletingFileLink}
                            onClick={deleteFileLink}
                            sx={{ minHeight: 44 }}
                        >
                            {t("deleteLink")}
                        </LoadingButton>
                    </Stack>
                </Stack>
            </DialogContent>
        </Dialog>

        <Dialog
            slotProps={{ paper: { sx: lockerDialogPaperSx } }}
            open={restoreDialogOpen}
            onClose={() => {
                if (!restoringItem) {
                    onCloseRestoreDialog();
                }
            }}
            fullWidth
            maxWidth="xs"
        >
            <DialogTitle>{t("restoreToCollection")}</DialogTitle>
            <DialogContent>
                <Stack sx={{ gap: 1, pt: 0.25, pb: 1 }}>
                    {restoreCollections.length > 0 ? (
                        restoreCollections.map((collection) => (
                            <Chip
                                key={collection.id}
                                label={collection.name}
                                variant={
                                    restoreCollectionID === collection.id
                                        ? "filled"
                                        : "outlined"
                                }
                                color={
                                    restoreCollectionID === collection.id
                                        ? "primary"
                                        : "default"
                                }
                                disabled={restoringItem}
                                onClick={() =>
                                    setRestoreCollectionID(collection.id)
                                }
                            />
                        ))
                    ) : (
                        <Typography variant="body" sx={{ color: "text.muted" }}>
                            {t("noCollectionsAvailableForSelection")}
                        </Typography>
                    )}
                    {restoreError && (
                        <Typography
                            variant="small"
                            sx={{ color: "critical.main" }}
                        >
                            {restoreError}
                        </Typography>
                    )}
                    <LoadingButton
                        variant="contained"
                        loading={restoringItem}
                        disabled={restoreCollectionID === null}
                        onClick={onConfirmRestore}
                        sx={{ mt: 1 }}
                    >
                        {t("restore")}
                    </LoadingButton>
                </Stack>
            </DialogContent>
        </Dialog>

        <Dialog
            slotProps={{ paper: { sx: lockerDialogPaperSx } }}
            open={renameCollectionOpen}
            onClose={() => {
                if (!renamingCollection) {
                    onCloseRenameDialog();
                }
            }}
            fullWidth
            maxWidth="xs"
        >
            <DialogTitle>{t("renameCollection")}</DialogTitle>
            <DialogContent>
                <Stack sx={{ gap: 2, pt: 0.25, pb: 1 }}>
                    <TextField
                        value={renameValue}
                        onChange={(event) => setRenameValue(event.target.value)}
                        label={t("enterCollectionName")}
                        fullWidth
                        autoFocus
                        disabled={renamingCollection}
                        onKeyDown={(event) => {
                            if (event.key === "Enter") {
                                void onConfirmRename();
                            }
                        }}
                    />
                    {renameError && (
                        <Typography
                            variant="small"
                            sx={{ color: "critical.main" }}
                        >
                            {renameError}
                        </Typography>
                    )}
                    <LoadingButton
                        variant="contained"
                        loading={renamingCollection}
                        disabled={!renameValue.trim()}
                        onClick={onConfirmRename}
                    >
                        {t("save")}
                    </LoadingButton>
                </Stack>
            </DialogContent>
        </Dialog>

        <Dialog
            slotProps={{ paper: { sx: lockerDialogPaperSx } }}
            open={createCollectionOpen}
            onClose={() => {
                if (!creatingCollection) {
                    onCloseCreateCollectionDialog();
                }
            }}
            fullWidth
            maxWidth="xs"
        >
            <DialogTitle>{t("createCollection")}</DialogTitle>
            <DialogContent>
                <Stack sx={{ gap: 2, pt: 0.25, pb: 1 }}>
                    <TextField
                        value={createCollectionName}
                        onChange={(event) =>
                            setCreateCollectionName(event.target.value)
                        }
                        label={t("enterCollectionName")}
                        fullWidth
                        autoFocus
                        disabled={creatingCollection}
                        onKeyDown={(event) => {
                            if (event.key === "Enter") {
                                onConfirmCreateCollection();
                            }
                        }}
                    />
                    {createCollectionError && (
                        <Typography
                            variant="small"
                            sx={{ color: "critical.main" }}
                        >
                            {createCollectionError}
                        </Typography>
                    )}
                    <Stack direction="row" sx={{ gap: 1 }}>
                        <Button
                            fullWidth
                            color="secondary"
                            onClick={onCloseCreateCollectionDialog}
                            disabled={creatingCollection}
                        >
                            {t("cancel")}
                        </Button>
                        <LoadingButton
                            fullWidth
                            color="primary"
                            loading={creatingCollection}
                            onClick={onConfirmCreateCollection}
                            disabled={!createCollectionName.trim()}
                        >
                            {t("createCollectionButton")}
                        </LoadingButton>
                    </Stack>
                </Stack>
            </DialogContent>
        </Dialog>

        <Menu
            anchorEl={collectionFilterAnchorEl}
            open={!!collectionFilterAnchorEl}
            onClose={closeCollectionFilterMenu}
            slotProps={{
                paper: {
                    sx: {
                        mt: 1,
                        width: "fit-content",
                        minWidth: 0,
                        maxWidth: "calc(100vw - 32px)",
                        borderRadius: "18px",
                        overflow: "hidden",
                    },
                },
            }}
        >
            <Box sx={{ px: 1, pt: 0, pb: 0, width: "fit-content" }}>
                {dropdownHomeCollections.map((collection) => {
                    const isSelected = homeSelectedCollectionIDs.includes(
                        collection.id,
                    );

                    return (
                        <MenuItem
                            key={collection.id}
                            onClick={() =>
                                onToggleHomeCollection(collection.id)
                            }
                            sx={(theme) => ({
                                gap: 1.25,
                                px: 1,
                                py: 1,
                                my: "6px",
                                borderRadius: "14px",
                                alignItems: "center",
                                width: "auto",
                                color: isSelected
                                    ? "primary.main"
                                    : "text.base",
                                backgroundColor: isSelected
                                    ? "rgba(16, 113, 255, 0.10)"
                                    : "transparent",
                                "&:hover": {
                                    backgroundColor: isSelected
                                        ? "rgba(16, 113, 255, 0.14)"
                                        : theme.vars.palette.fill.faint,
                                },
                            })}
                        >
                            <CheckCircleRoundedIcon
                                sx={{
                                    fontSize: 20,
                                    color: isSelected
                                        ? "primary.main"
                                        : "text.faint",
                                    opacity: isSelected ? 1 : 0.22,
                                    flexShrink: 0,
                                }}
                            />
                            <Box sx={{ minWidth: 0, flex: 1 }}>
                                <Typography
                                    variant="body"
                                    sx={{
                                        fontWeight: isSelected ? 700 : 500,
                                        display: "flex",
                                        alignItems: "center",
                                        gap: 0.75,
                                        minWidth: 0,
                                        whiteSpace: "nowrap",
                                    }}
                                >
                                    <Box
                                        component="span"
                                        sx={{
                                            overflow: "hidden",
                                            textOverflow: "ellipsis",
                                            whiteSpace: "nowrap",
                                            minWidth: 0,
                                        }}
                                    >
                                        {collection.name}
                                    </Box>
                                    <Box
                                        component="span"
                                        sx={{
                                            color: "text.muted",
                                            flexShrink: 0,
                                        }}
                                    >
                                        {"·"}
                                    </Box>
                                    <Box
                                        component="span"
                                        sx={{
                                            color: "text.muted",
                                            fontWeight: 500,
                                            flexShrink: 0,
                                            whiteSpace: "nowrap",
                                        }}
                                    >
                                        {new Intl.NumberFormat().format(
                                            collection.items.length,
                                        )}
                                    </Box>
                                </Typography>
                            </Box>
                        </MenuItem>
                    );
                })}
                {homeSelectedCollectionIDs.length > 0 && (
                    <Box
                        sx={{
                            display: "flex",
                            justifyContent: "center",
                            pt: "12px",
                            pb: 0,
                        }}
                    >
                        <Button
                            color="secondary"
                            onClick={() => {
                                clearHomeCollectionSelection();
                                closeCollectionFilterMenu();
                            }}
                            sx={{
                                minWidth: "auto",
                                px: 1,
                                py: 0.5,
                                backgroundColor: "transparent",
                                color: "text.muted",
                                fontSize: "0.8125rem",
                                fontWeight: 500,
                                textDecoration: "underline",
                                textUnderlineOffset: "3px",
                                "&:hover": {
                                    backgroundColor: "transparent",
                                    color: "text.secondary",
                                },
                            }}
                        >
                            {t("clearSelection")}
                        </Button>
                    </Box>
                )}
            </Box>
        </Menu>

        <Snackbar
            open={feedbackMessage !== null}
            message={feedbackMessage}
            autoHideDuration={2500}
            onClose={onCloseFeedback}
        />
    </>
);
