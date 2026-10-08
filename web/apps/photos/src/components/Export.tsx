import exportService, {
    ExportStage,
    isExportFolderMissingError,
    selectAndPrepareExportDirectory,
    type ExportOpts,
    type ExportProgress,
} from "@/services/export";
import {
    Box,
    Divider,
    LinearProgress,
    Stack,
    Tooltip,
    Typography,
} from "@mui/material";
import { isDesktop } from "ente-base/app";
import { EnteSwitch } from "ente-base/components/EnteSwitch";
import { LinkButton } from "ente-base/components/LinkButton";
import { TitledMiniDialog } from "ente-base/components/MiniDialog";
import { EllipsizedTypography } from "ente-base/components/Typography";
import { SpacedRow } from "ente-base/components/containers";
import { FocusVisibleButton } from "ente-base/components/mui/FocusVisibleButton";
import {
    TitledNestedSidebarDrawer,
    type NestedSidebarDrawerVisibilityProps,
} from "ente-base/components/mui/SidebarDrawer";
import {
    useModalVisibility,
    type ModalVisibilityProps,
} from "ente-base/components/utils/modal";
import { RowCard } from "ente-base/components/v2/RowCard";
import { useBaseContext } from "ente-base/context";
import { ensureElectron } from "ente-base/electron";
import { formattedNumber, ut } from "ente-base/i18n";
import { formattedDateRelative, formattedDateTime } from "ente-base/i18n-date";
import log from "ente-base/log";
import type { EnteFile } from "ente-media/file";
import { fileFileName } from "ente-media/file-metadata";
import { ItemCard, PreviewItemTile } from "ente-new/photos/components/Tiles";
import { t } from "i18next";
import React, { memo, useCallback, useEffect, useState } from "react";
import { Trans } from "react-i18next";
import {
    areEqual,
    FixedSizeList,
    type ListChildComponentProps,
    type ListItemKeySelector,
} from "react-window";

type ExportProps = NestedSidebarDrawerVisibilityProps & {
    collectionNameByID: Map<number, string>;
};

