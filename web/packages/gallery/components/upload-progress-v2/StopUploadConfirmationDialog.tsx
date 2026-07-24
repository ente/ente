import CloseIcon from "@mui/icons-material/Close";
import {
    Box,
    Button,
    Dialog,
    IconButton,
    Stack,
    Typography,
    type Theme,
} from "@mui/material";
import { t } from "i18next";
import { uploadCompletionCounts } from "../uploadProgressStats";
import { useUploadProgressContext } from "./context";
import { doneStatConfigs } from "./helpers";

interface StopUploadConfirmationDialogProps {
    open: boolean;
    onClose: () => void;
    onConfirm: () => void;
}

export function StopUploadConfirmationDialog({
    open,
    onClose,
    onConfirm,
}: StopUploadConfirmationDialogProps) {
    const { finishedUploads, preUploadSkippedFiles } =
        useUploadProgressContext();
    const counts = uploadCompletionCounts(
        finishedUploads,
        preUploadSkippedFiles,
    );

    return (
        <Dialog
            open={open}
            onClose={onClose}
            maxWidth={false}
            aria-labelledby="stop-upload-confirmation-title"
            aria-describedby="stop-upload-confirmation-message"
            slotProps={{ paper: { sx: stopConfirmationPaperSx } }}
        >
            <Stack sx={stopConfirmationContentSx}>
                <Stack sx={stopConfirmationMessageSx}>
                    <Stack sx={stopConfirmationHeaderSx}>
                        <Box sx={stopConfirmationCloseRowSx}>
                            <IconButton
                                aria-label={t("close")}
                                onClick={onClose}
                                sx={stopConfirmationCloseButtonSx}
                            >
                                <CloseIcon sx={{ fontSize: 18 }} />
                            </IconButton>
                        </Box>
                        <Box aria-hidden sx={stopConfirmationIllustrationSx}>
                            <Box sx={stopConfirmationWarningIconSx}>
                                <CloseIcon sx={{ fontSize: 26 }} />
                            </Box>
                        </Box>
                        <Typography
                            id="stop-upload-confirmation-title"
                            component="h2"
                            sx={stopConfirmationTitleSx}
                        >
                            {t("stop_uploads_title")}
                        </Typography>
                    </Stack>
                    <Typography
                        id="stop-upload-confirmation-message"
                        sx={stopConfirmationSubtitleSx}
                    >
                        {t("stop_uploads_resume_message")}
                    </Typography>
                </Stack>
                <Stack direction="row" sx={stopConfirmationCountsSx}>
                    {doneStatConfigs.map(({ kind, color, labelKey }) => (
                        <Stack key={kind} sx={stopConfirmationCountTileSx}>
                            <Stack
                                direction="row"
                                sx={stopConfirmationCountLabelRowSx}
                            >
                                <Box
                                    sx={{
                                        ...statDotSx,
                                        backgroundColor: color,
                                    }}
                                />
                                <Typography sx={stopConfirmationCountLabelSx}>
                                    {t(labelKey)}
                                </Typography>
                            </Stack>
                            <Typography sx={stopConfirmationCountValueSx}>
                                {counts[kind].toLocaleString()}
                            </Typography>
                        </Stack>
                    ))}
                </Stack>
                <Button
                    fullWidth
                    onClick={onConfirm}
                    sx={stopConfirmationButtonSx}
                >
                    {t("stop_uploads")}
                </Button>
            </Stack>
        </Dialog>
    );
}

