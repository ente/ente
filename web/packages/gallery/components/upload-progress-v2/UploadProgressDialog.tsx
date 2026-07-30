import CloseIcon from "@mui/icons-material/Close";
import UnfoldLessIcon from "@mui/icons-material/UnfoldLess";
import {
    Box,
    Dialog,
    IconButton,
    keyframes,
    LinearProgress,
    Stack,
    Typography,
    type DialogProps,
    type Theme,
} from "@mui/material";
import { t } from "i18next";
import { uploadStatColors } from "../uploadProgressStats";
import { useUploadProgressContext } from "./context";
import {
    normalizePercent,
    uploadCountsText,
    uploadStatusText,
} from "./helpers";
import { UploadProgressDetails } from "./UploadProgressDetails";

export function UploadProgressDialog() {
    const { onClose, uploadPhase } = useUploadProgressContext();
    const isDone = uploadPhase == "done";

    const handleClose: DialogProps["onClose"] = (_, reason) => {
        if (reason != "backdropClick") onClose();
    };

    return (
        <Dialog
            open
            onClose={handleClose}
            maxWidth={false}
            aria-labelledby="upload-progress-v2-title"
            slotProps={{ paper: { sx: uploadProgressDialogPaperSx } }}
        >
            <Box sx={uploadProgressDialogContentSx(isDone)}>
                <UploadProgressV2Header />
                {isDone ? (
                    <UploadProgressDetails />
                ) : (
                    <Stack sx={{ gap: 3 }}>
                        <UploadProgressV2Summary />
                        <UploadProgressDetails />
                    </Stack>
                )}
            </Box>
        </Dialog>
    );
}

function UploadProgressV2Header() {
    const { onClose, setExpanded, uploadPhase } = useUploadProgressContext();
    const isDone = uploadPhase == "done";
    const title = t(isDone ? "upload_details" : "file_upload");

    const handleMinimize = () => setExpanded(false);

    return (
        <Stack direction="row" sx={[headerSx, isDone && quietHeaderSx]}>
            <Typography
                id="upload-progress-v2-title"
                component="h2"
                sx={uploadTitleSx}
            >
                {title}
            </Typography>
            <Stack direction="row" sx={headerActionsSx}>
                <IconButton
                    aria-label={t("minimize")}
                    onClick={handleMinimize}
                    sx={headerActionButtonSx}
                >
                    <UnfoldLessIcon sx={{ fontSize: 22 }} />
                </IconButton>
                <IconButton
                    aria-label={t("close")}
                    onClick={onClose}
                    sx={headerActionButtonSx}
                >
                    <CloseIcon sx={{ fontSize: 18 }} />
                </IconButton>
            </Stack>
        </Stack>
    );
}

function UploadProgressV2Summary() {
    const context = useUploadProgressContext();
    const { uploadPhase, percentComplete } = context;
    const isUploading = uploadPhase == "uploading";
    const isDeterminate = isUploading || uploadPhase == "readingMetadata";
    const progress = normalizePercent(percentComplete);
    const headline = isUploading
        ? t("uploaded_percent", { percent: progress })
        : uploadStatusText(uploadPhase);
    const supportingText =
        uploadPhase == "preparing"
            ? t("upload_getting_ready")
            : uploadPhase == "cancelling"
              ? t("upload_finishing_active")
              : uploadCountsText(context);
    const progressCaption =
        uploadPhase == "readingMetadata"
            ? t("upload_reading_file_information")
            : uploadPhase == "cancelling"
              ? t("this_may_take_a_moment")
              : isUploading
                ? uploadStatusText(uploadPhase)
                : undefined;

    return (
        <Box sx={summaryLayoutSx}>
            <Stack sx={{ gap: 2, minWidth: 0 }}>
                <Stack sx={{ minWidth: 0, gap: "4px" }}>
                    <Typography
                        component="p"
                        sx={[titleTextSx, !isDeterminate && animatedEllipsisSx]}
                    >
                        {headline}
                    </Typography>
                    <Typography sx={mutedBodySx}>{supportingText}</Typography>
                </Stack>
                <Stack sx={{ gap: "10px" }}>
                    <LinearProgress
                        variant="determinate"
                        value={isDeterminate ? progress : 0}
                        sx={mainProgressSx}
                    />
                    {(progressCaption || isDeterminate) && (
                        <Stack
                            direction="row"
                            sx={{
                                justifyContent: "space-between",
                                alignItems: "baseline",
                                gap: 2,
                            }}
                        >
                            {progressCaption && (
                                <Typography
                                    sx={[
                                        mutedCaptionSx,
                                        isUploading && animatedEllipsisSx,
                                    ]}
                                >
                                    {progressCaption}
                                </Typography>
                            )}
                            {isDeterminate && (
                                <Typography sx={mutedCaptionSx}>
                                    {t("percent_complete", {
                                        percent: progress,
                                    })}
                                </Typography>
                            )}
                        </Stack>
                    )}
                </Stack>
            </Stack>
            <Box
                component="img"
                alt=""
                src="/images/upload-progress-sleeping-duck.svg"
                sx={mascotSx}
            />
        </Box>
    );
}

const progressGreen = uploadStatColors.completed;
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
const uploadProgressDialogPaperSx = (theme: Theme) => ({
    width: "min(714px, calc(100svw - 32px))",
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
const uploadProgressDialogContentSx = (isDone: boolean) => ({
    p: "20px",
    pb: "28px",
    display: "flex",
    flexDirection: "column",
    gap: isDone ? "36px" : "20px",
    color: "text.base",
});
const headerSx = (theme: Theme) => ({
    alignItems: "center",
    justifyContent: "space-between",
    pb: "12px",
    borderBottom: "1px solid rgba(0 0 0 / 0.06)",
    ...theme.applyStyles("dark", {
        borderBottomColor: "rgba(255 255 255 / 0.08)",
    }),
});
const quietHeaderSx = { pb: 0, borderBottom: "none" };
const headerActionsSx = { alignItems: "center", gap: 1, flexShrink: 0 };
const headerActionButtonSx = (theme: Theme) => ({
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
const titleTextSx = { fontSize: 24, lineHeight: "32px", fontWeight: 600 };
const waitingDotsAnimation = keyframes`
    0% { content: "."; }
    33% { content: ".."; }
    66%, 100% { content: "..."; }
`;
const animatedEllipsisSx = {
    "&::after": {
        display: "inline-block",
        width: "1.5em",
        content: '""',
        animation: `${waitingDotsAnimation} 1.2s steps(1, end) infinite`,
    },
    "@media (prefers-reduced-motion: reduce)": {
        "&::after": { animation: "none", content: '"..."' },
    },
};
const uploadTitleSx = { ...ellipsisSx, ...titleTextSx };
const summaryLayoutSx = {
    pl: "8px",
    display: "grid",
    gridTemplateColumns: "minmax(0, 440px) minmax(128px, 1fr)",
    gap: "32px",
    alignItems: "center",
    "@media (max-width: 620px)": { gridTemplateColumns: "1fr", gap: 2 },
};
const mainProgressSx = (theme: Theme) => ({
    height: 14,
    borderRadius: "200px",
    backgroundColor: "background.paper",
    "& .MuiLinearProgress-bar": {
        borderRadius: "inherit",
        backgroundColor: progressGreen,
    },
    ...theme.applyStyles("dark", {
        backgroundColor: "rgba(255 255 255 / 0.12)",
    }),
});
const mascotSx = {
    width: 128,
    maxWidth: "100%",
    justifySelf: "center",
    "@media (max-width: 620px)": { display: "none" },
};
