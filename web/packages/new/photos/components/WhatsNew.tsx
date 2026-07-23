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
import React, { useEffect } from "react";
import { didShowWhatsNew } from "../services/changelog";
import { SlideUpTransition } from "./mui/SlideUpTransition";

interface WhatsNewProps {
    /** If `true`, then the dialog is shown. */
    open: boolean;
    /** Called when the dialog wants to be closed. */
    onClose: () => void;
}

/**
 * A dialog showing a short summary of interesting-for-the-user things since the
 * last time this dialog was shown.
 */
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
    // NOTE: Remember to update changelogVersion when changing the content
    // below.

    return (
        <Stack sx={{ gap: 2, mb: 1 }}>
            <Typography variant="h6">
                {ut(
                    "Improved Google Takeout imports, Archived view, File navigation experience and more",
                )}
            </Typography>
            <Typography sx={{ color: "text.muted" }}>
                {ut(
                    "Google Takeout imports now preserve favorites, Archive section shows only archived albums, upload progress lists skipped files, File Info stays open on navigation, shared links are easier to spot, and new translations are available.",
                )}
            </Typography>
        </Stack>
    );
};

const ButtonContents = styled("div")`
    /* Make the button text fill the entire space so the endIcon shows at the
       trailing edge of the button. */
    width: 100%;
    text-align: left;
`;
