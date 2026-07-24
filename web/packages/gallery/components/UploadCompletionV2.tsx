import CloseIcon from "@mui/icons-material/Close";
import {
    Box,
    Button,
    Dialog,
    IconButton,
    Stack,
    Typography,
    type DialogProps,
    type Theme,
} from "@mui/material";
import type { PreUploadSkippedFile } from "ente-base/types/ipc";
import { t } from "i18next";
import {
    finishedStatKinds,
    uploadCompletionCounts,
    uploadStatColors,
    type SegregatedFinishedUploads,
} from "./uploadProgressStats";

export function UploadCompletionV2({
    open,
    onClose,
    onReviewFailed,
    finishedUploads,
    preUploadSkippedFiles = [],
}: {
    open: boolean;
    onClose: () => void;
    onReviewFailed: () => void;
    finishedUploads: SegregatedFinishedUploads;
    preUploadSkippedFiles?: PreUploadSkippedFile[];
}) {
    const counts = uploadCompletionCounts(
        finishedUploads,
        preUploadSkippedFiles,
    );
    const hasReviewableUploads = counts.failed > 0 || counts.skipped > 0;

    const handleClose: DialogProps["onClose"] = (_, reason) => {
        if (reason != "backdropClick") onClose();
    };

    if (!open) {
        return null;
    }

    return (
        <Dialog
            open
            onClose={handleClose}
            maxWidth={false}
            aria-labelledby="upload-completion-v2-title"
            slotProps={{ paper: { sx: completionDialogPaperSx } }}
        >
            <Stack sx={completionDialogContentSx}>
                <Stack direction="row" sx={{ justifyContent: "flex-end" }}>
                    <IconButton
                        aria-label={t("close")}
                        onClick={onClose}
                        sx={completionCloseButtonSx}
                    >
                        <CloseIcon sx={{ fontSize: 18 }} />
                    </IconButton>
                </Stack>
                <Stack sx={completionBodySx}>
                    <Box
                        component="img"
                        alt=""
                        src="/images/upload-complete-duck.svg"
                        sx={completionIllustrationSx}
                    />
                    <Stack sx={{ gap: "6px", alignItems: "center" }}>
                        <Typography
                            id="upload-completion-v2-title"
                            component="h2"
                            sx={completionTitleSx}
                        >
                            Your upload is done!
                        </Typography>
                        <Typography sx={completionSubtitleSx}>
                            Uploaded items are now available on Ente.
                        </Typography>
                    </Stack>
                </Stack>
                <Box sx={completionStatsGridSx}>
                    {finishedStatKinds.map((kind) => (
                        <Stack key={kind} sx={completionStatSx}>
                            <Stack
                                direction="row"
                                sx={{ alignItems: "center", gap: 0.5 }}
                            >
                                <Box
                                    sx={{
                                        ...completionStatDotSx,
                                        backgroundColor: uploadStatColors[kind],
                                    }}
                                />
                                <Typography sx={completionStatLabelSx}>
                                    {completionStatLabels[kind]}
                                </Typography>
                            </Stack>
                            <Typography sx={completionStatValueSx}>
                                {counts[kind].toLocaleString()}
                            </Typography>
                        </Stack>
                    ))}
                </Box>
                <Stack sx={{ gap: 1.5 }}>
                    {hasReviewableUploads ? (
                        <Button
                            fullWidth
                            onClick={onReviewFailed}
                            sx={primaryButtonSx}
                        >
                            Review items
                        </Button>
                    ) : null}
                    <Button
                        fullWidth
                        onClick={onClose}
                        sx={
                            hasReviewableUploads
                                ? secondaryButtonSx
                                : primaryButtonSx
                        }
                    >
                        Close
                    </Button>
                </Stack>
            </Stack>
        </Dialog>
    );
}

const completionStatLabels = {
    completed: "Completed",
    skipped: "Skipped",
    failed: "Failed",
} as const;

const completionDialogPaperSx = (theme: Theme) => ({
    width: "min(488px, calc(100svw - 32px))",
    borderRadius: "20px",
    border: "1px solid #e0e0e0",
    backgroundColor: "#f4f4f4",
    backgroundImage: "none",
    boxShadow: "none",
    overflow: "hidden",
    ...theme.applyStyles("dark", {
        borderColor: "rgba(255 255 255 / 0.12)",
        backgroundColor: "#1b1b1b",
    }),
});

const completionDialogContentSx = { p: "20px", gap: 3, color: "text.base" };

const completionCloseButtonSx = (theme: Theme) => ({
    width: 38,
    height: 38,
    p: 0,
    color: "text.base",
    backgroundColor: "background.paper",
    "&:hover": { backgroundColor: "fill.faintHover" },
    ...theme.applyStyles("dark", {
        backgroundColor: "rgba(255 255 255 / 0.12)",
    }),
});

const completionBodySx = { alignItems: "center", gap: 3, textAlign: "center" };

const completionIllustrationSx = { width: 138, height: 154, maxWidth: "100%" };

const completionTitleSx = { fontSize: 24, lineHeight: "32px", fontWeight: 600 };

const completionSubtitleSx = {
    color: "text.muted",
    fontSize: 14,
    lineHeight: "20px",
    fontWeight: 500,
};

const completionStatsGridSx = {
    display: "grid",
    gridTemplateColumns: "repeat(3, minmax(0, 1fr))",
    gap: "10px",
    "@media (max-width: 420px)": { gridTemplateColumns: "1fr" },
};

const completionStatSx = (theme: Theme) => ({
    minWidth: 0,
    minHeight: 64,
    p: "12px 20px",
    gap: "4px",
    borderRadius: "16px",
    backgroundColor: "background.paper",
    ...theme.applyStyles("dark", { backgroundColor: "#282828" }),
});

const completionStatDotSx = {
    width: 6,
    height: 6,
    borderRadius: "50%",
    flexShrink: 0,
};

const completionStatLabelSx = {
    minWidth: 0,
    overflow: "hidden",
    textOverflow: "ellipsis",
    whiteSpace: "nowrap",
    color: "text.muted",
    fontSize: 12,
    lineHeight: "16px",
    fontWeight: 500,
};

const completionStatValueSx = {
    fontSize: 16,
    lineHeight: "20px",
    fontWeight: 600,
};

const baseButtonSx = {
    height: 52,
    borderRadius: "20px",
    boxShadow: "none",
    textTransform: "none",
    fontSize: 14,
    lineHeight: "20px",
    fontWeight: 500,
    "&:hover": { boxShadow: "none" },
};

const primaryButtonSx = {
    ...baseButtonSx,
    color: "#fff",
    backgroundColor: uploadStatColors.completed,
    "&:hover": { backgroundColor: "#07ad21", boxShadow: "none" },
};

const secondaryButtonSx = (theme: Theme) => ({
    ...baseButtonSx,
    color: "text.base",
    backgroundColor: "#eaeaea",
    "&:hover": { backgroundColor: "#dedede", boxShadow: "none" },
    ...theme.applyStyles("dark", {
        backgroundColor: "rgba(255 255 255 / 0.12)",
        "&:hover": { backgroundColor: "rgba(255 255 255 / 0.18)" },
    }),
});
