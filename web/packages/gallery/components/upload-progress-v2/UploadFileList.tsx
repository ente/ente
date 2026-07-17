import { Alert02Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import ErrorOutlineIcon from "@mui/icons-material/ErrorOutlineOutlined";
import ImageOutlinedIcon from "@mui/icons-material/ImageOutlined";
import MovieOutlinedIcon from "@mui/icons-material/MovieOutlined";
import PlayArrowOutlinedIcon from "@mui/icons-material/PlayArrowOutlined";
import {
    Box,
    LinearProgress,
    Stack,
    Typography,
    type Theme,
} from "@mui/material";
import { useEffect, useRef } from "react";
import { VariableSizeList } from "react-window";
import { uploadStatColors } from "../uploadProgressStats";
import { useUploadProgressContext } from "./context";
import { uploadStatusText } from "./helpers";

export interface ListedFile {
    name: string;
    title?: string;
    reason?: string;
    reasonHint?: string;
}

interface UploadFileListProps {
    files: ListedFile[];
    maxHeight: number;
    reasonColor: string;
    isFailedReason: boolean;
}

export function UploadFileList({
    files,
    maxHeight,
    reasonColor,
    isFailedReason,
}: UploadFileListProps) {
    const listRef = useRef<VariableSizeList | null>(null);

    // Cached row heights depend on the file at each index, so recompute them
    // when the backing list changes (e.g. on tab switch).
    useEffect(() => {
        listRef.current?.resetAfterIndex(0);
    }, [files]);

    const rowHeight = (file: ListedFile) =>
        file.reasonHint ? listedRowWithHintHeight : listedRowHeight;

    const height = Math.min(
        files.reduce((h, file) => h + rowHeight(file), 0),
        maxHeight,
    );

    return (
        <VariableSizeList
            ref={listRef}
            className="upload-file-list"
            height={height}
            width="100%"
            itemCount={files.length}
            itemSize={(index) => rowHeight(files[index]!)}
        >
            {({ index, style }) => (
                <div style={style}>
                    <UploadFileRow
                        {...files[index]!}
                        reasonColor={reasonColor}
                        isFailedReason={isFailedReason}
                        topBorder={index > 0}
                    />
                </div>
            )}
        </VariableSizeList>
    );
}

function FileTypeIcon({ name }: { name: string }) {
    return (
        <Box aria-hidden sx={fileIconSx}>
            {/\.(avi|m4v|mkv|mov|mp4|webm)$/i.test(name) ? (
                <PlayArrowOutlinedIcon sx={{ fontSize: 18 }} />
            ) : (
                <ImageOutlinedIcon sx={{ fontSize: 18 }} />
            )}
        </Box>
    );
}

export function UploadProgressRow({
    name,
    progress,
}: {
    name: string;
    progress: number;
}) {
    return (
        <Box sx={uploadRowSx}>
            <Stack
                direction="row"
                sx={{ alignItems: "center", gap: 1.5, minWidth: 0 }}
            >
                <FileTypeIcon name={name} />
                <Typography title={name} sx={fileNameSx}>
                    {name}
                </Typography>
            </Stack>
            <Stack
                direction="row"
                sx={{
                    alignItems: "center",
                    gap: 1.5,
                    justifyContent: "flex-end",
                    minWidth: 0,
                }}
            >
                <LinearProgress
                    variant="determinate"
                    value={progress}
                    sx={rowProgressSx}
                />
                <Typography sx={rowProgressLabelSx}>{progress}%</Typography>
            </Stack>
        </Box>
    );
}

function UploadFileRow({
    name,
    title,
    reason,
    reasonHint,
    reasonColor,
    isFailedReason,
    topBorder,
}: ListedFile & {
    reasonColor: string;
    isFailedReason: boolean;
    topBorder: boolean;
}) {
    return (
        <Stack
            direction="row"
            sx={[fileRowSx, !topBorder && { borderTop: "none" }]}
        >
            <FileTypeIcon name={name} />
            <Typography title={title ?? name} sx={fileNameSx}>
                {name}
            </Typography>
            {reason && (
                <Stack sx={fileReasonSx}>
                    <Stack
                        direction="row"
                        sx={{
                            alignItems: "center",
                            gap: 0.75,
                            justifyContent: "flex-end",
                        }}
                    >
                        {isFailedReason ? (
                            <HugeiconsIcon
                                icon={Alert02Icon}
                                size={18}
                                color={reasonColor}
                            />
                        ) : (
                            <ErrorOutlineIcon
                                sx={{ fontSize: 18, color: reasonColor }}
                            />
                        )}
                        <Typography sx={fileReasonTextSx}>{reason}</Typography>
                    </Stack>
                    {reasonHint && (
                        <Typography sx={fileReasonHintSx}>
                            {reasonHint}
                        </Typography>
                    )}
                </Stack>
            )}
        </Stack>
    );
}

export function EmptyUploadRows({ message }: { message?: string }) {
    const { uploadPhase } = useUploadProgressContext();

    return (
        <Stack sx={emptyRowsSx}>
            <MovieOutlinedIcon sx={{ fontSize: 24 }} />
            <Typography sx={mutedCaptionSx}>
                {message ?? uploadStatusText(uploadPhase)}
            </Typography>
        </Stack>
    );
}

const progressGreen = uploadStatColors.completed;
const uploadSurfaceStroke = "#e0e0e0";
const uploadSurfaceStrokeDark = "rgba(255 255 255 / 0.12)";
const uploadMutedText = "text.muted";
const uploadMutedFill = "fill.muted";
const ellipsisSx = {
    minWidth: 0,
    overflow: "hidden",
    textOverflow: "ellipsis",
    whiteSpace: "nowrap",
};
const mutedCaptionSx = {
    color: uploadMutedText,
    fontSize: 12,
    lineHeight: "16px",
    fontWeight: 500,
};
const listedRowHeight = 60;
const listedRowWithHintHeight = 92;
const rowShellSx = (theme: Theme) => ({
    minHeight: listedRowHeight,
    px: 1.5,
    py: 1.5,
    alignItems: "center",
    borderTop: `1px solid ${uploadSurfaceStroke}`,
    ...theme.applyStyles("dark", { borderTopColor: uploadSurfaceStrokeDark }),
});
const fileRowSx = (theme: Theme) => ({
    ...rowShellSx(theme),
    height: "100%",
    gap: 1.5,
});
const uploadRowSx = (theme: Theme) => ({
    ...rowShellSx(theme),
    "&:first-of-type": { borderTop: "none" },
    display: "grid",
    gridTemplateColumns: "minmax(160px, 1fr) minmax(180px, 244px)",
    gap: "24px",
    "@media (max-width: 620px)": {
        gridTemplateColumns: "1fr",
        gap: 1,
        "& > :nth-of-type(2)": { gridColumn: "1 / -1", gridRow: 2 },
    },
});
const fileIconSx = {
    width: 36,
    height: 36,
    borderRadius: "12px",
    display: "flex",
    alignItems: "center",
    justifyContent: "center",
    flexShrink: 0,
    color: "stroke.muted",
};
const fileNameSx = {
    ...ellipsisSx,
    fontSize: 14,
    lineHeight: "20px",
    fontWeight: 500,
};
const fileReasonSx = {
    marginLeft: "auto",
    alignItems: "flex-end",
    gap: 0.5,
    flexShrink: 0,
    pr: 0.5,
};
const fileReasonTextSx = { ...mutedCaptionSx, whiteSpace: "nowrap" };
const fileReasonHintSx = {
    color: uploadMutedText,
    opacity: 0.6,
    fontSize: 10,
    lineHeight: "14px",
    fontWeight: 500,
    maxWidth: 200,
    textAlign: "right",
};
const rowProgressSx = {
    flex: "1 1 172px",
    maxWidth: 172,
    height: 5,
    borderRadius: "16px",
    backgroundColor: uploadMutedFill,
    "& .MuiLinearProgress-bar": {
        borderRadius: "35px",
        backgroundColor: progressGreen,
    },
};
const rowProgressLabelSx = { width: 46, flexShrink: 0, ...mutedCaptionSx };
const emptyRowsSx = (theme: Theme) => ({
    minHeight: 3 * listedRowHeight,
    alignItems: "center",
    justifyContent: "center",
    gap: 1,
    color: "text.muted",
    borderTop: `1px solid ${uploadSurfaceStroke}`,
    ...theme.applyStyles("dark", { borderTopColor: uploadSurfaceStrokeDark }),
});
