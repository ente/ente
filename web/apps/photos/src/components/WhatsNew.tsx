import { didShowWhatsNew } from "@/services/changelog";
import CloseIcon from "@mui/icons-material/Close";
import {
    Box,
    Dialog,
    DialogActions,
    DialogContent,
    DialogTitle,
    IconButton,
    Stack,
    Typography,
} from "@mui/material";
import { FocusVisibleButton } from "ente-base/components/mui/FocusVisibleButton";
import { useIsSmallWidth } from "ente-base/components/utils/hooks";
import { ensureElectron } from "ente-base/electron";
import { ut } from "ente-base/i18n";
import { SlideUpTransition } from "ente-new/photos/components/mui/SlideUpTransition";
import React, { useEffect } from "react";

interface WhatsNewProps {
    open: boolean;
    onClose: () => void;
}

export const WhatsNew: React.FC<WhatsNewProps> = ({ open, onClose }) => {
    const isSmallWidth = useIsSmallWidth();

    useEffect(() => {
        if (open) void didShowWhatsNew(ensureElectron());
    }, [open]);

    return (
        <Dialog
            open={open}
            onClose={onClose}
            slots={{ transition: SlideUpTransition }}
            aria-labelledby="whats-new-title"
            sx={{
                "& .MuiDialog-container": {
                    alignItems: isSmallWidth ? "flex-end" : "center",
                },
            }}
            slotProps={{
                backdrop: { sx: { backgroundColor: "rgba(0, 0, 0, 0.55)" } },
                paper: {
                    sx: (theme) => ({
                        m: isSmallWidth ? 0 : 2.5,
                        width: isSmallWidth ? "100%" : "calc(100% - 40px)",
                        maxWidth: 440,
                        p: 2.5,
                        pb: "max(20px, env(safe-area-inset-bottom))",
                        maxHeight: "calc(100dvh - 40px)",
                        borderRadius: isSmallWidth ? "20px 20px 0 0" : "24px",
                        bgcolor: "#F4F4F4",
                        color: "#000000",
                        "--changelog-muted": "#666666",
                        "--changelog-close": "#FFFFFF",
                        "--changelog-close-hover": "#EAEAEA",
                        ...theme.applyStyles("dark", {
                            bgcolor: "#161616",
                            color: "#FFFFFF",
                            "--changelog-muted": "#999999",
                            "--changelog-close": "#212121",
                            "--changelog-close-hover": "#0A0A0A",
                        }),
                    }),
                },
            }}
        >
            <DialogTitle
                id="whats-new-title"
                sx={{ p: 0, pb: 2, textAlign: "center", position: "relative" }}
            >
                <IconButton
                    aria-label={ut("Close")}
                    onClick={onClose}
                    sx={{
                        position: "absolute",
                        top: 0,
                        right: 0,
                        width: 36,
                        height: 36,
                        bgcolor: "var(--changelog-close)",
                        color: "inherit",
                        "&:hover": { bgcolor: "var(--changelog-close-hover)" },
                    }}
                >
                    <CloseIcon sx={{ fontSize: 20 }} />
                </IconButton>
                <Box
                    component="img"
                    src="/images/whats-new.png"
                    alt=""
                    sx={{
                        display: "block",
                        width: 115,
                        height: 108,
                        objectFit: "contain",
                        mx: "auto",
                        mb: 1,
                    }}
                />
                <Typography
                    component="span"
                    sx={{
                        fontFamily: '"Outfit Variable", Outfit, sans-serif',
                        fontSize: 24,
                        lineHeight: "32px",
                        fontWeight: 600,
                    }}
                >
                    {ut("What’s new in Ente Photos 2.0")}
                </Typography>
            </DialogTitle>
            <DialogContent sx={{ p: 0, pr: 2 }}>
                <ChangelogContent />
            </DialogContent>
            <DialogActions sx={{ p: 0, pt: 2 }}>
                <FocusVisibleButton
                    onClick={onClose}
                    fullWidth
                    sx={{
                        height: 52,
                        borderRadius: "20px",
                        bgcolor: "#08C225",
                        color: "#FFFFFF",
                        fontSize: 14,
                        "&:hover": { bgcolor: "#069D1E" },
                        "&:active": { bgcolor: "#057C18" },
                    }}
                >
                    {ut("Continue")}
                </FocusVisibleButton>
            </DialogActions>
        </Dialog>
    );
};

const ChangelogContent: React.FC = () => {
    // Update changelogVersion whenever this content changes.

    return (
        <Stack sx={{ gap: 2 }}>
            <UpdateEntry
                title={ut("A fresh look")}
                description={ut(
                    "We’ve redesigned the app, from the gallery to Settings. The new collapsible navigation rail makes it easier to move around your library.",
                )}
            />
            <UpdateEntry
                title={ut("Feed and Places")}
                description={ut(
                    "Catch up on shared photos, likes, and comments in Feed. Search for a location in Places or explore the map to see photos taken there.",
                )}
            />
            <UpdateEntry
                title={ut("Easier to find, edit, and download")}
                description={ut(
                    "Jump to a date with the new date scrubber. Try the redesigned search and photo editing presets, keep track of your downloads, and so much more.",
                )}
            />
        </Stack>
    );
};

const UpdateEntry = ({
    title,
    description,
}: {
    title: string;
    description: string;
}) => (
    <Box>
        <Typography
            sx={{ fontSize: 16, lineHeight: "20px", fontWeight: 600, mb: 1.5 }}
        >
            {title}
        </Typography>
        <Typography
            sx={{
                color: "var(--changelog-muted)",
                fontSize: 14,
                lineHeight: "20px",
                fontWeight: 500,
            }}
        >
            {description}
        </Typography>
    </Box>
);