export const Export: React.FC<ExportProps> = ({
    open,
    onClose,
    onRootClose,
    collectionNameByID,
}) => {
    const { showMiniDialog } = useBaseContext();
    const [exportStage, setExportStage] = useState<ExportStage>(
        ExportStage.init,
    );
    const [exportFolder, setExportFolder] = useState("");
    const [continuousExport, setContinuousExport] = useState(false);
    const [exportProgress, setExportProgress] = useState<ExportProgress>({
        success: 0,
        failed: 0,
        total: 0,
    });
    const [pendingFiles, setPendingFiles] = useState<EnteFile[]>([]);
    const [lastExportTime, setLastExportTime] = useState<number | null>(0);

    const syncExportRecord = useCallback(
        async (exportFolder: string | undefined) => {
            try {
                if (!(await exportService.exportFolderExists(exportFolder))) {
                    setPendingFiles(await exportService.pendingFiles());
                }
                const exportRecord =
                    await exportService.getExportRecord(exportFolder);
                const currentStage = exportService.getCurrentExportStage();
                const isRunning = Boolean(exportService.isExportInProgress());
                const effectiveStage =
                    isRunning && currentStage !== ExportStage.init
                        ? currentStage
                        : exportRecord.stage;
                setExportStage(effectiveStage);
                setLastExportTime(exportRecord.lastAttemptTimestamp);
                setPendingFiles(await exportService.pendingFiles(exportRecord));
            } catch (e) {
                if (!isExportFolderMissingError(e)) {
                    log.error("syncExportRecord failed", e);
                }
            }
        },
        [],
    );

    useEffect(() => {
        if (!isDesktop) return;

        exportService.setUIUpdaters({
            setExportStage,
            setExportProgress,
            setLastExportTime,
            setPendingFiles,
        });
        const exportSettings = exportService.getExportSettings();
        setExportFolder(exportSettings?.folder ?? "");
        setContinuousExport(exportSettings?.continuousExport ?? false);
        void syncExportRecord(exportSettings?.folder);
    }, [syncExportRecord]);

    useEffect(() => {
        if (!open) return;
        void syncExportRecord(exportFolder);
    }, [open, exportFolder, syncExportRecord]);

    const verifyExportFolderExists = useCallback(async () => {
        if (!(await exportService.exportFolderExists(exportFolder))) {
            showMiniDialog({
                title: t("export_directory_does_not_exist"),
                message: (
                    <Trans
                        i18nKey={"export_directory_does_not_exist_message"}
                    />
                ),
                cancel: t("ok"),
            });
            return false;
        }
        return true;
    }, [exportFolder, showMiniDialog]);

    const handleChangeExportDirectory = useCallback(() => {
        void (async () => {
            const newFolder = await selectAndPrepareExportDirectory();
            if (!newFolder) return;

            log.info(`Export folder changed to ${newFolder}`);
            exportService.updateExportSettings({ folder: newFolder });
            setExportFolder(newFolder);
            await syncExportRecord(newFolder);
        })();
    }, [syncExportRecord]);

    const handleToggleContinuousExport = useCallback(() => {
        void (async () => {
            if (!(await verifyExportFolderExists())) return;

            const newContinuousExport = !continuousExport;
            if (newContinuousExport) {
                exportService.enableContinuousExport();
            } else {
                exportService.disableContinuousExport();
            }
            exportService.updateExportSettings({
                continuousExport: newContinuousExport,
            });
            setContinuousExport(newContinuousExport);
        })();
    }, [verifyExportFolderExists, continuousExport]);

    const handleStartExport = useCallback(
        (opts?: ExportOpts) => {
            void (async () => {
                if (!(await verifyExportFolderExists())) return;

                await exportService.scheduleExport(opts ?? {});
            })();
        },
        [verifyExportFolderExists],
    );

    const handleResyncExport = useCallback(() => {
        handleStartExport({ resync: true });
    }, [handleStartExport]);

    const handleStopExport = useCallback(() => {
        void exportService.stopRunningExport();
    }, []);

    const handleRootClose = () => {
        onClose();
        onRootClose();
    };

    const percentComplete = exportProgress.total
        ? Math.round(
              ((exportProgress.success + exportProgress.failed) * 100) /
                  exportProgress.total,
          )
        : 0;

    return (
        <TitledNestedSidebarDrawer
            {...{ open, onClose }}
            onRootClose={handleRootClose}
            maxWidth="440px"
            title={t("export_data")}
        >
            <Typography sx={{ px: 3, pb: 2, color: "text.muted" }}>
                {ut("Keep a decrypted copy of your library on this computer.")}
            </Typography>
            <Box sx={{ px: 2, py: 1 }}>
                <Stack sx={{ gap: 2 }}>
                    <ExportDirectory
                        exportStage={exportStage}
                        exportFolder={exportFolder}
                        onChangeExportDirectory={handleChangeExportDirectory}
                    />
                    <ContinuousExport
                        enabled={continuousExport}
                        onToggle={handleToggleContinuousExport}
                    />
                </Stack>
            </Box>
            <Divider sx={{ mx: 2, my: 1 }} />
            <SpacedRow sx={{ px: 2, pt: 2, gap: 2 }}>
                <Typography variant="small" sx={{ color: "text.muted" }}>
                    {t("last_export_time")}
                    {": "}
                    {lastExportTime ? (
                        <Tooltip
                            title={formattedDateTime(new Date(lastExportTime))}
                        >
                            <span>
                                {formattedDateRelative(
                                    new Date(lastExportTime),
                                )}
                            </span>
                        </Tooltip>
                    ) : (
                        t("never")
                    )}
                </Typography>
                {exportStage === ExportStage.exportingFiles && (
                    <Typography
                        variant="small"
                        sx={{ color: "text.muted", flexShrink: 0 }}
                    >
                        {t("percent_complete", { percent: percentComplete })}
                    </Typography>
                )}
            </SpacedRow>
            <ExportDialogStageContent
                {...{
                    exportStage,
                    exportProgress,
                    percentComplete,
                    pendingFiles,
                    collectionNameByID,
                    onClose,
                }}
                onStartExport={handleStartExport}
                onResyncExport={handleResyncExport}
                onStopExport={handleStopExport}
            />
        </TitledNestedSidebarDrawer>
    );
};

