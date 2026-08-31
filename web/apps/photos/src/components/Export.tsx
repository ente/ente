import exportService, {
    ExportStage,
    isExportFolderMissingError,
    selectAndPrepareExportDirectory,
    type ExportOpts,
    type ExportProgress,
} from "@/services/export";
import FolderIcon from "@mui/icons-material/Folder";
import {
    Box,
    Button,
    Dialog,
    DialogActions,
    DialogContent,
    DialogTitle,
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
import {
    OverflowMenu,
    OverflowMenuOption,
} from "ente-base/components/OverflowMenu";
import { EllipsizedTypography } from "ente-base/components/Typography";
import { SpacedRow } from "ente-base/components/containers";
import type { ButtonishProps } from "ente-base/components/mui";
import { DialogCloseIconButton } from "ente-base/components/mui/DialogCloseIconButton";
import { FocusVisibleButton } from "ente-base/components/mui/FocusVisibleButton";
import {
    useModalVisibility,
    type ModalVisibilityProps,
} from "ente-base/components/utils/modal";
import { useBaseContext } from "ente-base/context";
import { ensureElectron } from "ente-base/electron";
import { formattedNumber } from "ente-base/i18n";
import { formattedDateTime } from "ente-base/i18n-date";
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

type ExportProps = ModalVisibilityProps & {
    collectionNameByID: Map<number, string>;
};

export const Export: React.FC<ExportProps> = ({
    open,
    onClose,
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

    return (
        <Dialog {...{ open, onClose }} maxWidth="xs" fullWidth>
            <SpacedRow sx={{ p: "12px 4px 0px 0px" }}>
                <DialogTitle variant="h3">{t("export_data")}</DialogTitle>
                <DialogCloseIconButton {...{ onClose }} />
            </SpacedRow>

            <DialogContent>
                <Stack>
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
            </DialogContent>
            <Divider />
            <ExportDialogStageContent
                {...{
                    exportStage,
                    exportProgress,
                    pendingFiles,
                    lastExportTime,
                    collectionNameByID,
                    onClose,
                }}
                onStartExport={handleStartExport}
                onResyncExport={handleResyncExport}
                onStopExport={handleStopExport}
            />
        </Dialog>
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
        direction="row"
        sx={{ gap: 1, justifyContent: "space-between", alignItems: "center" }}
    >
        <Typography sx={{ color: "text.muted", mr: 1 }}>
            {t("destination")}
        </Typography>
        {exportFolder ? (
            <>
                <DirectoryPath path={exportFolder} />
                {exportStage === ExportStage.finished ||
                exportStage === ExportStage.init ? (
                    <ChangeDirectoryOption onClick={onChangeExportDirectory} />
                ) : (
                    // Preserve the directory row width while its action is hidden.
                    <Box sx={{ width: "16px", height: "48px" }} />
                )}
            </>
        ) : (
            <Button color="accent" onClick={onChangeExportDirectory}>
                {t("select_folder")}
            </Button>
        )}
    </Stack>
);

interface DirectoryPathProps {
    path: string;
}

const DirectoryPath: React.FC<DirectoryPathProps> = ({ path }) => (
    <LinkButton onClick={() => void ensureElectron().openDirectory(path)}>
        <Tooltip title={path}>
            <EllipsizedTypography
                // Ellipsis needs a fixed maximum width.
                sx={{ maxWidth: "262px" }}
            >
                {path}
            </EllipsizedTypography>
        </Tooltip>
    </LinkButton>
);

const ChangeDirectoryOption: React.FC<ButtonishProps> = ({ onClick }) => (
    <OverflowMenu ariaID="export-option">
        <OverflowMenuOption onClick={onClick} startIcon={<FolderIcon />}>
            {t("change_folder")}
        </OverflowMenuOption>
    </OverflowMenu>
);

interface ContinuousExportProps {
    enabled: boolean;
    onToggle: () => void;
}

const ContinuousExport: React.FC<ContinuousExportProps> = ({
    enabled,
    onToggle,
}) => (
    <SpacedRow sx={{ minHeight: "48px", mt: 1 }}>
        <Typography sx={{ color: "text.muted" }}>
            {t("sync_continuously")}
        </Typography>
        <Box>
            <EnteSwitch color="accent" checked={enabled} onChange={onToggle} />
        </Box>
    </SpacedRow>
);

type ExportDialogStageContentProps = ExportInitDialogContentProps &
    ExportInProgressDialogContentProps &
    ExportFinishedDialogContentProps;

const ExportDialogStageContent: React.FC<ExportDialogStageContentProps> = ({
    exportStage,
    exportProgress,
    pendingFiles,
    lastExportTime,
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
                    {...{ exportStage, exportProgress, onClose, onStopExport }}
                />
            );
        case ExportStage.finished:
            return (
                <ExportFinishedDialogContent
                    {...{
                        pendingFiles,
                        lastExportTime,
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
    <DialogContent>
        <DialogActions>
            <FocusVisibleButton
                fullWidth
                color="accent"
                onClick={onStartExport}
            >
                {t("start")}
            </FocusVisibleButton>
        </DialogActions>
    </DialogContent>
);

interface ExportInProgressDialogContentProps {
    exportStage: ExportStage;
    exportProgress: ExportProgress;
    onClose: () => void;
    onStopExport: () => void;
}

const ExportInProgressDialogContent: React.FC<
    ExportInProgressDialogContentProps
> = ({ exportStage, exportProgress, onClose, onStopExport }) => (
    <>
        <DialogContent>
            <Stack sx={{ alignItems: "center", gap: 3, mt: 1 }}>
                <Typography>
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
                        <Typography
                            component="span"
                            sx={{ color: "text.muted" }}
                        >
                            <Trans
                                i18nKey={"export_progress"}
                                components={{
                                    a: (
                                        <Typography
                                            component="span"
                                            sx={{
                                                color: "text.base",
                                                pr: "1rem",
                                                wordSpacing: "1rem",
                                            }}
                                        />
                                    ),
                                }}
                                values={{ progress: exportProgress }}
                            />
                        </Typography>
                    )}
                </Typography>

                <Box sx={{ alignSelf: "stretch" }}>
                    {exportStage === ExportStage.exportingFiles ? (
                        <LinearProgress
                            variant="determinate"
                            value={Math.round(
                                ((exportProgress.success +
                                    exportProgress.failed) *
                                    100) /
                                    exportProgress.total,
                            )}
                        />
                    ) : (
                        <LinearProgress />
                    )}
                </Box>
            </Stack>
        </DialogContent>
        <DialogActions>
            <FocusVisibleButton fullWidth color="secondary" onClick={onClose}>
                {t("close")}
            </FocusVisibleButton>
            <FocusVisibleButton
                fullWidth
                color="critical"
                onClick={onStopExport}
            >
                {t("stop")}
            </FocusVisibleButton>
        </DialogActions>
    </>
);

interface ExportFinishedDialogContentProps {
    pendingFiles: EnteFile[];
    lastExportTime: number | null;
    collectionNameByID: Map<number, string>;
    onClose: () => void;
    onResyncExport: () => void;
}

const ExportFinishedDialogContent: React.FC<
    ExportFinishedDialogContentProps
> = ({
    pendingFiles,
    lastExportTime,
    collectionNameByID,
    onClose,
    onResyncExport,
}) => {
    const { show: showPendingList, props: pendingListVisibilityProps } =
        useModalVisibility();

    return (
        <>
            <DialogContent>
                <Stack sx={{ pr: 1 }}>
                    <SpacedRow sx={{ minHeight: "48px" }}>
                        <Typography sx={{ color: "text.muted" }}>
                            {t("pending_items")}
                        </Typography>
                        {pendingFiles.length ? (
                            <LinkButton onClick={showPendingList}>
                                {formattedNumber(pendingFiles.length)}
                            </LinkButton>
                        ) : (
                            <Typography>
                                {formattedNumber(pendingFiles.length)}
                            </Typography>
                        )}
                    </SpacedRow>
                    <SpacedRow sx={{ minHeight: "48px" }}>
                        <Typography sx={{ color: "text.muted" }}>
                            {t("last_export_time")}
                        </Typography>
                        <Typography>
                            {lastExportTime
                                ? formattedDateTime(new Date(lastExportTime))
                                : t("never")}
                        </Typography>
                    </SpacedRow>
                </Stack>
            </DialogContent>
            <DialogActions>
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
            </DialogActions>
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
