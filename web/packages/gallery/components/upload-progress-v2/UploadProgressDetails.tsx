import { Box, Button, Stack, Typography, type Theme } from "@mui/material";
import type { SystemStyleObject } from "@mui/system";
import { basename } from "ente-base/file-name";
import { t } from "i18next";
import { useState } from "react";
import {
    statFinishedTypes,
    uploadProgressStatCounts,
    uploadStatColors,
    type UploadStatKind,
} from "../uploadProgressStats";
import { useUploadProgressContext } from "./context";
import {
    doneStatConfigs,
    finishedTypeReasonHints,
    finishedTypeReasons,
    normalizePercent,
    preUploadSkippedFileReasons,
    statConfigs,
    statEmptyMessages,
} from "./helpers";
import {
    EmptyUploadRows,
    UploadFileList,
    UploadProgressRow,
    type ListedFile,
} from "./UploadFileList";

export function UploadProgressDetails({ closeOnly }: { closeOnly: boolean }) {
    const {
        finishedUploads,
        hasLivePhotos,
        inProgressUploads,
        retryFailed,
        preUploadSkippedFiles,
        uploadCounter,
        uploadFileNames,
        uploadPhase,
        onClose,
    } = useUploadProgressContext();
    const isDone = uploadPhase == "done";

    const [selectedStat, setSelectedStat] = useState<UploadStatKind>();
    const [selectedReason, setSelectedReason] = useState<string>();

    const statCounts = uploadProgressStatCounts({
        uploadPhase,
        uploadCounter,
        inProgressUploads,
        finishedUploads,
        preUploadSkippedFiles,
    });
    const failedCount = statCounts.failed;
    const activeStat =
        selectedStat ??
        (isDone ? (failedCount > 0 ? "failed" : "completed") : "inProgress");

    const handleSelectStat = (kind: UploadStatKind) => {
        setSelectedStat(kind);
        setSelectedReason(undefined);
    };
    const visibleStatConfigs = isDone ? doneStatConfigs : statConfigs;

    const listedFiles: ListedFile[] =
        activeStat == "inProgress"
            ? []
            : [
                  ...statFinishedTypes[activeStat].flatMap((type) => {
                      const reason =
                          type == "uploadedWithStaticThumbnail"
                              ? t("thumbnail_generation_failed")
                              : finishedTypeReasons[type];
                      const reasonHint = finishedTypeReasonHints[type];
                      return (finishedUploads.get(type) ?? []).map((id) => ({
                          name: uploadFileNames.get(id) ?? t("file"),
                          reason,
                          reasonHint,
                      }));
                  }),
                  ...(activeStat == "skipped"
                      ? preUploadSkippedFiles.map((file) => ({
                            name: basename(file.name),
                            title: file.name,
                            reason: preUploadSkippedFileReasons[file.type],
                        }))
                      : []),
              ];

    const reasonCounts = new Map<string, number>();
    if (!isDone) {
        for (const { reason } of listedFiles) {
            if (reason) {
                reasonCounts.set(reason, (reasonCounts.get(reason) ?? 0) + 1);
            }
        }
    }

    const activeStatColor = statConfigs.find(
        ({ kind }) => kind == activeStat,
    )!.color;

    const activeReason =
        !isDone && selectedReason && reasonCounts.has(selectedReason)
            ? selectedReason
            : undefined;

    const visibleFiles = activeReason
        ? listedFiles.filter(({ reason }) => reason == activeReason)
        : listedFiles;

    const handleSelectReason = (reason: string) => {
        setSelectedReason(reason == activeReason ? undefined : reason);
    };

    return (
        <Stack sx={{ gap: isDone ? 3 : 2 }}>
            {!isDone && (
                <Typography component="h3" sx={detailsTitleSx}>
                    {t("details")}
                </Typography>
            )}
            <Box sx={detailsCardSx}>
                <Box sx={statsGridSx(isDone)}>
                    {visibleStatConfigs.map(({ kind, color, label }) => (
                        <UploadStat
                            key={kind}
                            active={activeStat == kind}
                            color={color}
                            kind={kind}
                            label={label}
                            value={statCounts[kind]}
                            onSelect={handleSelectStat}
                        />
                    ))}
                </Box>
                {!isDone && reasonCounts.size > 0 && (
                    <Stack direction="row" sx={reasonSummarySx}>
                        {[...reasonCounts].map(([reason, count]) => (
                            <ReasonTab
                                key={reason}
                                active={reason == activeReason}
                                count={count}
                                reason={reason}
                                onSelect={handleSelectReason}
                            />
                        ))}
                    </Stack>
                )}
                {activeStat == "failed" && !isDone && failedCount > 0 && (
                    <Typography sx={failedUploadsHintSx}>
                        {t("failed_uploads_hint")}
                    </Typography>
                )}
                <Box sx={uploadRowsSx(isDone)}>
                    {activeStat == "inProgress" ? (
                        inProgressUploads.length ? (
                            inProgressUploads.map(
                                ({ localFileID, progress }) => (
                                    <UploadProgressRow
                                        key={localFileID}
                                        name={
                                            uploadFileNames.get(localFileID) ??
                                            t("file")
                                        }
                                        progress={normalizePercent(progress)}
                                    />
                                ),
                            )
                        ) : (
                            <EmptyUploadRows />
                        )
                    ) : visibleFiles.length ? (
                        <UploadFileList
                            files={visibleFiles}
                            maxHeight={
                                isDone ? doneRowsListHeight : maxRowsListHeight
                            }
                            reasonColor={activeStatColor}
                            isFailedReason={activeStat == "failed"}
                        />
                    ) : (
                        <EmptyUploadRows
                            message={statEmptyMessages[activeStat]}
                        />
                    )}
                </Box>
                {hasLivePhotos && (
                    <Typography sx={livePhotosTextSx}>
                        {t("live_photos_detected")}
                    </Typography>
                )}
            </Box>
            {isDone && (closeOnly || failedCount > 0) && (
                <Button
                    fullWidth
                    onClick={closeOnly ? onClose : retryFailed}
                    sx={retryButtonSx}
                >
                    {t(closeOnly ? "close" : "retry_failed_uploads")}
                </Button>
            )}
        </Stack>
    );
}