interface ExportDirectoryProps {
    exportStage: ExportStage;
    exportFolder: string;
    onChangeExportDirectory: () => void;
}

const ExportDirectory: React.FC<ExportDirectoryProps> = ({
    exportStage,
    exportFolder,
    onChangeExportDirectory,
}) => (
    <Stack
        direction={exportFolder ? "column" : "row"}
        sx={{
            p: 2,
            gap: 1,
            bgcolor: "fill.faint",
            borderRadius: "20px",
            alignItems: exportFolder ? "stretch" : "center",
            justifyContent: "space-between",
        }}
    >
        <Typography variant="small" sx={{ color: "text.muted" }}>
            {ut("Export folder")}
        </Typography>
        <Stack
            direction="row"
            sx={{
                gap: 1,
                alignItems: "center",
                justifyContent: "space-between",
            }}
        >
            {exportFolder && <DirectoryPath path={exportFolder} />}
            <FocusVisibleButton
                color="secondary"
                onClick={onChangeExportDirectory}
                disabled={
                    Boolean(exportFolder) &&
                    exportStage !== ExportStage.finished &&
                    exportStage !== ExportStage.init
                }
                sx={{ flexShrink: 0, px: 2, borderRadius: "12px" }}
            >
                {exportFolder ? t("change_folder") : t("select_folder")}
            </FocusVisibleButton>
        </Stack>
    </Stack>
);

interface DirectoryPathProps {
    path: string;
}

const DirectoryPath: React.FC<DirectoryPathProps> = ({ path }) => (
    <Box
        sx={{
            minWidth: 0,
            "& button": { maxWidth: "100%", textAlign: "left" },
        }}
    >
        <LinkButton onClick={() => void ensureElectron().openDirectory(path)}>
            <Tooltip title={path}>
                <EllipsizedTypography
                    sx={{ maxWidth: "100%", fontFamily: "monospace" }}
                >
                    {path}
                </EllipsizedTypography>
            </Tooltip>
        </LinkButton>
    </Box>
);

interface ContinuousExportProps {
    enabled: boolean;
    onToggle: () => void;
}

const ContinuousExport: React.FC<ContinuousExportProps> = ({
    enabled,
    onToggle,
}) => (
    <SpacedRow sx={{ gap: 2, px: 1, py: 1 }}>
        <Stack sx={{ gap: 0.5 }}>
            <Typography>{ut("Continuous export")}</Typography>
            <Typography variant="small" sx={{ color: "text.muted" }}>
                {ut("Automatically export new photos as they sync")}
            </Typography>
        </Stack>
        <EnteSwitch
            color="accent"
            checked={enabled}
            onChange={onToggle}
            slotProps={{ input: { "aria-label": ut("Continuous export") } }}
            sx={{ flexShrink: 0 }}
        />
    </SpacedRow>
);

type ExportDialogStageContentProps = ExportInitDialogContentProps &
    ExportInProgressDialogContentProps &
    ExportFinishedDialogContentProps;

