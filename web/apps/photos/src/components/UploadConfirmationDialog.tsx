import {
    Cancel01Icon,
    StarIcon,
    Tick02Icon,
    UserMultipleIcon,
} from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import {
    Box,
    Dialog,
    IconButton,
    Stack,
    Typography,
    type Theme,
} from "@mui/material";
import { EnteSwitch } from "ente-base/components/EnteSwitch";
import { FocusVisibleButton } from "ente-base/components/mui/FocusVisibleButton";
import { t } from "i18next";
import type { ChangeEvent, ReactElement } from "react";

interface UploadConfirmationDialogProps {
    open: boolean;
    /**
     * `true` if the items being uploaded were detected to be a Google Takeout
     * import (Takeout metadata JSONs were found amongst them).
     */
    isTakeout: boolean;
    fileCount: number;
    albumCount: number;
    importFavorites: boolean;
    onImportFavoritesChange: (
        event: ChangeEvent<HTMLInputElement>,
        checked: boolean,
    ) => void;
    includePartnerSharedFiles: boolean;
    onIncludePartnerSharedFilesChange: (
        event: ChangeEvent<HTMLInputElement>,
        checked: boolean,
    ) => void;
    onConfirm: () => void;
    onCancel: () => void;
}

export function UploadConfirmationDialog({
    open,
    isTakeout,
    fileCount,
    albumCount,
    importFavorites,
    onImportFavoritesChange,
    includePartnerSharedFiles,
    onIncludePartnerSharedFilesChange,
    onConfirm,
    onCancel,
}: UploadConfirmationDialogProps): ReactElement {
    return (
        <Dialog
            open={open}
            onClose={onCancel}
            maxWidth={false}
            aria-labelledby="upload-confirmation-title"
            slotProps={{ paper: { sx: paperSx } }}
        >
            <Stack sx={contentSx}>
                <Stack direction="row" sx={headerSx}>
                    <Typography sx={displayTitleSx}>
                        {isTakeout
                            ? t("import_from_google_photos")
                            : t("upload_to_ente")}
                    </Typography>
                    <Stack direction="row" sx={headerActionsSx}>
                        <IconButton
                            aria-label={t("close")}
                            onClick={onCancel}
                            sx={headerButtonSx}
                        >
                            <HugeiconsIcon icon={Cancel01Icon} size={18} />
                        </IconButton>
                    </Stack>
                </Stack>

                <Stack sx={mainSx}>
                    <Stack sx={{ gap: "20px" }}>
                        <Stack sx={readySx}>
                            <Box aria-hidden sx={successIllustrationSx}>
                                <Box sx={successIconSx}>
                                    <HugeiconsIcon
                                        icon={Tick02Icon}
                                        size={26}
                                        strokeWidth={2.5}
                                    />
                                </Box>
                            </Box>
                            <Typography
                                id="upload-confirmation-title"
                                component="h2"
                                sx={displayTitleSx}
                            >
                                {isTakeout
                                    ? t("ready_to_import")
                                    : t("ready_to_upload")}
                            </Typography>
                        </Stack>

                        <Stack direction="row" sx={statsSx}>
                            <StatCard
                                value={fileCount}
                                label={t("preupload_media_found", {
                                    count: fileCount,
                                })}
                            />
                            <StatCard
                                value={albumCount}
                                label={t("preupload_album_found", {
                                    count: albumCount,
                                })}
                            />
                        </Stack>
                    </Stack>

                    {isTakeout && (
                        <Stack sx={{ gap: "20px" }}>
                            <Typography component="h3" sx={sectionTitleSx}>
                                {t("more_options")}
                            </Typography>
                            <Stack direction="row" sx={optionSx}>
                                <Box sx={optionIconSx}>
                                    <HugeiconsIcon icon={StarIcon} size={18} />
                                </Box>
                                <Stack sx={optionTextSx}>
                                    <Typography sx={bodySx}>
                                        {t("favorites")}
                                    </Typography>
                                    <Typography sx={captionSx}>
                                        {t("import_favorites_hint")}
                                    </Typography>
                                </Stack>
                                <EnteSwitch
                                    color="accent"
                                    checked={importFavorites}
                                    onChange={onImportFavoritesChange}
                                    slotProps={{
                                        input: { "aria-label": t("favorites") },
                                    }}
                                    sx={switchSx}
                                />
                            </Stack>
                            <Stack direction="row" sx={optionSx}>
                                <Box sx={optionIconSx}>
                                    <HugeiconsIcon
                                        icon={UserMultipleIcon}
                                        size={18}
                                    />
                                </Box>
                                <Stack sx={optionTextSx}>
                                    <Typography sx={bodySx}>
                                        {t("partner_shared_photos")}
                                    </Typography>
                                    <Typography sx={captionSx}>
                                        {t("import_partner_shared_photos_hint")}
                                    </Typography>
                                </Stack>
                                <EnteSwitch
                                    color="accent"
                                    checked={includePartnerSharedFiles}
                                    onChange={onIncludePartnerSharedFilesChange}
                                    slotProps={{
                                        input: {
                                            "aria-label": t(
                                                "partner_shared_photos",
                                            ),
                                        },
                                    }}
                                    sx={switchSx}
                                />
                            </Stack>
                        </Stack>
                    )}
                </Stack>

                <FocusVisibleButton
                    fullWidth
                    color="accent"
                    onClick={onConfirm}
                    sx={confirmButtonSx}
                >
                    {t(isTakeout ? "start_import" : "start_upload")}
                </FocusVisibleButton>
            </Stack>
        </Dialog>
    );
}

