import { didShowWhatsNew } from "@/services/changelog";
import ArrowForwardIcon from "@mui/icons-material/ArrowForward";
import {
    Box,
    Dialog,
    DialogActions,
    DialogContent,
    DialogContentText,
    DialogTitle,
    Stack,
    Typography,
    styled,
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
    const fullScreen = useIsSmallWidth();

    useEffect(() => {
        if (open) void didShowWhatsNew(ensureElectron());
    }, [open]);

    return (
        <Dialog
            {...{ open, fullScreen }}
            slots={{ transition: SlideUpTransition }}
            maxWidth="xs"
            fullWidth
        >
            <Box sx={{ m: 1 }}>
                <DialogTitle sx={{ mt: 2, mb: 0 }}>
                    <Typography
                        variant="body"
                        sx={{ color: "text.faint", fontWeight: "regular" }}
                    >
                        {ut("What's new")}
                    </Typography>
                </DialogTitle>
                <DialogContent>
                    <DialogContentText>
                        <ChangelogContent />
                    </DialogContentText>
                </DialogContent>
                <DialogActions>
                    <FocusVisibleButton
                        onClick={onClose}
                        color="accent"
                        fullWidth
                        endIcon={<ArrowForwardIcon />}
                    >
                        <ButtonContents>{ut("Continue")}</ButtonContents>
                    </FocusVisibleButton>
                </DialogActions>
            </Box>
        </Dialog>
    );
};

const ChangelogContent: React.FC = () => {
    // Update changelogVersion whenever this content changes.

    return (
        <Stack sx={{ gap: 2, mb: 1 }}>
            <Typography variant="h6">
                {ut(
                    "Improved hidden album organization, video stream processing progress, Windows installer fixes, and more",
                )}
            </Typography>
            <Typography sx={{ color: "text.muted" }}>
                {ut(
                    "Move photos between hidden albums and view video stream processing progress in Preferences. Title bars now match your theme on Windows and Linux. and bug fixes.",
                )}
            </Typography>
        </Stack>
    );
};

const ButtonContents = styled("div")`
    width: 100%;
    text-align: left;
`;