const ExportDialogStageContent: React.FC<ExportDialogStageContentProps> = ({
    exportStage,
    exportProgress,
    percentComplete,
    pendingFiles,
    collectionNameByID,
    onClose,
    onStartExport,
    onStopExport,
    onResyncExport,
}) => {
    switch (exportStage) {
        case ExportStage.init:
            return <ExportInitDialogContent {...{ onStartExport }} />;

        case ExportStage.migration:
        case ExportStage.starting:
        case ExportStage.exportingFiles:
        case ExportStage.renamingCollectionFolders:
        case ExportStage.trashingDeletedFiles:
        case ExportStage.trashingDeletedCollections:
            return (
                <ExportInProgressDialogContent
                    {...{
                        exportStage,
                        exportProgress,
                        percentComplete,
                        onClose,
                        onStopExport,
                    }}
                />
            );
        case ExportStage.finished:
            return (
                <ExportFinishedDialogContent
                    {...{
                        pendingFiles,
                        collectionNameByID,
                        onClose,
                        onResyncExport,
                    }}
                />
            );

        default:
            return <></>;
    }
};

interface ExportInitDialogContentProps {
    onStartExport: () => void;
}

const ExportInitDialogContent: React.FC<ExportInitDialogContentProps> = ({
    onStartExport,
}) => (
    <Stack direction="row" sx={{ px: 2, py: 1, gap: 1 }}>
        <FocusVisibleButton fullWidth color="accent" onClick={onStartExport}>
            {ut("Start export")}
        </FocusVisibleButton>
    </Stack>
);

interface ExportInProgressDialogContentProps {
    percentComplete: number;
    exportStage: ExportStage;
    exportProgress: ExportProgress;
    onClose: () => void;
    onStopExport: () => void;
}

const ExportInProgressDialogContent: React.FC<
    ExportInProgressDialogContentProps
> = ({
    exportStage,
    exportProgress,
    percentComplete,
    onClose,
    onStopExport,
}) => {
    return (
        <>
            <Box sx={{ px: 2, py: 1 }}>
                <Stack sx={{ gap: 1, mb: 1 }}>
                    <Box>
                        {exportStage === ExportStage.exportingFiles ? (
                            <LinearProgress
                                variant="determinate"
                                value={percentComplete}
                                sx={{
                                    height: 6,
                                    borderRadius: 3,
                                    bgcolor: "fill.faint",
                                    "& .MuiLinearProgress-bar": {
                                        bgcolor: "accent.main",
                                    },
                                }}
                            />
                        ) : (
                            <LinearProgress
                                sx={{
                                    height: 6,
                                    borderRadius: 3,
                                    bgcolor: "fill.faint",
                                    "& .MuiLinearProgress-bar": {
                                        bgcolor: "accent.main",
                                    },
                                }}
                            />
                        )}
                    </Box>
                    <Typography variant="small" sx={{ color: "text.muted" }}>
                        {exportStage === ExportStage.starting ? (
                            t("export_starting")
                        ) : exportStage === ExportStage.migration ? (
                            t("export_preparing")
                        ) : exportStage ===
                          ExportStage.renamingCollectionFolders ? (
                            t("export_renaming_album_folders")
                        ) : exportStage === ExportStage.trashingDeletedFiles ? (
                            t("export_trashing_deleted_files")
                        ) : exportStage ===
                          ExportStage.trashingDeletedCollections ? (
                            t("export_trashing_deleted_albums")
                        ) : (
                            <Trans
                                i18nKey={"export_progress"}
                                components={{ a: <span /> }}
                                values={{ progress: exportProgress }}
                            />
                        )}
                    </Typography>
                </Stack>
            </Box>
            <Stack direction="row" sx={{ px: 2, py: 1, gap: 1 }}>
                <FocusVisibleButton
                    fullWidth
                    color="secondary"
                    onClick={onClose}
                >
                    {t("close")}
                </FocusVisibleButton>
                <FocusVisibleButton
                    fullWidth
                    color="critical"
                    onClick={onStopExport}
                >
                    {t("stop")}
                </FocusVisibleButton>
            </Stack>
        </>
    );
};

interface ExportFinishedDialogContentProps {
    pendingFiles: EnteFile[];
    collectionNameByID: Map<number, string>;
    onClose: () => void;
    onResyncExport: () => void;
}

