import { accentGreen, accentGreenHover } from "@/theme/buttons";
import { uiColors } from "@/theme/colors";
import {
    dialogActionSx,
    dialogDescriptionSx,
    dialogHeaderSx,
    dialogPaperSx,
    dialogTitleSx,
} from "@/theme/dialogs";
import { Box, Button, Dialog, Typography } from "@mui/material";
import { ErrorIcon } from "./icons";

export default function RestoreErrorDialog() {
    return (
        <Dialog
            open
            maxWidth={false}
            aria-labelledby="restore-error-title"
            aria-describedby="restore-error-description"
            slotProps={{
                paper: { role: "alertdialog", sx: dialogPaperSx },
                backdrop: { sx: { bgcolor: "rgba(0,0,0,0.5)" } },
            }}
        >
            <Box sx={{ position: "relative", p: "48px 16px 16px" }}>
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
                            color: uiColors.danger,
                        }}
                    >
                        <ErrorIcon sx={{ fontSize: 72 }} />
                    </Box>
                    <Box sx={dialogHeaderSx}>
                        <Typography
                            component="h2"
                            id="restore-error-title"
                            sx={dialogTitleSx}
                        >
                            Couldn&apos;t open photobook
                        </Typography>
                        <Typography
                            id="restore-error-description"
                            sx={dialogDescriptionSx}
                        >
                            Your saved book hasn&apos;t been changed.
                            <br />
                            Reload to try again.
                        </Typography>
                    </Box>
                    <Button
                        variant="contained"
                        fullWidth
                        disableElevation
                        autoFocus
                        onClick={() => window.location.reload()}
                        sx={{
                            ...dialogActionSx,
                            color: "#FFFFFF",
                            bgcolor: accentGreen,
                            "&:hover": { bgcolor: accentGreenHover },
                        }}
                    >
                        Reload
                    </Button>
                </Box>
            </Box>
        </Dialog>
    );
}
