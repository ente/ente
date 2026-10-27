import { CollectionMappingChoice } from "@/components/CollectionMappingChoice";
import watcher from "@/services/watch";
import { Add01Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
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
} from "@mui/material";
import { FocusVisibleButton } from "ente-base/components/mui/FocusVisibleButton";
import {
    NestedSidebarDrawer,
    SidebarDrawerTitlebar,
    type NestedSidebarDrawerVisibilityProps,
} from "ente-base/components/mui/SidebarDrawer";
import { SidebarPanelContext } from "ente-base/components/mui/SidebarDrawerContext";
import { useModalVisibility } from "ente-base/components/utils/modal";
import { RowCard } from "ente-base/components/v2/RowCard";
import { useBaseContext } from "ente-base/context";
import {
    ensureElectron,
    suppressMainWindowBlurForTrustedPrompt,
} from "ente-base/electron";
import { dirname } from "ente-base/file-name";
import { ut } from "ente-base/i18n";
import log from "ente-base/log";
import type { CollectionMapping, FolderWatch } from "ente-base/types/ipc";
import { t } from "i18next";
import React, { useContext, useEffect, useRef, useState } from "react";

export const WatchFolder: React.FC<NestedSidebarDrawerVisibilityProps> = ({
    open,
    onClose,
    onRootClose,
}) => {
    const inSettingsPanel = !!useContext(SidebarPanelContext);
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
            <NestedSidebarDrawer
                maxWidth="440px"
                {...{ open, onClose }}
                onRootClose={handleRootClose}
            >
                {!inSettingsPanel && (
                    <SidebarDrawerTitlebar
                        title={t("watch_folders")}
                        onClose={onClose}
                        onRootClose={handleRootClose}
                        titleInline
                    />
                )}
                <Stack sx={{ p: { xs: 2, sm: 3.5 }, gap: 2.5 }}>
                    {inSettingsPanel && (
                        <Typography variant="h3">
                            {t("watch_folders")}
                        </Typography>
                    )}
                    {watches?.length === 0 ? (
                        <NoWatches onChooseFolder={addNewWatch} />
                    ) : (
                        <Stack sx={{ gap: 1 }}>
                            <WatchList
                                {...{ watches, removeWatch, refreshWatches }}
                            />
                            <Divider sx={{ opacity: 0.4 }} />
                            <RowCard
                                title={
                                    <Box
                                        component="span"
                                        sx={{ color: "accent.main" }}
                                    >
                                        {t("add_folder")}
                                    </Box>
                                }
                                subtitle={ut("Choose a folder to watch")}
                                onClick={addNewWatch}
                            />
                            <Divider sx={{ opacity: 0.4 }} />
                        </Stack>
                    )}
                </Stack>
            </NestedSidebarDrawer>
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
    ) : (
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
    );

const NoWatches: React.FC<{ onChooseFolder: () => void }> = ({
    onChooseFolder,
}) => (
    <Stack sx={{ pt: 12, gap: 2, alignItems: "center", textAlign: "center" }}>
        <Box
            component="img"
            src="/images/empty-state/no-matches.svg"
            alt=""
            draggable={false}
            sx={{ width: 104.4, height: "auto", flexShrink: 0 }}
        />
        <Typography sx={{ fontSize: 18, lineHeight: "26px", fontWeight: 600 }}>
            {ut("Nothing watched yet")}
        </Typography>
        <Typography
            sx={{
                maxWidth: 360,
                fontSize: 13,
                lineHeight: "19px",
                color: "text.muted",
            }}
        >
            {ut(
                "Point ente at a folder and everything inside it backs up and keeps backing up as you add to it.",
            )}
        </Typography>
        <FocusVisibleButton
            color="accent"
            onClick={onChooseFolder}
            startIcon={
                <HugeiconsIcon icon={Add01Icon} size={24} strokeWidth={1.5} />
            }
            sx={{
                height: 52,
                px: 3,
                borderRadius: 2.5,
                lineHeight: "20px",
                "& .MuiButton-startIcon": { m: 0, mr: 1 },
            }}
        >
            {ut("Choose a folder")}
        </FocusVisibleButton>
    </Stack>
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