function StatCard({ value, label }: { value: number; label: string }) {
    return (
        <Stack sx={statCardSx}>
            <Typography sx={statValueSx}>{value.toLocaleString()}</Typography>
            <Typography sx={captionSx}>{label}</Typography>
        </Stack>
    );
}

/* primary/default in the design */
const green = "#08c225";

const paperSx = (theme: Theme) => ({
    width: "min(607px, calc(100svw - 32px))",
    maxWidth: "none",
    border: "1px solid #e0e0e0",
    borderRadius: "20px",
    backgroundColor: "#f4f4f4",
    backgroundImage: "none",
    boxShadow: "none",
    overflow: "hidden",
    ...theme.applyStyles("dark", {
        borderColor: "rgba(255 255 255 / 0.12)",
        backgroundColor: "#1b1b1b",
    }),
});

const contentSx = { p: "20px", gap: "36px", color: "text.base" };

const headerSx = {
    alignItems: "center",
    justifyContent: "space-between",
    gap: 2,
    minWidth: 0,
};

const headerActionsSx = { alignItems: "center", gap: 1, flexShrink: 0 };

const headerButtonSx = (theme: Theme) => ({
    width: 38,
    height: 38,
    flexShrink: 0,
    p: 0,
    color: "text.base",
    backgroundColor: "background.paper",
    "&:hover": { backgroundColor: "fill.faintHover" },
    ...theme.applyStyles("dark", {
        backgroundColor: "rgba(255 255 255 / 0.12)",
    }),
});

const displayTitleSx = {
    minWidth: 0,
    fontFamily: "'Outfit', sans-serif",
    fontSize: 24,
    fontWeight: 600,
    lineHeight: "32px",
    overflowWrap: "anywhere",
};

const mainSx = { gap: 3, minWidth: 0 };

const readySx = { alignItems: "center", gap: "10px", textAlign: "center" };

const successIllustrationSx = (theme: Theme) => ({
    display: "flex",
    width: 80,
    height: 80,
    alignItems: "center",
    justifyContent: "center",
    borderRadius: "50%",
    backgroundColor: "#ddeedf",
    ...theme.applyStyles("dark", { backgroundColor: "rgba(8 194 37 / 0.16)" }),
});

const successIconSx = {
    display: "flex",
    width: 40,
    height: 40,
    alignItems: "center",
    justifyContent: "center",
    borderRadius: "50%",
    color: "#fff",
    backgroundColor: green,
};

const statsSx = { gap: "10px", minWidth: 0 };

const statCardSx = (theme: Theme) => ({
    flex: "1 1 0",
    minWidth: 0,
    px: "20px",
    py: "12px",
    gap: "4px",
    borderRadius: "16px",
    backgroundColor: "#fff",
    ...theme.applyStyles("dark", { backgroundColor: "#282828" }),
});

const statValueSx = {
    fontSize: 16,
    fontWeight: 600,
    lineHeight: "20px",
    fontVariantNumeric: "tabular-nums",
};

const captionSx = {
    color: "text.muted",
    fontSize: 12,
    fontWeight: 500,
    lineHeight: "16px",
};

const sectionTitleSx = { fontSize: 18, fontWeight: 600, lineHeight: "24px" };

const optionSx = (theme: Theme) => ({
    minHeight: 60,
    alignItems: "center",
    gap: "12px",
    pl: "12px",
    pr: "16px",
    py: "12px",
    borderRadius: "20px",
    backgroundColor: "#fff",
    ...theme.applyStyles("dark", { backgroundColor: "#282828" }),
});

const optionIconSx = {
    display: "flex",
    width: 36,
    height: 36,
    flexShrink: 0,
    alignItems: "center",
    justifyContent: "center",
    color: "text.muted",
};

const optionTextSx = { flex: 1, minWidth: 0, gap: "4px" };

const switchSx = {
    width: 31,
    height: 18,
    flexShrink: 0,
    "& .MuiSwitch-switchBase": {
        m: "2px",
        "&.Mui-checked": { transform: "translateX(13px)" },
    },
    "& .MuiSwitch-thumb": { width: 14, height: 14 },
};

const bodySx = { fontSize: 14, fontWeight: 500, lineHeight: "20px" };

const confirmButtonSx = {
    minHeight: 52,
    px: 3,
    py: "14px",
    borderRadius: "20px",
    color: "#fff",
    backgroundColor: green,
    boxShadow: "none",
    fontSize: 14,
    fontWeight: 500,
    lineHeight: "20px",
    textTransform: "none",
    "&:hover": { backgroundColor: "#07ad21", boxShadow: "none" },
};
