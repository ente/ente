import { uiColors } from "@/theme/colors";
import {
    dialogActionSx,
    dialogCloseButtonSx,
    dialogDescriptionSx,
    dialogHeaderSx,
    dialogPaperSx,
    dialogTitleSx,
} from "@/theme/dialogs";
import { Box, Button, Dialog, IconButton, Typography } from "@mui/material";
import { CloseIcon, EditIcon } from "./icons";

export default function DesktopEditingDialog({
    open,
    onClose,
}: {
    open: boolean;
    onClose: () => void;
}) {
    return (
        <Dialog
            open={open}
            onClose={onClose}
            aria-labelledby="desktop-editing-title"
            aria-describedby="desktop-editing-description"
            maxWidth={false}
            slotProps={{
                paper: { sx: dialogPaperSx },
                backdrop: { sx: { bgcolor: "rgba(0,0,0,0.5)" } },
            }}
        >
            <Box sx={{ position: "relative", p: "48px 16px 16px" }}>
                <IconButton
                    aria-label="Close"
                    onClick={onClose}
                    sx={dialogCloseButtonSx}
                >
                    <CloseIcon sx={{ fontSize: 20 }} />
                </IconButton>
                <Box
                    sx={{
                        display: "flex",
                        flexDirection: "column",
                        alignItems: "center",
                        gap: "16px",
                    }}
                >
                    <Box
                        aria-hidden="true"
                        sx={{
                            width: 126,
                            height: 121,
                            display: "flex",
                            alignItems: "center",
                            justifyContent: "center",
                            mb: "8px",
                            color: uiColors.text,
                        }}
                    >
                        <EditIcon sx={{ fontSize: 72 }} />
                    </Box>
                    <Box sx={dialogHeaderSx}>
                        <Typography
                            component="h2"
                            id="desktop-editing-title"
                            sx={dialogTitleSx}
                        >
                            Edit on desktop
                        </Typography>
                        <Typography
                            id="desktop-editing-description"
                            sx={dialogDescriptionSx}
                        >
                            Use the desktop version to arrange photos, change
                            layouts and edit page text.
                        </Typography>
                    </Box>
                    <Button
                        variant="contained"
                        fullWidth
                        autoFocus
                        onClick={onClose}
                        sx={dialogActionSx}
                    >
                        Got it
                    </Button>
                </Box>
            </Box>
        </Dialog>
    );
}
