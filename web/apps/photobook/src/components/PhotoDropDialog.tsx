import type { PhotoDropChoice } from "@/hooks/usePhotoDrag";
import { accentGreen } from "@/theme/buttons";
import {
    dialogActionSx,
    dialogCancelButtonSx,
    dialogCloseButtonSx,
    dialogDescriptionSx,
    dialogHeaderSx,
    dialogPaperSx,
    dialogTitleSx,
} from "@/theme/dialogs";
import { Box, Button, Dialog, IconButton, Typography } from "@mui/material";
import { AddPhotosIcon, CloseIcon } from "./icons";

export default function PhotoDropDialog({
    open,
    onChoose,
}: {
    open: boolean;
    onChoose: (choice: PhotoDropChoice) => void;
}) {
    const close = () => onChoose("cancel");
    return (
        <Dialog
            open={open}
            onClose={close}
            maxWidth={false}
            aria-labelledby="photo-drop-title"
            aria-describedby="photo-drop-description"
            slotProps={{
                paper: { sx: dialogPaperSx },
                backdrop: { sx: { bgcolor: "rgba(0,0,0,0.5)" } },
            }}
        >
            <Box
                sx={{
                    position: "relative",
                    display: "grid",
                    justifyItems: "center",
                    gap: 1.5,
                    p: "48px 16px 16px",
                }}
            >
                <IconButton
                    aria-label="Close"
                    onClick={close}
                    sx={dialogCloseButtonSx}
                >
                    <CloseIcon sx={{ fontSize: 20 }} />
                </IconButton>
                <AddPhotosIcon
                    aria-hidden
                    sx={{ fontSize: 72, my: 3, color: accentGreen }}
                />
                <Box sx={dialogHeaderSx}>
                    <Typography
                        component="h2"
                        id="photo-drop-title"
                        sx={dialogTitleSx}
                    >
                        Add or swap photos?
                    </Typography>
                    <Typography
                        id="photo-drop-description"
                        sx={dialogDescriptionSx}
                    >
                        Keep both photos on this page, or swap them between
                        pages.
                    </Typography>
                </Box>
                <Button
                    variant="contained"
                    fullWidth
                    autoFocus
                    onClick={() => onChoose("add")}
                    sx={dialogActionSx}
                >
                    Add to page
                </Button>
                <Button
                    variant="outlined"
                    fullWidth
                    onClick={() => onChoose("swap")}
                    sx={dialogCancelButtonSx}
                >
                    Swap photos
                </Button>
            </Box>
        </Dialog>
    );
}
