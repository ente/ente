import { Cancel01Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import {
    Box,
    Dialog,
    IconButton,
    Stack,
    Typography,
    type Theme,
} from "@mui/material";
import { LoadingButton } from "ente-base/components/mui/LoadingButton";
import {
    v2CancelButtonSx,
    v2SubmitButtonSx,
} from "ente-base/components/SingleInput.styles";
import {
    uploadSheetMediaQuery,
    uploadSheetPaperSx,
    useIsUploadSheet,
} from "ente-gallery/components/upload-progress/bottom-sheet";
import type { Collection } from "ente-media/collection";
import type { EnteFile } from "ente-media/file";
import { FileType } from "ente-media/file-type";
import { SlideUpTransition } from "ente-new/photos/components/mui/SlideUpTransition";
import { t } from "i18next";
import React, { useEffect, useId, useMemo, useState } from "react";
import AutoSizer from "react-virtualized-auto-sizer";
import { CoverPhotoGrid } from "./CoverPhotoGrid";

interface CoverPickerDialogProps {
    open: boolean;
    onClose: () => void;
    collection: Collection;
    files: EnteFile[];
    currentCoverFile: EnteFile | undefined;
    canResetToDefault: boolean;
    onUseSelectedPhoto: (file: EnteFile) => Promise<boolean>;
    onResetToDefault: () => Promise<boolean>;
}

type SubmittingAction = "set_as_cover" | "reset_to_default";

export const CoverPickerDialog: React.FC<CoverPickerDialogProps> = ({
    open,
    onClose,
    collection,
    files,
    currentCoverFile,
    canResetToDefault,
    onUseSelectedPhoto,
    onResetToDefault,
}) => {
    const isSheet = useIsUploadSheet();
    const titleID = useId();
    const descriptionID = useId();
    const [submittingAction, setSubmittingAction] = useState<
        SubmittingAction | undefined
    >();
    const [selectedFileID, setSelectedFileID] = useState<number>();
    const isSubmitting = Boolean(submittingAction);
    const currentCoverID = currentCoverFile?.id;

    const photos = useMemo(() => {
        const eligible = files.filter(
            (file) => file.metadata.fileType !== FileType.video,
        );
        const currentIndex = eligible.findIndex(
            ({ id }) => id === currentCoverID,
        );
        if (currentIndex > 0)
            eligible.unshift(...eligible.splice(currentIndex, 1));
        return eligible;
    }, [files, currentCoverID]);

    useEffect(() => {
        if (open) {
            setSelectedFileID(currentCoverID);
            setSubmittingAction(undefined);
        }
    }, [open, collection.id, currentCoverID]);

    const actions: SubmittingAction[] = canResetToDefault
        ? ["set_as_cover", "reset_to_default"]
        : ["set_as_cover"];
    const selectedFile = photos.find(({ id }) => id === selectedFileID);

    const submit = async (action: SubmittingAction) => {
        const update =
            action === "set_as_cover"
                ? selectedFile && (() => onUseSelectedPhoto(selectedFile))
                : onResetToDefault;
        if (!update || isSubmitting) return;

        setSubmittingAction(action);
        try {
            if (await update()) onClose();
        } finally {
            setSubmittingAction(undefined);
        }
    };

    return (
        <Dialog
            open={open}
            onClose={isSubmitting ? undefined : onClose}
            aria-labelledby={titleID}
            aria-describedby={descriptionID}
            maxWidth={false}
            slots={isSheet ? { transition: SlideUpTransition } : undefined}
            slotProps={{ paper: { sx: [paperSx, uploadSheetPaperSx] } }}
        >
            <Stack
                sx={{ height: "100%", minHeight: 0 }}
                aria-busy={isSubmitting}
            >
                <Stack direction="row" sx={headerSx}>
                    <Stack sx={{ minWidth: 0, gap: "2px" }}>
                        <Typography id={titleID} sx={titleSx}>
                            {t("choose_cover")}
                        </Typography>
                        <Typography id={descriptionID} sx={subtitleSx}>
                            {t("pick_cover_from_album", {
                                album: collection.name,
                            })}
                        </Typography>
                    </Stack>
                    <IconButton
                        aria-label={t("close")}
                        onClick={onClose}
                        disabled={isSubmitting}
                        sx={closeButtonSx}
                    >
                        <HugeiconsIcon icon={Cancel01Icon} size={16} />
                    </IconButton>
                </Stack>
                <Box sx={{ flex: 1, minHeight: 0, py: "18px" }}>
                    {photos.length ? (
                        <AutoSizer>
                            {({ width, height }) => (
                                <CoverPhotoGrid
                                    {...{
                                        width,
                                        height,
                                        photos,
                                        selectedFileID,
                                        currentCoverID,
                                    }}
                                    disabled={isSubmitting}
                                    onSelect={setSelectedFileID}
                                />
                            )}
                        </AutoSizer>
                    ) : (
                        <Typography sx={{ color: "text.muted", px: "24px" }}>
                            {t("no_photos_found_here")}
                        </Typography>
                    )}
                </Box>
                <Stack sx={footerSx}>
                    {actions.map((action) => {
                        const primary = action === "set_as_cover";
                        return (
                            <LoadingButton
                                key={action}
                                fullWidth
                                color={primary ? "accent" : "secondary"}
                                onClick={() => submit(action)}
                                loading={submittingAction === action}
                                disabled={
                                    isSubmitting || (primary && !selectedFile)
                                }
                                sx={[
                                    primary
                                        ? v2SubmitButtonSx
                                        : v2CancelButtonSx,
                                    actionButtonSx,
                                    primary
                                        ? submittingAction !== action &&
                                          primaryButtonDisabledSx
                                        : secondaryButtonSx,
                                ]}
                            >
                                {t(action)}
                            </LoadingButton>
                        );
                    })}
                </Stack>
            </Stack>
        </Dialog>
    );
};

const paperSx = {
    width: "min(688px, calc(100svw - 32px))",
    maxWidth: "688px",
    height: "560px",
    maxHeight: "calc(100dvh - 32px)",
    boxSizing: "border-box",
    m: 2,
    borderRadius: "20px",
    backgroundColor: "background.paper",
    backgroundImage: "none",
    boxShadow: "0px 24px 64px rgba(0 0 0 / 0.28)",
};
const headerSx = {
    alignItems: "center",
    justifyContent: "space-between",
    gap: "12px",
    p: "20px 20px 16px 24px",
    borderBottom: "1px solid",
    borderColor: "stroke.fainter",
    flexShrink: 0,
};
const titleSx = { fontSize: 18, lineHeight: "24px", fontWeight: 600 };
const subtitleSx = {
    fontSize: 12,
    lineHeight: "16px",
    fontWeight: 500,
    color: "text.muted",
    overflowWrap: "anywhere",
};
const closeButtonSx = {
    width: 24,
    height: 24,
    p: 0,
    flexShrink: 0,
    color: "text.muted",
};
const footerSx = (theme: Theme) => ({
    gap: "12px",
    px: "24px",
    py: "14px",
    flexShrink: 0,
    borderTop: "1px solid",
    borderColor: "stroke.fainter",
    backgroundColor: "#f4f4f4",
    ...theme.applyStyles("dark", { backgroundColor: "#1b1b1b" }),
    [uploadSheetMediaQuery]: {
        px: "16px",
        pb: "calc(14px + env(safe-area-inset-bottom, 0px))",
    },
});
const actionButtonSx = {
    flex: "none",
    minHeight: 52,
    px: "24px",
    py: "14px",
    textTransform: "none",
    boxShadow: "none",
    "&:hover": { boxShadow: "none" },
};
const secondaryButtonSx = (theme: Theme) => ({
    "&:hover": { backgroundColor: "#e0e0e0" },
    "&.Mui-disabled": { opacity: 1 },
    ...theme.applyStyles("dark", {
        backgroundColor: "#282828",
        "&:hover": { backgroundColor: "#333" },
    }),
});
const primaryButtonDisabledSx = (theme: Theme) => ({
    "&.Mui-disabled": {
        opacity: 1,
        color: "#d6d6d6",
        backgroundColor: "#eaeaea",
        ...theme.applyStyles("dark", {
            color: "rgba(255 255 255 / 0.3)",
            backgroundColor: "rgba(255 255 255 / 0.12)",
        }),
    },
});