interface ReasonTabProps {
    active: boolean;
    count: number;
    reason: string;
    onSelect: (reason: string) => void;
}

function ReasonTab({ active, count, reason, onSelect }: ReasonTabProps) {
    const handleClick = () => onSelect(reason);

    return (
        <Box
            component="button"
            type="button"
            aria-pressed={active}
            onClick={handleClick}
            sx={reasonTabSx}
        >
            <Typography
                className="reason-label"
                sx={[mutedCaptionSx, active && { color: "text.base" }]}
            >
                {reason}
            </Typography>
            <Typography sx={reasonSummaryCountSx}>{"•"}</Typography>
            <Typography sx={reasonSummaryCountSx}>
                {count.toLocaleString()}
            </Typography>
            <Box
                aria-hidden
                className="reason-underline"
                sx={{
                    ...reasonTabUnderlineSx,
                    backgroundColor: active ? progressGreen : "transparent",
                }}
            />
        </Box>
    );
}

interface UploadStatProps {
    active: boolean;
    color: string;
    kind: UploadStatKind;
    label: string;
    value: number;
    onSelect: (kind: UploadStatKind) => void;
}

function UploadStat({
    active,
    color,
    kind,
    label,
    value,
    onSelect,
}: UploadStatProps) {
    const handleClick = () => onSelect(kind);

    return (
        <Box
            component="button"
            type="button"
            aria-pressed={active}
            onClick={handleClick}
            sx={[statTileSx, active && activeStatTileSx]}
        >
            <Stack direction="row" sx={{ alignItems: "center", gap: 0.5 }}>
                <Box sx={{ ...statDotSx, backgroundColor: color }} />
                <Typography sx={statLabelSx}>{label}</Typography>
            </Stack>
            <Typography sx={statValueSx}>{value.toLocaleString()}</Typography>
            <Box
                aria-hidden
                className="stat-underline"
                sx={{
                    ...statUnderlineSx,
                    backgroundColor: active ? progressGreen : "fill.muted",
                }}
            />
        </Box>
    );
}

const progressGreen = uploadStatColors.completed;
const ellipsisSx = {
    minWidth: 0,
    overflow: "hidden",
    textOverflow: "ellipsis",
    whiteSpace: "nowrap",
};
const mutedCaptionSx = {
    color: "text.muted",
    fontSize: 12,
    lineHeight: "16px",
    fontWeight: 500,
};
const maxRowsListHeight = 181;
const listedRowHeight = 60;
const doneRowsListHeight = 5 * listedRowHeight;
const minRowsListHeight = 3 * listedRowHeight;

