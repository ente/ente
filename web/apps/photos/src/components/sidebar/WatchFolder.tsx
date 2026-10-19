import { CollectionMappingChoice } from "@/components/CollectionMappingChoice";
import watcher from "@/services/watch";
import CheckIcon from "@mui/icons-material/Check";
import ChevronRightIcon from "@mui/icons-material/ChevronRight";
import RefreshIcon from "@mui/icons-material/Refresh";
import StopCircleOutlinedIcon from "@mui/icons-material/StopCircleOutlined";
import {
    Box,
    CircularProgress,
    Divider,
    IconButton,
    Stack,
    Tooltip,
    Typography,
    useTheme,
} from "@mui/material";
import {
    TitledNestedSidebarDrawer,
    type NestedSidebarDrawerVisibilityProps,
} from "ente-base/components/mui/SidebarDrawer";
import { useModalVisibility } from "ente-base/components/utils/modal";
import { RowCard } from "ente-base/components/v2/RowCard";
import { useBaseContext } from "ente-base/context";
import {
    ensureElectron,
    suppressMainWindowBlurForTrustedPrompt,
} from "ente-base/electron";
import { dirname } from "ente-base/file-name";
import log from "ente-base/log";
import type { CollectionMapping, FolderWatch } from "ente-base/types/ipc";
import { t } from "i18next";
import React, { useEffect, useRef, useState } from "react";

