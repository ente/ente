import type { SelectedState } from "@/utils/file";
import CloseIcon from "@mui/icons-material/Close";
import {
    Box,
    Dialog,
    DialogActions,
    DialogContent,
    IconButton,
    Stack,
    Typography,
} from "@mui/material";
import type { LocalUser } from "ente-accounts/services/user";
import { LoadingButton } from "ente-base/components/mui/LoadingButton";
import { useIsSmallWidth } from "ente-base/components/utils/hooks";
import { isSameDay } from "ente-base/date";
import { ut } from "ente-base/i18n";
import { formattedDate } from "ente-base/i18n-date";
import type { Collection } from "ente-media/collection";
import type { EnteFile } from "ente-media/file";
import { fileCreationPhotoDate } from "ente-media/file-metadata";
import { FileType } from "ente-media/file-type";
import { t } from "i18next";
import React, { useCallback, useEffect, useId, useMemo, useState } from "react";
import AutoSizer from "react-virtualized-auto-sizer";
import { FileList, type FileListAnnotatedFile } from "../FileList";

interface PickCoverPhotoDialogProps {
    open: boolean;
    onClose: () => void;
    collection: Collection;
    files: EnteFile[];
    user: LocalUser;
    canResetToDefault: boolean;
    onUseSelectedPhoto: (file: EnteFile) => Promise<boolean>;
    onResetToDefault: () => Promise<boolean>;
}

type SubmittingAction = "use-selected-photo" | "reset-to-default";

/**
 * Picker dialog for selecting a single file to use as an album cover.
 */