const detailsTitleSx = {
    pl: "8px",
    fontSize: 18,
    lineHeight: "24px",
    fontWeight: 600,
};
const detailsCardSx = (theme: Theme) => ({
    p: "16px 8px",
    borderRadius: "20px",
    backgroundColor: "background.paper",
    ...theme.applyStyles("dark", { backgroundColor: "#282828" }),
});
const statsGridSx = (isDone: boolean) => ({
    display: "grid",
    gridTemplateColumns: `repeat(${isDone ? 3 : 4}, minmax(0, 1fr))`,
    gap: "10px",
    "@media (max-width: 620px)": {
        gridTemplateColumns: "repeat(2, minmax(0, 1fr))",
    },
});
const statTileSx = (theme: Theme): SystemStyleObject<Theme> => ({
    position: "relative",
    minWidth: 0,
    minHeight: 71,
    p: "12px 20px 19px",
    display: "flex",
    flexDirection: "column",
    gap: "4px",
    borderRadius: "16px 16px 0 0",
    border: 0,
    background: "transparent",
    textAlign: "left",
    cursor: "pointer",
    "&:hover": { backgroundColor: "rgba(0 0 0 / 0.02)" },
    "&:hover .stat-underline": { backgroundColor: "stroke.base" },
    ...theme.applyStyles("dark", {
        "&:hover": { backgroundColor: "rgba(255 255 255 / 0.03)" },
    }),
});
const activeStatTileSx = {
    background:
        "linear-gradient(0deg, rgba(8, 194, 37, 0.16) 1.57%, rgba(8, 194, 37, 0) 49.33%)",
    "&:hover .stat-underline": { backgroundColor: progressGreen },
};
const statDotSx = { width: 6, height: 6, borderRadius: "50%", flexShrink: 0 };
const statLabelSx = { ...ellipsisSx, ...mutedCaptionSx };
const statValueSx = { fontSize: 16, lineHeight: "20px", fontWeight: 600 };
const statUnderlineSx = {
    position: "absolute",
    inset: "auto 0 0",
    height: 3,
    borderRadius: "200px",
};
const uploadRowsSx =
    (isDone: boolean) =>
    (theme: Theme): SystemStyleObject<Theme> => ({
        mt: 2,
        minHeight: minRowsListHeight,
        maxHeight: isDone ? doneRowsListHeight : maxRowsListHeight,
        overflowY: "auto",
        "&, & .upload-file-list": {
            scrollbarWidth: "thin",
            scrollbarColor: "rgba(0 0 0 / 0.2) transparent",
        },
        "&::-webkit-scrollbar, & .upload-file-list::-webkit-scrollbar": {
            width: 6,
        },
        "&::-webkit-scrollbar-track, & .upload-file-list::-webkit-scrollbar-track":
            { background: "transparent" },
        "&::-webkit-scrollbar-thumb, & .upload-file-list::-webkit-scrollbar-thumb":
            { borderRadius: "8px", backgroundColor: "rgba(0 0 0 / 0.2)" },
        ...theme.applyStyles("dark", {
            "&, & .upload-file-list": {
                scrollbarColor: "rgba(255 255 255 / 0.2) transparent",
            },
            "&::-webkit-scrollbar-thumb, & .upload-file-list::-webkit-scrollbar-thumb":
                { backgroundColor: "rgba(255 255 255 / 0.2)" },
        }),
    });
const failedUploadsHintSx = { mt: 2, px: 1.5, ...mutedCaptionSx };
const reasonSummarySx = (theme: Theme): SystemStyleObject<Theme> => ({
    p: "6px 4px 0",
    gap: 0.5,
    flexWrap: "wrap",
    borderRadius: "0 0 12px 12px",
    backgroundColor: "rgba(0 0 0 / 0.03)",
    ...theme.applyStyles("dark", {
        backgroundColor: "rgba(255 255 255 / 0.04)",
    }),
});
const reasonSummaryCountSx = { ...mutedCaptionSx, color: "text.faint" };
const reasonTabSx = {
    position: "relative",
    display: "flex",
    alignItems: "center",
    gap: 0.75,
    p: "4px 10px 8px",
    border: 0,
    borderRadius: "8px 8px 0 0",
    background: "transparent",
    cursor: "pointer",
    "&:hover .reason-underline": { backgroundColor: progressGreen },
    "&:hover .reason-label": { color: "text.base" },
};
const reasonTabUnderlineSx = {
    position: "absolute",
    inset: "auto 0 0",
    height: 2,
    borderRadius: "200px",
};
const livePhotosTextSx = { mt: 1, px: 1.5, ...mutedCaptionSx };
const retryButtonSx = {
    minHeight: 52,
    px: 3,
    py: "14px",
    borderRadius: "20px",
    color: "#fff",
    backgroundColor: progressGreen,
    boxShadow: "none",
    textTransform: "none",
    fontSize: 14,
    lineHeight: "20px",
    fontWeight: 500,
    "&:hover": { backgroundColor: progressGreen, boxShadow: "none" },
};
