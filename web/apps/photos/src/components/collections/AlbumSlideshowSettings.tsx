import CheckIcon from "@mui/icons-material/Check";
import CloseIcon from "@mui/icons-material/Close";
import {
    Box,
    ButtonBase,
    Dialog,
    IconButton,
    Stack,
    Typography,
} from "@mui/material";
import { t } from "i18next";
import type { PropsWithChildren } from "react";
import {
    slideshowDurationOptions,
    type SlideshowSettings,
} from "./album-slideshow";

interface AlbumSlideshowSettingsProps {
    open: boolean;
    onClose: () => void;
    settings: SlideshowSettings;
    onChange: (settings: SlideshowSettings) => void;
}

export function AlbumSlideshowSettings({
    open,
    onClose,
    settings,
    onChange,
}: AlbumSlideshowSettingsProps) {
    return (
        <Dialog
            open={open}
            onClose={onClose}
            aria-labelledby="slideshow-settings-title"
            maxWidth={false}
            sx={{ "& .MuiBackdrop-root": { bgcolor: "#0008" } }}
            slotProps={{
                container: {
                    sx: { alignItems: { xs: "flex-end", sm: "center" } },
                },
                paper: {
                    sx: {
                        m: { xs: 0, sm: "20px" },
                        p: "20px",
                        pb: "max(20px, env(safe-area-inset-bottom))",
                        width: { xs: "100%", sm: 440 },
                        maxWidth: { xs: "100%", sm: "calc(100% - 40px)" },
                        maxHeight: "80dvh",
                        borderRadius: { xs: "20px 20px 0 0", sm: "24px" },
                        bgcolor: "#161616",
                        color: "#fff",
                        backgroundImage: "none",
                    },
                },
            }}
        >
            <Stack
                direction="row"
                sx={{ alignItems: "center", gap: "12px", mb: "16px" }}
            >
                <Typography
                    id="slideshow-settings-title"
                    component="h2"
                    sx={{
                        flex: 1,
                        fontSize: 18,
                        lineHeight: "24px",
                        fontWeight: 600,
                    }}
                >
                    {t("slideshow_settings")}
                </Typography>
                <IconButton
                    aria-label={t("close")}
                    onClick={onClose}
                    color="inherit"
                    sx={{ width: 38, height: 38, bgcolor: "#212121" }}
                >
                    <CloseIcon sx={{ fontSize: 20 }} />
                </IconButton>
            </Stack>
            <Stack sx={{ gap: "20px" }}>
                <SettingsOptions title={t("time_per_photo")}>
                    {slideshowDurationOptions.map((seconds) => (
                        <SettingsChip
                            key={seconds}
                            label={
                                seconds < 60
                                    ? t("seconds_count_short", {
                                          count: seconds,
                                      })
                                    : t("minutes_count_short", {
                                          count: seconds / 60,
                                      })
                            }
                            selected={settings.durationSeconds === seconds}
                            onClick={() =>
                                onChange({
                                    ...settings,
                                    durationSeconds: seconds,
                                })
                            }
                        />
                    ))}
                </SettingsOptions>
                <SettingsOptions title={t("photo_order")}>
                    <SettingsChip
                        label={t("in_order")}
                        selected={!settings.randomOrder}
                        onClick={() =>
                            onChange({ ...settings, randomOrder: false })
                        }
                    />
                    <SettingsChip
                        label={t("shuffle")}
                        selected={settings.randomOrder}
                        onClick={() =>
                            onChange({ ...settings, randomOrder: true })
                        }
                    />
                </SettingsOptions>
                <SettingsOptions title={t("background")}>
                    <SettingsChip
                        label={t("blurred")}
                        selected={settings.blurredBackground}
                        onClick={() =>
                            onChange({ ...settings, blurredBackground: true })
                        }
                    />
                    <SettingsChip
                        label={t("black")}
                        selected={!settings.blurredBackground}
                        onClick={() =>
                            onChange({ ...settings, blurredBackground: false })
                        }
                    />
                </SettingsOptions>
            </Stack>
        </Dialog>
    );
}

function SettingsOptions({
    title,
    children,
}: PropsWithChildren<{ title: string }>) {
    return (
        <Box component="fieldset" sx={{ m: 0, p: 0, border: 0, minWidth: 0 }}>
            <Typography
                component="legend"
                sx={{
                    mb: "8px",
                    p: 0,
                    fontSize: 14,
                    lineHeight: "20px",
                    fontWeight: 600,
                }}
            >
                {title}
            </Typography>
            <Stack
                direction="row"
                useFlexGap
                sx={{ flexWrap: "wrap", gap: "12px 8px" }}
            >
                {children}
            </Stack>
        </Box>
    );
}

function SettingsChip({
    label,
    selected,
    onClick,
}: {
    label: string;
    selected: boolean;
    onClick: () => void;
}) {
    return (
        <ButtonBase
            aria-pressed={selected}
            onClick={selected ? undefined : onClick}
            sx={{
                minHeight: 40,
                minWidth: 40,
                p: selected ? "12px 12px 12px 16px" : "12px 18px",
                gap: "8px",
                borderRadius: "20px",
                bgcolor: selected ? "#f4f4f4" : "#212121",
                color: selected ? "#000" : "#999",
                fontSize: 12,
                lineHeight: "16px",
                fontWeight: 500,
                "&:hover": { bgcolor: selected ? "#fff" : "#2a2a2a" },
                "&.Mui-focusVisible": {
                    outline: "2px solid currentColor",
                    outlineOffset: 3,
                },
            }}
        >
            {label}
            {selected && <CheckIcon sx={{ fontSize: 18 }} />}
        </ButtonBase>
    );
}