export const WatchFolder: React.FC<NestedSidebarDrawerVisibilityProps> = ({
    open,
    onClose,
    onRootClose,
}) => {
    const theme = useTheme();
    const [watches, setWatches] = useState<FolderWatch[] | undefined>();
    const [savedFolderPath, setSavedFolderPath] = useState<
        string | undefined
    >();
    const { show: showMappingChoice, props: mappingChoiceVisibilityProps } =
        useModalVisibility();

    const handleRootClose = () => {
        onClose();
        onRootClose();
    };

    const refreshWatches = async () => {
        const ws = await watcher.getWatches();
        setWatches(ws);
    };

    // Recheck inaccessible folders when the window regains focus.
    useEffect(() => {
        if (!open) return;

        let active = true;
        const handleFocus = () => {
            void watcher
                .getWatches()
                .then((ws) => {
                    if (active) setWatches(ws);
                })
                .catch((e: unknown) =>
                    log.error("Failed to refresh watched folders", e),
                );
        };
        handleFocus();
        window.addEventListener("focus", handleFocus);
        return () => {
            active = false;
            window.removeEventListener("focus", handleFocus);
        };
    }, [open]);

    useEffect(() => {
        const handleWatchFolderDrop = (e: DragEvent) => {
            if (!open) return;

            e.preventDefault();
            e.stopPropagation();

            for (const file of e.dataTransfer?.files ?? []) {
                void selectCollectionMappingAndAddWatchIfDirectory(file);
            }
        };

        addEventListener("drop", handleWatchFolderDrop);
        return () => {
            removeEventListener("drop", handleWatchFolderDrop);
        };
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [open]);

    const selectCollectionMappingAndAddWatchIfDirectory = async (
        file: File,
    ) => {
        const electron = ensureElectron();
        const path = electron.pathForFile(file);
        if (await electron.fs.isDir(path)) {
            await selectCollectionMappingAndAddWatch(path);
        }
    };

    const selectCollectionMappingAndAddWatch = async (path: string) => {
        const filePaths = await ensureElectron().fs.findFiles(path);
        if (areAllInSameDirectory(filePaths)) {
            await addWatch(path, "root");
        } else {
            setSavedFolderPath(path);
            showMappingChoice();
        }
    };

    const addWatch = (folderPath: string, mapping: CollectionMapping) =>
        watcher.addWatch(folderPath, mapping).then((ws) => setWatches(ws));

    const addNewWatch = async () => {
        suppressMainWindowBlurForTrustedPrompt();
        const dirPath = await ensureElectron().selectDirectory();
        if (dirPath) {
            await selectCollectionMappingAndAddWatch(dirPath);
        }
    };

    const removeWatch = async (watch: FolderWatch) =>
        watcher.removeWatch(watch.folderPath).then((ws) => setWatches(ws));

    const handleCollectionMappingSelect = (mapping: CollectionMapping) => {
        setSavedFolderPath(undefined);
        void addWatch(savedFolderPath!, mapping);
    };

    return (
        <>
            <TitledNestedSidebarDrawer
                maxWidth="440px"
                {...{ open, onClose }}
                onRootClose={handleRootClose}
                title={t("watch_folders")}
                caption="Folders on this computer that are backed up automatically whenever files change."
            >
                <Stack sx={{ px: 2, py: 1, gap: 1 }}>
                    <WatchList {...{ watches, removeWatch, refreshWatches }} />
                    <Divider sx={{ opacity: 0.4 }} />
                    <Box
                        component="button"
                        type="button"
                        onClick={addNewWatch}
                        sx={[
                            {
                                display: "flex",
                                width: "100%",
                                padding: "8px 8px 8px 0.5rem",
                                alignItems: "center",
                                justifyContent: "space-between",
                                border: 0,
                                color: "inherit",
                                font: "inherit",
                                textAlign: "left",
                                cursor: "pointer",
                                borderRadius: "10px",
                                bgcolor: "transparent",
                                "&:hover": { bgcolor: "fill.faintHover" },
                            },
                            (theme) =>
                                theme.applyStyles("dark", {
                                    "&:hover": { bgcolor: "backdrop.muted" },
                                }),
                        ]}
                    >
                        <span
                            style={{ display: "flex", flexDirection: "column" }}
                        >
                            <span
                                style={{
                                    color: theme.vars.palette.accent.main,
                                }}
                            >
                                {t("add_folder")}
                            </span>
                            <span
                                style={{
                                    fontSize: "14px",
                                    lineHeight: "20px",
                                    fontWeight: 400,
                                    color: theme.vars.palette.text.muted,
                                }}
                            >
                                Choose a folder to watch
                            </span>
                        </span>
                        <span style={{ display: "flex", padding: "8px" }}>
                            <ChevronRightIcon
                                className="ente-chevron-right"
                                sx={{ fontSize: "20px", color: "text.muted" }}
                            />
                        </span>
                    </Box>
                    <Divider sx={{ opacity: 0.4 }} />
                </Stack>
            </TitledNestedSidebarDrawer>
            <CollectionMappingChoice
                {...mappingChoiceVisibilityProps}
                onSelect={handleCollectionMappingSelect}
            />
        </>
    );
};

interface WatchListProps {
    watches: FolderWatch[] | undefined;
    removeWatch: (watch: FolderWatch) => Promise<void>;
    refreshWatches: () => Promise<void>;
}

const WatchList: React.FC<WatchListProps> = ({
    watches,
    removeWatch,
    refreshWatches,
}) =>
    watches === undefined ? (
        <Stack sx={{ alignItems: "center", py: 2 }}>
            <CircularProgress size={24} aria-label="Loading watched folders" />
        </Stack>
    ) : watches.length ? (
        <Stack sx={{ gap: 1 }}>
            {watches.map((watch) => (
                <WatchEntry
                    key={watch.folderPath}
                    watch={watch}
                    removeWatch={removeWatch}
                    onRetry={refreshWatches}
                />
            ))}
        </Stack>
    ) : (
        <NoWatches />
    );

const NoWatches: React.FC = () => (
    <Stack sx={{ p: "14px 8px 14px 0.5rem", gap: 1 }}>
        <Typography sx={{ fontWeight: "medium" }}>
            {t("no_folders_added")}
        </Typography>
        <Stack direction="row" sx={{ gap: 1, alignItems: "center" }}>
            <Check />
            <Typography
                variant="small"
                sx={{ color: "text.muted", fontWeight: 400 }}
            >
                {t("watch_folders_hint_2")}
            </Typography>
        </Stack>
        <Stack direction="row" sx={{ gap: 1, alignItems: "center" }}>
            <Check />
            <Typography
                variant="small"
                sx={{ color: "text.muted", fontWeight: 400 }}
            >
                {t("watch_folders_hint_3")}
            </Typography>
        </Stack>
    </Stack>
);

const Check: React.FC = () => (
    <CheckIcon
        sx={{ display: "inline", fontSize: "15px", color: "stroke.muted" }}
    />
);

interface WatchEntryProps {
    watch: FolderWatch;
    removeWatch: (watch: FolderWatch) => Promise<void>;
    onRetry: () => Promise<void>;
}

const WatchEntry: React.FC<WatchEntryProps> = ({
    watch,
    removeWatch,
    onRetry,
}) => {
    const { showMiniDialog } = useBaseContext();
    const [isRetrying, setIsRetrying] = useState(false);
    const isAccessible = watch.isAccessible !== false;
    const retryTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

    useEffect(() => {
        return () => {
            if (retryTimerRef.current) clearTimeout(retryTimerRef.current);
        };
    }, []);

    const confirmStopWatching = () =>
        showMiniDialog({
            title: t("stop_watching_folder_title"),
            message: `${t("stop_watching_folder_message")}\n\n${watch.folderPath}`,
            continue: {
                text: t("yes_stop"),
                color: "critical",
                action: () => removeWatch(watch),
            },
        });

    const handleRetry = async () => {
        if (isRetrying) return;
        setIsRetrying(true);
        await onRetry();
        // Keep feedback visible long enough to notice.
        retryTimerRef.current = setTimeout(() => setIsRetrying(false), 1000);
    };

    return (
        <RowCard
            title={
                <Tooltip title={watch.folderPath}>
                    <span>{`/${watch.folderPath
                        .split(/[\\/]/)
                        .filter(Boolean)
                        .slice(-2)
                        .join("/")}`}</span>
                </Tooltip>
            }
            subtitle={!isAccessible ? t("folder_not_accessible") : undefined}
            endIcon={
                <Stack
                    direction="row"
                    sx={{ alignItems: "center", flexShrink: 0 }}
                >
                    {!isAccessible && (
                        <Tooltip title={t("retry_watching")}>
                            <IconButton
                                aria-label={`${t("retry_watching")}: ${watch.folderPath}`}
                                onClick={handleRetry}
                                disabled={isRetrying}
                            >
                                {isRetrying ? (
                                    <CircularProgress size={20} />
                                ) : (
                                    <RefreshIcon />
                                )}
                            </IconButton>
                        </Tooltip>
                    )}
                    <Tooltip title={t("stop_watching")}>
                        <IconButton
                            aria-label={`${t("stop_watching")}: ${watch.folderPath}`}
                            onClick={confirmStopWatching}
                        >
                            <StopCircleOutlinedIcon />
                        </IconButton>
                    </Tooltip>
                </Stack>
            }
        />
    );
};

const areAllInSameDirectory = (paths: string[]) =>
    new Set(paths.map(dirname)).size == 1;