export const PickCoverPhotoDialog: React.FC<PickCoverPhotoDialogProps> = ({
    open,
    onClose,
    collection,
    files,
    user,
    canResetToDefault,
    onUseSelectedPhoto,
    onResetToDefault,
}) => {
    const isFullScreen = useIsSmallWidth();
    const titleID = useId();
    const descriptionID = useId();
    const [submittingAction, setSubmittingAction] = useState<
        SubmittingAction | undefined
    >();
    const [selected, setSelected] = useState<SelectedState>(
        createEmptySelection(collection.id),
    );
    const isSubmitting = Boolean(submittingAction);

    useEffect(() => {
        if (open) {
            setSelected(createEmptySelection(collection.id));
            setSubmittingAction(undefined);
        }
    }, [open, collection.id]);

    const annotatedFiles = useMemo((): FileListAnnotatedFile[] => {
        if (!open) return [];

        return files
            .filter((file) => file.metadata.fileType !== FileType.video)
            .map((file) => ({
                file,
                timelineDateString: fileTimelineDateString(file),
            }));
    }, [open, files]);

    const selectedFile = useMemo(() => {
        if (!open) return undefined;

        for (const [key, value] of Object.entries(selected)) {
            if (typeof value !== "boolean" || !value) continue;
            const selectedFileID = Number(key);
            return files.find(({ id }) => id === selectedFileID);
        }
        return undefined;
    }, [open, selected, files]);

    const handleItemClick = useCallback(
        (index: number) => {
            const file = annotatedFiles[index]?.file;
            if (!file) return;
            setSelected(createSingleSelection(file, collection.id, user.id));
        },
        [annotatedFiles, collection.id, user.id],
    );

    const handleUseSelectedPhoto = useCallback(async () => {
        if (!selectedFile) return;

        setSubmittingAction("use-selected-photo");
        try {
            const didUpdate = await onUseSelectedPhoto(selectedFile);
            if (didUpdate) onClose();
        } finally {
            setSubmittingAction(undefined);
        }
    }, [onUseSelectedPhoto, onClose, selectedFile]);

    const handleResetToDefault = useCallback(async () => {
        setSubmittingAction("reset-to-default");
        try {
            const didReset = await onResetToDefault();
            if (didReset) onClose();
        } finally {
            setSubmittingAction(undefined);
        }
    }, [onResetToDefault, onClose]);

    const actionButtonSx = isFullScreen
        ? { flex: 1, minHeight: "44px" }
        : { minHeight: "44px" };
    const headerIconButtonSx = {
        width: "46px",
        height: "46px",
        borderRadius: "50%",
        color: "fixed.white",
        backgroundColor: "fill.faint",
        transition: "background-color 150ms ease",
        "& > svg": { opacity: 0.72, transition: "opacity 150ms ease" },
        "&:hover": {
            backgroundColor: "fill.faintHover",
            "& > svg": { opacity: 1 },
        },
    };

    return (
        <Dialog
            open={open}
            onClose={isSubmitting ? undefined : onClose}
            aria-labelledby={titleID}
            aria-describedby={descriptionID}
            fullWidth
            fullScreen={isFullScreen}
            slotProps={{
                paper: {
                    sx: !isFullScreen
                        ? {
                              width: "min(980px, calc(100vw - 64px))",
                              height: "min(760px, calc(100vh - 64px))",
                              borderRadius: "12px",
                          }
                        : undefined,
                },
            }}
        >
            <Stack
                sx={{ width: "100%", height: "100%" }}
                aria-busy={isSubmitting}
            >
                <Stack
                    sx={{
                        px: 2,
                        pt: 2,
                        pb: 2,
                        gap: 1,
                        borderBottom: 1,
                        borderColor: "divider",
                    }}
                >
                    <Stack
                        direction="row"
                        sx={{ alignItems: "center", gap: 1 }}
                    >
                        <Box sx={{ flex: 1, minWidth: 0 }}>
                            <Typography id={titleID} variant="h5">
                                {t("select_cover_photo")}
                            </Typography>
                            <Typography
                                id={descriptionID}
                                variant="small"
                                sx={{
                                    color: "text.muted",
                                    fontWeight: "regular",
                                }}
                                noWrap
                            >
                                {collection.name}
                            </Typography>
                        </Box>
                        <Stack
                            direction="row"
                            sx={{ alignItems: "center", gap: 1 }}
                        >
                            <IconButton
                                aria-label={t("close")}
                                onClick={onClose}
                                disabled={isSubmitting}
                                sx={headerIconButtonSx}
                            >
                                <CloseIcon fontSize="medium" />
                            </IconButton>
                        </Stack>
                    </Stack>
                </Stack>

                <DialogContent
                    sx={{
                        px: 2,
                        py: 0,
                        flex: 1,
                        minHeight: 0,
                        display: "flex",
                    }}
                >
                    <AutoSizer>
                        {({ width, height }) =>
                            width > 0 && height > 0 ? (
                                <FileList
                                    {...{
                                        width,
                                        height,
                                        user,
                                        annotatedFiles,
                                        selected,
                                        setSelected,
                                    }}
                                    mode="albums"
                                    enableSelect={false}
                                    activeCollectionID={collection.id}
                                    onItemClick={handleItemClick}
                                />
                            ) : (
                                <></>
                            )
                        }
                    </AutoSizer>
                </DialogContent>

                <DialogActions
                    sx={{
                        px: 2,
                        py: 1.5,
                        gap: 1,
                        borderTop: 1,
                        borderColor: "divider",
                        flexWrap: isFullScreen ? "wrap" : undefined,
                        alignItems: "center",
                        justifyContent: "flex-end",
                    }}
                >
                    {!isFullScreen && <Box sx={{ flex: 1 }} />}
                    {canResetToDefault && (
                        <LoadingButton
                            color="secondary"
                            onClick={handleResetToDefault}
                            loading={submittingAction === "reset-to-default"}
                            disabled={
                                isSubmitting &&
                                submittingAction !== "reset-to-default"
                            }
                            sx={actionButtonSx}
                        >
                            {t("reset_to_default")}
                        </LoadingButton>
                    )}
                    <LoadingButton
                        variant="contained"
                        color="primary"
                        onClick={handleUseSelectedPhoto}
                        loading={submittingAction === "use-selected-photo"}
                        disabled={
                            !selectedFile ||
                            (isSubmitting &&
                                submittingAction !== "use-selected-photo")
                        }
                        autoFocus={Boolean(selectedFile)}
                        sx={actionButtonSx}
                    >
                        {ut("Confirm")}
                    </LoadingButton>
                </DialogActions>
            </Stack>
        </Dialog>
    );
};

const createEmptySelection = (collectionID: number): SelectedState => ({
    ownCount: 0,
    count: 0,
    collectionID,
    context: { mode: "albums", collectionID },
});

const createSingleSelection = (
    file: EnteFile,
    collectionID: number,
    userID: number,
): SelectedState => ({
    [file.id]: true,
    ownCount: file.ownerID === userID ? 1 : 0,
    count: 1,
    collectionID,
    context: { mode: "albums", collectionID },
});

const fileTimelineDateString = (file: EnteFile) => {
    const date = fileCreationPhotoDate(file);
    return isSameDay(date, new Date())
        ? t("today")
        : isSameDay(date, new Date(Date.now() - 24 * 60 * 60 * 1000))
          ? t("yesterday")
          : formattedDate(date);
};