const ExportFinishedDialogContent: React.FC<
    ExportFinishedDialogContentProps
> = ({ pendingFiles, collectionNameByID, onClose, onResyncExport }) => {
    const { show: showPendingList, props: pendingListVisibilityProps } =
        useModalVisibility();

    return (
        <>
            <Box sx={{ px: 2, py: 1 }}>
                <RowCard
                    title={
                        <Typography
                            component="span"
                            variant="small"
                            sx={{ color: "text.muted" }}
                        >
                            {t("pending_items")}
                        </Typography>
                    }
                    onClick={pendingFiles.length ? showPendingList : undefined}
                    endIcon={
                        <Typography
                            variant="small"
                            sx={{ color: "text.muted" }}
                        >
                            {formattedNumber(pendingFiles.length)}
                        </Typography>
                    }
                />
            </Box>
            <Stack direction="row" sx={{ px: 2, py: 1, gap: 1 }}>
                <FocusVisibleButton
                    fullWidth
                    color="secondary"
                    onClick={onClose}
                >
                    {t("close")}
                </FocusVisibleButton>
                <FocusVisibleButton fullWidth onClick={onResyncExport}>
                    {t("export_again")}
                </FocusVisibleButton>
            </Stack>
            <ExportPendingListDialog
                {...pendingListVisibilityProps}
                pendingFiles={pendingFiles}
                collectionNameByID={collectionNameByID}
            />
        </>
    );
};

type ExportPendingListDialogProps = ModalVisibilityProps &
    ExportPendingListItemData;

const ExportPendingListDialog: React.FC<ExportPendingListDialogProps> = ({
    open,
    onClose,
    collectionNameByID,
    pendingFiles,
}) => {
    const itemSize = 56;
    const itemCount = pendingFiles.length;
    const listHeight = Math.min(itemCount * itemSize, 240);

    const itemKey: ListItemKeySelector<ExportPendingListItemData> = (
        index,
        { pendingFiles },
    ) => {
        const file = pendingFiles[index]!;
        return `${file.collectionID}/${file.id}`;
    };

    return (
        <TitledMiniDialog
            {...{ open, onClose }}
            paperMaxWidth="444px"
            title={t("pending_items")}
        >
            <FixedSizeList
                itemData={{ collectionNameByID, pendingFiles }}
                height={listHeight}
                width="100%"
                {...{ itemSize, itemCount, itemKey }}
            >
                {ExportPendingListItem}
            </FixedSizeList>
            <FocusVisibleButton
                fullWidth
                color="secondary"
                onClick={onClose}
                sx={{ mt: 2 }}
            >
                {t("close")}
            </FocusVisibleButton>
        </TitledMiniDialog>
    );
};

interface ExportPendingListItemData {
    pendingFiles: EnteFile[];
    collectionNameByID: Map<number, string>;
}

const ExportPendingListItem: React.FC<
    ListChildComponentProps<ExportPendingListItemData>
> = memo(({ index, style, data }) => {
    const { pendingFiles, collectionNameByID } = data;
    const file = pendingFiles[index]!;

    const fileName = fileFileName(file);
    const collectionName = collectionNameByID.get(file.collectionID);

    return (
        <div style={style}>
            <Stack direction="row" sx={{ gap: 1 }}>
                <Box sx={{ flexShrink: 0 }}>
                    <ItemCard
                        key={file.id}
                        TileComponent={PreviewItemTile}
                        coverFile={file}
                    />
                </Box>
                <Stack
                    sx={{
                        // EllipsizedTypography needs overflow hidden on its container.
                        overflow: "hidden",
                        gap: "2px",
                    }}
                >
                    <Tooltip title={fileName}>
                        <EllipsizedTypography>{fileName}</EllipsizedTypography>
                    </Tooltip>
                    <Typography sx={{ color: "text.muted" }} variant="small">
                        {collectionName}
                    </Typography>
                </Stack>
            </Stack>
        </div>
    );
}, areEqual);