const uploadSurfaceStroke = "#e0e0e0";
const uploadSurfaceStrokeDark = "rgba(255 255 255 / 0.12)";
const ellipsisSx = {
    minWidth: 0,
    overflow: "hidden",
    textOverflow: "ellipsis",
    whiteSpace: "nowrap",
};
const mutedBodySx = {
    color: "text.muted",
    fontSize: 14,
    lineHeight: "20px",
    fontWeight: 500,
};
const mutedCaptionSx = {
    color: "text.muted",
    fontSize: 12,
    lineHeight: "16px",
    fontWeight: 500,
};
const statDotSx = { width: 6, height: 6, borderRadius: "50%", flexShrink: 0 };
const stopConfirmationPaperSx = (theme: Theme) => ({
    width: "min(488px, calc(100svw - 32px))",
    borderRadius: "20px",
    border: `1px solid ${uploadSurfaceStroke}`,
    backgroundColor: "#f4f4f4",
    backgroundImage: "none",
    boxShadow: "none",
    overflow: "hidden",
    ...theme.applyStyles("dark", {
        borderColor: uploadSurfaceStrokeDark,
        backgroundColor: "#1b1b1b",
    }),
});
const stopConfirmationContentSx = { p: "20px", gap: 3, color: "text.base" };
const stopConfirmationMessageSx = { alignItems: "center", gap: 1, minWidth: 0 };
const stopConfirmationHeaderSx = {
    alignItems: "center",
    gap: 2,
    width: "100%",
    minWidth: 0,
};
const stopConfirmationCloseRowSx = {
    width: "100%",
    display: "flex",
    justifyContent: "flex-end",
};
const stopConfirmationCloseButtonSx = (theme: Theme) => ({
    width: 38,
    height: 38,
    p: 0,
    color: "text.base",
    backgroundColor: "#fff",
    "&:hover": { backgroundColor: "fill.faintHover" },
    ...theme.applyStyles("dark", {
        backgroundColor: "rgba(255 255 255 / 0.12)",
    }),
});
const stopConfirmationIllustrationSx = (theme: Theme) => ({
    width: 80,
    height: 80,
    borderRadius: "50%",
    display: "flex",
    alignItems: "center",
    justifyContent: "center",
    backgroundColor: "#faebeb",
    ...theme.applyStyles("dark", { backgroundColor: "rgba(250 19 54 / 0.16)" }),
});
const stopConfirmationWarningIconSx = {
    width: 36,
    height: 36,
    borderRadius: "50%",
    display: "flex",
    alignItems: "center",
    justifyContent: "center",
    color: "#fff",
    backgroundColor: "#fa1336",
};
const stopConfirmationTitleSx = {
    fontSize: 24,
    lineHeight: "32px",
    fontWeight: 600,
    textAlign: "center",
    overflowWrap: "anywhere",
};
const stopConfirmationSubtitleSx = {
    ...mutedBodySx,
    width: "100%",
    textAlign: "center",
    overflowWrap: "anywhere",
};
const stopConfirmationCountsSx = { gap: "10px", width: "100%", minWidth: 0 };
const stopConfirmationCountTileSx = (theme: Theme) => ({
    flex: "1 1 0",
    minWidth: 0,
    px: { xs: 1.5, sm: "20px" },
    py: 1.5,
    gap: 0.5,
    borderRadius: "16px",
    backgroundColor: "#fff",
    ...theme.applyStyles("dark", { backgroundColor: "#282828" }),
});
const stopConfirmationCountLabelRowSx = {
    alignItems: "center",
    gap: 0.5,
    minWidth: 0,
};
const stopConfirmationCountLabelSx = {
    ...ellipsisSx,
    ...mutedCaptionSx,
    textAlign: "center",
};
const stopConfirmationCountValueSx = {
    fontSize: 16,
    lineHeight: "20px",
    fontWeight: 600,
    fontVariantNumeric: "tabular-nums",
};
const stopConfirmationButtonSx = {
    minHeight: 52,
    px: 3,
    py: "14px",
    borderRadius: "20px",
    color: "#fff",
    backgroundColor: "#fa1336",
    boxShadow: "none",
    textTransform: "none",
    fontSize: 14,
    lineHeight: "20px",
    fontWeight: 500,
    "&:hover": { backgroundColor: "#e80f31", boxShadow: "none" },
};
