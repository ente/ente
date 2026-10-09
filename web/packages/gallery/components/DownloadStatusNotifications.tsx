import {
    Download01Icon,
    Loading03Icon,
    Tick02Icon,
} from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import ErrorOutlinedIcon from "@mui/icons-material/ErrorOutlined";
import ReplayIcon from "@mui/icons-material/Replay";
import {
    Box,
    Button,
    Dialog,
    keyframes,
    styled,
    Typography,
} from "@mui/material";
import { Notification } from "ente-base/components/Notification";
import { useBaseContext } from "ente-base/context";
import {
    isSaveComplete,
    isSaveCompleteWithErrors,
    type SaveGroup,
} from "ente-gallery/components/utils/save-groups";
import { t } from "i18next";
import { useState } from "react";

const MAX_ALBUM_NAME_LENGTH = 25;
const SINGLE_FILE_SUCCESS_AUTO_CLOSE_DELAY_MS = 3000;

const truncateAlbumName = (name: string): string => {
    if (name.length <= MAX_ALBUM_NAME_LENGTH) return name;
    return name.slice(0, MAX_ALBUM_NAME_LENGTH) + "...";
};

export interface DownloadStatusNotificationsProps {
    saveGroups: SaveGroup[];
    onRemoveSaveGroup: (saveGroup: SaveGroup) => void;
    onShowCollectionSummary?: (
        collectionSummaryID: number | undefined,
        isHiddenCollectionSummary: boolean | undefined,
    ) => void;
    fullWidthOnMobile?: boolean;
}

export const DownloadStatusNotifications: React.FC<
    DownloadStatusNotificationsProps
