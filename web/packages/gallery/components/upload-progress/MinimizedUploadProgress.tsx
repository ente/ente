import { DragDropVerticalIcon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import CloseIcon from "@mui/icons-material/Close";
import UnfoldMoreIcon from "@mui/icons-material/UnfoldMore";
import {
    Box,
    IconButton,
    keyframes,
    Paper,
    Snackbar,
    Stack,
    Typography,
    type Theme,
} from "@mui/material";
import type { SystemStyleObject } from "@mui/system";
import { t } from "i18next";
import { useRef } from "react";
import { uploadCompletionCounts } from "../upload-progress-stats";
import { uploadSheetMediaQuery } from "./bottom-sheet";
import type { DragPosition } from "./context";
import { useUploadProgressContext } from "./context";
import {
    normalizePercent,
    uploadCountsText,
    uploadETAText,
    uploadStatusText,
} from "./helpers";
import { useMinimizedUploadDrag } from "./use-minimized-upload-drag";

export function MinimizedUploadProgress() {
    const context = useUploadProgressContext();
    const { onClose, percentComplete, setExpanded, uploadETA } = context;
    const dragSurfaceRef = useRef<HTMLDivElement>(null);
    const { dragPosition, dragHandleProps } =
        useMinimizedUploadDrag(dragSurfaceRef);
    const progress = normalizePercent(percentComplete);
    const showUploadProgress = context.uploadPhase == "uploading";
    const etaText = showUploadProgress ? uploadETAText(uploadETA) : undefined;
    const hasFailures =
        uploadCompletionCounts(
            context.finishedUploads,
            context.preUploadSkippedFiles,
        ).failed > 0;
    let title = t("file_upload");
    if (context.uploadPhase == "done" && hasFailures) {
        title = t("failed_uploads");
    } else if (showUploadProgress) {
        title = t("uploaded_percent", { percent: progress });
    } else if (context.uploadPhase == "done") {
        title = uploadStatusText(context.uploadPhase);
    }

    const setDragSurface = (surface: HTMLDivElement | null) => {
        dragSurfaceRef.current = surface;
    };
    const handleExpand = () => setExpanded(true);

    return (
        <Snackbar
            open
            anchorOrigin={{ horizontal: "right", vertical: "bottom" }}
            sx={minimizedSnackbarSx}
        >
            <Paper
                ref={setDragSurface}
                sx={[
                    (theme) => minimizedPaperSx(theme, hasFailures),
                    minimizedPositionSx(dragPosition),
                ]}
            >
                <Stack
                    direction="row"
                    sx={{ alignItems: "center", gap: 2, minWidth: 0 }}
                >
                    <Box
                        {...dragHandleProps}
                        aria-hidden
                        sx={[
                            minimizedDragIconSx,
                            hasFailures && failureForegroundSx,
                        ]}
                    >
                        <HugeiconsIcon
                            icon={DragDropVerticalIcon}
                            size={26}
                            strokeWidth={2.8}
                        />
                    </Box>
                    <Stack sx={{ flex: 1, minWidth: 0, gap: 0.5 }}>
                        <Typography sx={minimizedTitleSx}>{title}</Typography>
                        <Typography
                            sx={[
                                minimizedSubtitleSx,
                                hasFailures && {
                                    ...failureForegroundSx,
                                    whiteSpace: "normal",
                                    overflowWrap: "anywhere",
                                },
                            ]}
                        >
                            {showUploadProgress ||
                            context.uploadPhase == "done" ||
                            hasFailures
                                ? uploadCountsText(context)
                                : uploadStatusText(context.uploadPhase)}
                        </Typography>
                        {etaText && (
                            <Typography
                                sx={[
                                    minimizedSubtitleSx,
                                    {
                                        whiteSpace: "normal",
                                        overflowWrap: "anywhere",
                                    },
                                    hasFailures && failureForegroundSx,
                                ]}
                            >
                                {etaText}
                            </Typography>
                        )}
                    </Stack>
                    <IconButton
                        aria-label={t("expand")}
                        onClick={handleExpand}
                        sx={[
                            minimizedIconButtonSx,
                            hasFailures && failureForegroundSx,
                        ]}
                    >
                        <UnfoldMoreIcon sx={{ fontSize: 22 }} />
                    </IconButton>
                    <IconButton
                        aria-label={t("close")}
                        onClick={onClose}
                        sx={[
                            minimizedIconButtonSx,
                            hasFailures && failureForegroundSx,
                        ]}
                    >
                        <CloseIcon sx={{ fontSize: 22 }} />
                    </IconButton>
                </Stack>
            </Paper>
        </Snackbar>
    );
}

const ellipsisSx = {
    minWidth: 0,
    overflow: "hidden",
    textOverflow: "ellipsis",
    whiteSpace: "nowrap",
};
const minimizedRiseAnimation = keyframes`
    from { transform: translateY(48px); opacity: 0.6; }
    to { transform: translateY(0); opacity: 1; }
`;
const minimizedSnackbarSx = {
    [uploadSheetMediaQuery]: {
        left: "16px",
        right: "16px",
        bottom: "calc(32px + env(safe-area-inset-bottom, 0px))",
    },
};
const minimizedPaperSx = (
    theme: Theme,
    hasFailures: boolean,
): SystemStyleObject<Theme> => ({
    width: "min(400px, calc(100svw - 32px))",
    p: "16px 16px 16px 12px",
    borderRadius: "20px",
    backgroundColor: hasFailures ? "critical.main" : "#fff",
    backgroundImage: "none",
    boxShadow: "0px 4px 4px rgba(0 0 0 / 0.16)",
    color: hasFailures ? "critical.contrastText" : "text.base",
    overflow: "hidden",
    [uploadSheetMediaQuery]: {
        width: "calc(100svw - 32px)",
        animation: `${minimizedRiseAnimation} 320ms cubic-bezier(0.2, 0.8, 0.2, 1)`,
        "@media (prefers-reduced-motion: reduce)": { animation: "none" },
    },
    ...theme.applyStyles("dark", {
        backgroundColor: hasFailures ? "critical.main" : "#2b2b2b",
    }),
});
const failureForegroundSx = { color: "inherit" };
const minimizedDragIconSx = {
    display: "inline-flex",
    flexShrink: 0,
    color: "text.muted",
    cursor: "grab",
    touchAction: "none",
    userSelect: "none",
    "&:active": { cursor: "grabbing" },
};
const minimizedIconButtonSx = {
    width: 40,
    height: 40,
    p: 0,
    flexShrink: 0,
    color: "text.base",
    backgroundColor: "fill.faint",
    "&:hover": { backgroundColor: "fill.faintHover" },
};
const minimizedTitleSx = { fontSize: 16, lineHeight: "20px", fontWeight: 600 };
const minimizedSubtitleSx = {
    ...ellipsisSx,
    fontSize: 14,
    lineHeight: "17px",
    color: "text.muted",
    fontVariantNumeric: "tabular-nums",
};

const minimizedPositionSx = (dragPosition: DragPosition | undefined) =>
    dragPosition
        ? {
              position: "fixed",
              left: `${dragPosition.x}px`,
              top: `${dragPosition.y}px`,
              margin: 0,
          }
        : {};
