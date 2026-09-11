import {
    lockerColorSx,
    lockerShadowFloating,
    lockerTextBodyBoldSx,
    lockerTextBodySx,
} from "@/styles/tokens";
import { Delete02Icon, Download01Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import ClearRoundedIcon from "@mui/icons-material/ClearRounded";
import { Box, Button, IconButton, Stack, Typography } from "@mui/material";
import { t } from "i18next";
import React from "react";

export const SelectionActionBar: React.FC<{
    selectedCount: number;
    allSelected: boolean;
    bulkDownloading: boolean;
    bulkDownloadProgress: { completed: number; total: number } | null;
    canDownload: boolean;
    canDelete: boolean;
    onToggleSelectAll: () => void;
    onDownload: () => void;
    onDelete: () => void;
    onDone: () => void;
}> = ({
    selectedCount,
    allSelected,
    bulkDownloading,
    bulkDownloadProgress,
    canDownload,
    canDelete,
    onToggleSelectAll,
    onDownload,
    onDelete,
    onDone,
}) => (
    <Box sx={{ px: { xs: 2, sm: 3 }, py: 1.5 }}>
        <Stack
            direction={{ xs: "column", sm: "row" }}
            sx={(theme) => ({
                maxWidth: 760,
                mx: "auto",
                p: 1.5,
                gap: 1.5,
                alignItems: { xs: "stretch", sm: "center" },
                borderRadius: "24px",
                boxShadow: lockerShadowFloating,
                ...lockerColorSx(theme, {
                    backgroundColor: "fillLight",
                    color: "textBase",
                }),
            })}
        >
            <Stack
                direction="row"
                sx={{ alignItems: "center", gap: 1, flex: 1, minWidth: 0 }}
            >
                <IconButton
                    aria-label={t("close")}
                    onClick={onDone}
                    disabled={bulkDownloading}
                    sx={(theme) => ({
                        width: 40,
                        height: 40,
                        flexShrink: 0,
                        ...lockerColorSx(theme, { color: "textLight" }),
                    })}
                >
                    <ClearRoundedIcon sx={{ fontSize: 20 }} />
                </IconButton>
                <Typography
                    sx={{ ...lockerTextBodyBoldSx, flex: 1, minWidth: 0 }}
                    aria-live="polite"
                >
                    {t("selected_count", { selected: selectedCount })}
                </Typography>
                <Button
                    variant="text"
                    onClick={onToggleSelectAll}
                    disabled={bulkDownloading}
                    sx={{
                        ...lockerTextBodySx,
                        minHeight: 40,
                        px: 1.5,
                        flexShrink: 0,
                    }}
                >
                    {allSelected ? t("deselect_all") : t("select_all")}
                </Button>
            </Stack>
            <Stack
                direction="row"
                sx={{
                    gap: 1,
                    "& > button": {
                        flex: { xs: 1, sm: "initial" },
                        minHeight: 44,
                        px: 2,
                        ...lockerTextBodyBoldSx,
                    },
                }}
            >
                <Button
                    variant="contained"
                    startIcon={
                        <HugeiconsIcon
                            icon={Download01Icon}
                            size={18}
                            strokeWidth={1.6}
                        />
                    }
                    onClick={onDownload}
                    disabled={bulkDownloading || !canDownload}
                >
                    {bulkDownloading && bulkDownloadProgress
                        ? `${t("downloading")} ${bulkDownloadProgress.completed}/${bulkDownloadProgress.total}`
                        : t("download")}
                </Button>
                <Button
                    variant="text"
                    color="critical"
                    startIcon={
                        <HugeiconsIcon
                            icon={Delete02Icon}
                            size={18}
                            strokeWidth={1.6}
                        />
                    }
                    onClick={onDelete}
                    disabled={bulkDownloading || !canDelete}
                    sx={(theme) => ({
                        ...lockerColorSx(theme, {
                            backgroundColor: "warningLight",
                            color: "warning",
                        }),
                        "&:hover": lockerColorSx(theme, {
                            backgroundColor: "warningLight",
                            color: "warningDark",
                        }),
                        "&.Mui-disabled": {
                            ...lockerColorSx(theme, {
                                backgroundColor: "fillDark",
                                color: "textLighter",
                            }),
                            opacity: 0.5,
                        },
                    })}
                >
                    {t("delete")}
                </Button>
            </Stack>
        </Stack>
    </Box>
);