> = ({
    saveGroups,
    onRemoveSaveGroup,
    onShowCollectionSummary,
    fullWidthOnMobile,
}) => {
    const { showMiniDialog } = useBaseContext();
    const fileLabel = t("file").toLowerCase();
    const [cancelDownloadGroup, setCancelDownloadGroup] =
        useState<SaveGroup | null>(null);

    const closeCancelDownloadDialog = () => setCancelDownloadGroup(null);

    const confirmCancelDownload = (group: SaveGroup) => {
        if (fullWidthOnMobile) {
            setCancelDownloadGroup(group);
            return;
        }

        showMiniDialog({
            title: t("stop_downloads_title"),
            message: t("stop_downloads_message"),
            continue: {
                text: t("yes_stop_downloads"),
                color: "critical",
                action: () => {
                    group.canceller.abort();
                    onRemoveSaveGroup(group);
                },
            },
            cancel: t("no"),
        });
    };

    const handleConfirmCancelDownload = () => {
        if (!cancelDownloadGroup) return;
        cancelDownloadGroup.canceller.abort();
        onRemoveSaveGroup(cancelDownloadGroup);
        closeCancelDownloadDialog();
    };

    const createOnClose = (group: SaveGroup) => () => {
        if (isSaveComplete(group)) {
            onRemoveSaveGroup(group);
        } else {
            confirmCancelDownload(group);
        }
    };

    const createOnClick = (group: SaveGroup) => () => {
        const electron = globalThis.electron;
        if (electron && group.downloadDirPath) {
            void electron.openDirectory(group.downloadDirPath);
        } else if (onShowCollectionSummary) {
            onShowCollectionSummary(
                group.collectionSummaryID,
                group.isHiddenCollectionSummary,
            );
        } else {
            return undefined;
        }
    };

    return (
        <>
            {saveGroups.map((group, index) => {
                const hasErrors = isSaveCompleteWithErrors(group);
                const isComplete = isSaveComplete(group);
                const canRetry = hasErrors && !!group.retry;
                const shouldAutoClose =
                    group.total === 1 && isComplete && !hasErrors;

                const isZipDownload = !group.downloadDirPath && group.total > 1;
                const shouldShowZipPart =
                    isZipDownload &&
                    (group.includeZipNumber || (group.currentPart ?? 1) > 1);
                const isDesktopOrSingleFile =
                    !!group.downloadDirPath || group.total === 1;

                let statusText: React.ReactNode;
                if (hasErrors) {
                    if (group.failureReason === "network_offline") {
                        statusText = t("download_failed_network_offline");
                    } else if (group.failureReason === "file_error") {
                        statusText = t("download_failed_file_error");
                    } else if (group.failureReason === "blob_creation_failed") {
                        statusText = t("download_failed_blob_creation_failed");
                    } else {
                        statusText = t("download_failed");
                    }
                } else if (isComplete) {
                    statusText = t("download_complete");
                } else if (shouldShowZipPart) {
                    const part = group.currentPart ?? 1;
                    statusText = group.isDownloadingZip
                        ? t("downloading_part", { part })
                        : t("preparing_part", { part });
                } else if (isZipDownload) {
                    statusText = group.isDownloadingZip
                        ? t("downloading")
                        : t("preparing");
                } else if (isDesktopOrSingleFile) {
                    statusText =
                        group.total === 1
                            ? t("downloading_file")
                            : t("downloading_files");
                } else {
                    statusText = t("downloading");
                }

                const completedCount = group.success + group.failed;
                const progress =
                    group.total === 1
                        ? undefined
                        : t("download_progress", {
                              count: completedCount,
                              total: group.total,
                          });
                const caption = (
                    <Box
                        component="span"
                        sx={{
                            color: hasErrors ? "white" : "text.muted",
                            fontVariantNumeric: "tabular-nums",
                        }}
                    >
                        {statusText}
                        {!isComplete && progress !== undefined && (
                            <>
                                {" "}
                                {"\u2022"} {progress}
                            </>
                        )}
                    </Box>
                );

                let startIcon: React.ReactNode;
                if (hasErrors) {
                    startIcon = <ErrorOutlinedIcon />;
                } else if (isComplete) {
                    startIcon = (
                        <GlowingIconWrapper>
                            <HugeiconsIcon icon={Tick02Icon} size={28} />
                        </GlowingIconWrapper>
                    );
                } else if (
                    group.total === 1 ||
                    (isZipDownload && !group.isDownloadingZip)
                ) {
                    startIcon = <SpinningIcon />;
                } else {
                    startIcon = (
                        <DroppingIconWrapper>
                            <HugeiconsIcon icon={Download01Icon} size={28} />
                        </DroppingIconWrapper>
                    );
                }

                const filesCountTitle = t("files_count", {
                    count: group.total,
                });
                const title =
                    group.total === 1 && group.title === filesCountTitle
                        ? `${group.total} ${fileLabel}`
                        : group.title;
                const truncatedName = truncateAlbumName(title);

                return (
                    <Notification
                        key={group.id}
                        horizontal="left"
                        sx={(theme) => ({
                            "&&": { bottom: `${index * 80 + 20}px` },
                            width: "min(400px, 100vw)",
                            borderRadius: "20px",
                            "& .MuiButton-root": {
                                borderRadius: "20px",
                                padding: "16px 16px 16px 20px",
                            },
                            "& .MuiIconButton-root": {
                                width: "40px",
                                height: "40px",
                                "& svg": { fontSize: "22px" },
                            },
                            [theme.breakpoints.down("sm")]: {
                                "&&": {
                                    bottom: `${index * 70 + 16}px`,
                                    ...(fullWidthOnMobile
                                        ? { left: "8px" }
                                        : {}),
                                },
                                width: fullWidthOnMobile
                                    ? "calc(100vw - 16px)"
                                    : "min(340px, calc(100vw - 16px))",
                                borderRadius: "16px",
                                "& .MuiButton-root": {
                                    borderRadius: "16px",
                                    padding: "12px 12px 12px 16px",
                                },
                                "& .MuiIconButton-root": {
                                    width: "36px",
                                    height: "36px",
                                    "& svg": { fontSize: "20px" },
                                },
                            },
                        })}
                        open={true}
                        onClose={createOnClose(group)}
                        autoHideDuration={
                            shouldAutoClose
                                ? SINGLE_FILE_SUCCESS_AUTO_CLOSE_DELAY_MS
                                : undefined
                        }
                        keepOpenOnClick
                        attributes={{
                            color: hasErrors ? "critical" : "secondary",
                            startIcon,
                            title: truncatedName,
                            caption,
                            onClick: createOnClick(group),
                            endIcon: canRetry ? (
                                <ReplayIcon
                                    titleAccess={t("retry")}
                                    sx={{ color: "white" }}
                                />
                            ) : undefined,
                            onEndIconClick: canRetry
                                ? () => group.retry?.()
                                : undefined,
                            showCloseButtonWithEndIcon: canRetry,
                        }}
                    />
                );
            })}

            {fullWidthOnMobile && (
                <StyledStopDownloadDialog
                    open={!!cancelDownloadGroup}
                    onClose={closeCancelDownloadDialog}
                >
                    <StopDownloadDialogWrapper>
                        <StopDownloadTitleSection>
                            <Typography
                                sx={{
                                    fontWeight: 600,
                                    fontSize: 24,
                                    lineHeight: "28px",
                                    letterSpacing: "-0.48px",
                                    textAlign: "center",
                                }}
                            >
                                {t("stop_downloads_title")}
                            </Typography>
                            <StopDownloadSubtitle>
                                {t("stop_downloads_message")}
                            </StopDownloadSubtitle>
                        </StopDownloadTitleSection>
                        <StopDownloadButtonsSection>
                            <StopDownloadPrimaryButton
                                fullWidth
                                onClick={handleConfirmCancelDownload}
                            >
                                {t("yes_stop_downloads")}
                            </StopDownloadPrimaryButton>
                            <StopDownloadSecondaryButton
                                fullWidth
                                onClick={closeCancelDownloadDialog}
                            >
                                {t("no")}
                            </StopDownloadSecondaryButton>
                        </StopDownloadButtonsSection>
                    </StopDownloadDialogWrapper>
                </StyledStopDownloadDialog>
            )}
        </>
    );
};

