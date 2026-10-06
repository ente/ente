import { summarizeFreeUpSpace } from "@/services/free-up-space";
import ChevronRightIcon from "@mui/icons-material/ChevronRight";
import { Skeleton, Stack, Typography } from "@mui/material";
import { RowButton, RowButtonDivider } from "ente-base/components/RowButton";
import {
    TitledNestedSidebarDrawer,
    type NestedSidebarDrawerVisibilityProps,
} from "ente-base/components/mui/SidebarDrawer";
import { formattedNumber, ut } from "ente-base/i18n";
import log from "ente-base/log";
import { formattedByteSize } from "ente-gallery/utils/units";
import type { SidebarActionID } from "ente-new/photos/services/search/types";
import { t } from "i18next";
import { useRouter } from "next/router";
import React, { useCallback, useEffect, useState } from "react";

export type FreeUpSpaceAction = Extract<
    SidebarActionID,
    "freeUpSpace.deduplicate" | "freeUpSpace.largeFiles"
>;

type FreeUpSpaceProps = NestedSidebarDrawerVisibilityProps & {
    pendingAction?: FreeUpSpaceAction;
    onActionHandled?: (action?: FreeUpSpaceAction) => void;
};

export const FreeUpSpace: React.FC<FreeUpSpaceProps> = ({
    open,
    onClose,
    onRootClose,
    pendingAction,
    onActionHandled,
}) => {
    const router = useRouter();
    const [summary, setSummary] = useState<
        ReturnType<typeof summarizeFreeUpSpace> | undefined
    >();
    const [analysisFailed, setAnalysisFailed] = useState(false);

    useEffect(() => {
        if (!open) return;
        let cancelled = false;
        setSummary(undefined);
        setAnalysisFailed(false);
        const analyze = async () => {
            try {
                const [{ findLargeFiles }, { deduceDuplicates }] =
                    await Promise.all([
                        import("@/services/large-files"),
                        import("@/services/dedup"),
                    ]);
                const [largeFiles, duplicateGroups] = await Promise.all([
                    findLargeFiles("all"),
                    deduceDuplicates(),
                ]);
                if (!cancelled) {
                    setSummary(
                        summarizeFreeUpSpace(largeFiles, duplicateGroups),
                    );
                }
            } catch (e) {
                log.error("Failed to analyze storage cleanup", e);
                if (!cancelled) setAnalysisFailed(true);
            }
        };
        void analyze();
        return () => {
            cancelled = true;
        };
    }, [open]);

    const handleRootClose = useCallback(() => {
        onClose();
        onRootClose();
    }, [onClose, onRootClose]);

    const handleDeduplicate = useCallback(() => {
        onRootClose();
        void router.push("/duplicates");
    }, [onRootClose, router]);

    const handleLargeFiles = useCallback(() => {
        onRootClose();
        void router.push("/large-files");
    }, [onRootClose, router]);

    useEffect(() => {
        if (!open || !pendingAction) return;
        switch (pendingAction) {
            case "freeUpSpace.deduplicate":
                handleDeduplicate();
                break;
            case "freeUpSpace.largeFiles":
                handleLargeFiles();
                break;
        }
        onActionHandled?.();
    }, [
        handleDeduplicate,
        handleLargeFiles,
        open,
        onActionHandled,
        pendingAction,
    ]);

    return (
        <TitledNestedSidebarDrawer
            {...{ open, onClose }}
            onRootClose={handleRootClose}
            title={t("free_up_space")}
        >
            <Stack sx={{ px: 2, py: 1, gap: 3 }}>
                <Typography sx={{ color: "text.muted" }}>
                    {ut(
                        "Review large files and duplicates to reclaim storage.",
                    )}
                </Typography>
                <Stack
                    aria-live="polite"
                    sx={{
                        p: 2.5,
                        gap: 1,
                        borderRadius: 3,
                        bgcolor: "primary.main",
                        color: "primary.contrastText",
                    }}
                >
                    <Typography sx={{ opacity: 0.7 }}>
                        {ut("You can free up")}
                    </Typography>
                    {summary ? (
                        <Typography variant="h2" sx={{ fontWeight: 600 }}>
                            {formattedByteSize(summary.reclaimableSize, 1)}
                        </Typography>
                    ) : analysisFailed ? (
                        <Typography>{t("generic_error_retry")}</Typography>
                    ) : (
                        <Skeleton
                            width="60%"
                            height={40}
                            sx={{ bgcolor: "currentColor", opacity: 0.15 }}
                            aria-label={t("loading")}
                        />
                    )}
                </Stack>
                <Stack>
                    <RowButton
                        variant="secondary"
                        endIcon={
                            <ChevronRightIcon sx={{ color: "text.muted" }} />
                        }
                        label={
                            <Stack sx={{ gap: 0.5, textAlign: "left" }}>
                                <Typography>
                                    {t("large_files_title")}
                                </Typography>
                                <Typography
                                    variant="small"
                                    sx={{ color: "text.muted" }}
                                >
                                    {summary
                                        ? ut(
                                              `${formattedNumber(summary.largeFileCount)} ${summary.largeFileCount === 1 ? "file" : "files"} of 10 MB or more · ${formattedByteSize(summary.largeFileSize, 1)}`,
                                          )
                                        : t(
                                              analysisFailed
                                                  ? "generic_error"
                                                  : "loading",
                                          )}
                                </Typography>
                            </Stack>
                        }
                        onClick={handleLargeFiles}
                    />
                    <RowButtonDivider />
                    <RowButton
                        variant="secondary"
                        endIcon={
                            <ChevronRightIcon sx={{ color: "text.muted" }} />
                        }
                        label={
                            <Stack sx={{ gap: 0.5, textAlign: "left" }}>
                                <Typography>{ut("Duplicates")}</Typography>
                                <Typography
                                    variant="small"
                                    sx={{ color: "text.muted" }}
                                >
                                    {summary
                                        ? ut(
                                              `${formattedNumber(summary.duplicateGroupCount)} ${summary.duplicateGroupCount === 1 ? "group" : "groups"} · ${formattedByteSize(summary.duplicateSize, 1)}`,
                                          )
                                        : t(
                                              analysisFailed
                                                  ? "generic_error"
                                                  : "loading",
                                          )}
                                </Typography>
                            </Stack>
                        }
                        onClick={handleDeduplicate}
                    />
                </Stack>
            </Stack>
        </TitledNestedSidebarDrawer>
    );
};
