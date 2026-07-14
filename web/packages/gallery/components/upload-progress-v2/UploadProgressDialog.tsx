import ArrowBackIcon from "@mui/icons-material/ArrowBack";
import CloseIcon from "@mui/icons-material/Close";
import {
    Box,
    Dialog,
    IconButton,
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

export function UploadProgressDialog({ closeOnly }: { closeOnly: boolean }) {
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
                    <UploadProgressDetails closeOnly={closeOnly} />
                ) : (
                    <Stack sx={{ gap: 3 }}>
                        <UploadProgressV2Summary />
                        <UploadProgressDetails closeOnly={closeOnly} />
                    </Stack>
                )}
            </Box>
        </Dialog>
    );
}

function UploadProgressV2Header() {
    const { onClose, setExpanded, uploadPhase } = useUploadProgressContext();
    const isDone = uploadPhase == "done";
    const title = isDone ? "Upload details" : t("file_upload");

    const handleMinimize = () => setExpanded(false);

    return (
        <Stack direction="row" sx={[headerSx, isDone && quietHeaderSx]}>
            <Stack
                direction="row"
                sx={{ alignItems: "center", gap: 1, minWidth: 0 }}
            >
                <IconButton
                    aria-label="Minimize"
                    onClick={handleMinimize}
                    sx={headerIconButtonSx}
                >
                    <ArrowBackIcon sx={{ fontSize: 21 }} />
                </IconButton>
                <Typography
                    id="upload-progress-v2-title"
                    component="h2"
                    sx={uploadTitleSx}
                >
                    {title}
                </Typography>
            </Stack>
            <IconButton
                aria-label={t("close")}
                onClick={onClose}
                sx={closeIconButtonSx}
            >
                <CloseIcon sx={{ fontSize: 18 }} />
            </IconButton>
        </Stack>
    );
}

function UploadProgressV2Summary() {
    const context = useUploadProgressContext();
    const { uploadPhase, percentComplete } = context;
    const progress = normalizePercent(percentComplete);

    return (
        <Box sx={summaryLayoutSx}>
            <Stack sx={{ gap: 2, minWidth: 0 }}>
                <Stack sx={{ minWidth: 0, gap: "4px" }}>
                    <Typography component="p" sx={titleTextSx}>
                        {progress.toLocaleString()}% uploaded
                    </Typography>
                    <Typography sx={mutedBodySx}>
                        {uploadCountsText(context)}
                    </Typography>
                </Stack>
                <Stack sx={{ gap: "10px" }}>
                    <LinearProgress
                        variant="determinate"
                        value={progress}
                        sx={mainProgressSx}
                    />
                    <Stack
                        direction="row"
                        sx={{
                            justifyContent: "space-between",
                            alignItems: "baseline",
                            gap: 2,
                        }}
                    >
                        <Typography sx={mutedCaptionSx}>
                            {uploadStatusText(uploadPhase)}
                        </Typography>
                        <Typography sx={mutedCaptionSx}>{"100%"}</Typography>
                    </Stack>
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
const headerIconButtonSx = { width: 38, height: 38, p: 0, color: "text.base" };
const closeIconButtonSx = (theme: Theme) => ({
    ...headerIconButtonSx,
    backgroundColor: "background.paper",
    "&:hover": { backgroundColor: "fill.faintHover" },
    ...theme.applyStyles("dark", {
        backgroundColor: "rgba(255 255 255 / 0.12)",
    }),
});
const titleTextSx = { fontSize: 24, lineHeight: "32px", fontWeight: 600 };
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