const StyledStopDownloadDialog = styled(Dialog)(({ theme }) => ({
    "& .MuiDialog-paper": {
        width: 381,
        maxWidth: "calc(100% - 32px)",
        borderRadius: 28,
        backgroundColor: "#fff",
        padding: 0,
        margin: 16,
        boxShadow: "none",
        border: "1px solid #E0E0E0",
        ...theme.applyStyles("dark", {
            backgroundColor: "#1b1b1b",
            border: "1px solid rgba(255, 255, 255, 0.18)",
        }),
    },
    "& .MuiBackdrop-root": { backgroundColor: "rgba(0, 0, 0, 0.5)" },
}));

const StopDownloadDialogWrapper = styled(Box)(() => ({
    padding: "40px 16px 16px 16px",
}));

const StopDownloadTitleSection = styled(Box)(() => ({
    display: "flex",
    flexDirection: "column",
    alignItems: "center",
    justifyContent: "center",
    gap: 9,
    textAlign: "center",
    marginBottom: 36,
}));

const StopDownloadButtonsSection = styled(Box)(() => ({
    width: "100%",
    display: "flex",
    flexDirection: "column",
    gap: 12,
}));

const StopDownloadSubtitle = styled(Typography)(({ theme }) => ({
    fontWeight: 500,
    fontSize: 14,
    lineHeight: "20px",
    color: "#666666",
    maxWidth: 295,
    textAlign: "center",
    marginInline: "auto",
    ...theme.applyStyles("dark", { color: "rgba(255, 255, 255, 0.7)" }),
}));

const StopDownloadSecondaryButton = styled(Button)(({ theme }) => ({
    display: "flex",
    padding: "20px 16px",
    justifyContent: "center",
    alignItems: "center",
    gap: 8,
    borderRadius: 20,
    backgroundColor: "rgba(0, 0, 0, 0.04)",
    border: "none",
    fontSize: 16,
    fontWeight: 500,
    textTransform: "none",
    color: "#000",
    "&:hover": { backgroundColor: "rgba(0, 0, 0, 0.08)", border: "none" },
    ...theme.applyStyles("dark", {
        backgroundColor: "rgba(255, 255, 255, 0.08)",
        color: "#fff",
        "&:hover": { backgroundColor: "rgba(255, 255, 255, 0.12)" },
    }),
}));

const StopDownloadPrimaryButton = styled(Button)(({ theme }) => ({
    display: "flex",
    padding: "20px 16px",
    justifyContent: "center",
    alignItems: "center",
    gap: 8,
    borderRadius: 20,
    backgroundColor: theme.vars.palette.critical.main,
    fontSize: 16,
    fontWeight: 500,
    textTransform: "none",
    color: theme.vars.palette.critical.contrastText,
    "&:hover": { backgroundColor: theme.vars.palette.critical.dark },
}));

const spinAnimation = keyframes`
    from { transform: rotate(0deg); }
    to { transform: rotate(360deg); }
`;

const dropAnimation = keyframes`
    0% { transform: translateY(-100%); opacity: 0.15; }
    50% { transform: translateY(10%); opacity: 0.6; }
    100% { transform: translateY(0); opacity: 1; }
`;

const glowAnimation = keyframes`
    0% { color: var(--mui-palette-fixed-success); }
    100% { color: inherit; }
`;

const fadeInAnimation = keyframes`
    0% { opacity: 0; }
    100% { opacity: 1; }
`;

const DroppingIconWrapper = styled("span")`
    display: inline-flex;
    animation: ${dropAnimation} 0.8s ease-out forwards;
`;

const GlowingIconWrapper = styled("span")`
    display: inline-flex;
    animation: ${glowAnimation} 2s ease-out forwards;
`;

const SpinningIconWrapper = styled("span")`
    display: inline-flex;
    animation:
        ${fadeInAnimation} 0.5s ease-out forwards,
        ${spinAnimation} 3s linear infinite;
`;

const SpinningIcon: React.FC = () => (
    <SpinningIconWrapper>
        <HugeiconsIcon icon={Loading03Icon} size={28} />
    </SpinningIconWrapper>
);
