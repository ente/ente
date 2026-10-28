"use client";

import { accentGreen, accentGreenHover } from "@/theme/buttons";
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
import { useId, useState } from "react";
import { CloseIcon, InfoIcon } from "./icons";

export default function RequiredPageDialog({
    onClose,
}: {
    onClose: () => void;
}) {
    const id = useId();
    const [open, setOpen] = useState(true);
    const close = () => setOpen(false);

    return (
        <Dialog
            open={open}
            onClose={close}
            maxWidth={false}
            aria-labelledby={`${id}-title`}
            aria-describedby={`${id}-description ${id}-tips`}
            slotProps={{
                paper: { sx: dialogPaperSx },
                backdrop: { sx: { bgcolor: "rgba(0,0,0,0.5)" } },
                transition: { onExited: onClose },
            }}
        >
            <Box sx={{ position: "relative", p: "48px 16px 16px" }}>
                <IconButton
                    aria-label="Close"
                    onClick={close}
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
                            color: uiColors.muted,
                        }}
                    >
                        <InfoIcon sx={{ fontSize: 72 }} />
                    </Box>
                    <Box sx={dialogHeaderSx}>
                        <Typography
                            component="h2"
                            id={`${id}-title`}
                            sx={dialogTitleSx}
                        >
                            Page required for printing
                        </Typography>
                        <Typography
                            id={`${id}-description`}
                            sx={dialogDescriptionSx}
                        >
                            Printed books need an even page count.
                        </Typography>
                    </Box>
                    <Box
                        component="ul"
                        id={`${id}-tips`}
                        sx={{
                            width: "100%",
                            boxSizing: "border-box",
                            m: 0,
                            p: "16px",
                            listStyle: "none",
                            borderRadius: "16px",
                            bgcolor: "rgba(255,255,255,0.04)",
                            display: "flex",
                            flexDirection: "column",
                            gap: "16px",
                            textAlign: "left",
                        }}
                    >
                        <Box component="li">
                            <Typography
                                sx={{
                                    ...dialogDescriptionSx,
                                    color: "#FFFFFF",
                                    fontWeight: 600,
                                    mb: "4px",
                                }}
                            >
                                It doesn’t have to stay blank
                            </Typography>
                            <Typography sx={dialogDescriptionSx}>
                                You can add photos or text here.
                            </Typography>
                        </Box>
                        <Box
                            component="li"
                            sx={{
                                borderTop: "1px solid rgba(255,255,255,0.08)",
                                pt: "16px",
                            }}
                        >
                            <Typography
                                sx={{
                                    ...dialogDescriptionSx,
                                    color: "#FFFFFF",
                                    fontWeight: 600,
                                    mb: "4px",
                                }}
                            >
                                Want to remove it?
                            </Typography>
                            <Typography sx={dialogDescriptionSx}>
                                Delete another page to remove both.
                            </Typography>
                        </Box>
                    </Box>
                    <Button
                        variant="contained"
                        fullWidth
                        disableElevation
                        autoFocus
                        onClick={close}
                        sx={{
                            ...dialogActionSx,
                            color: "#FFFFFF",
                            bgcolor: accentGreen,
                            "&:hover": { bgcolor: accentGreenHover },
                        }}
                    >
                        Got it
                    </Button>
                </Box>
            </Box>
        </Dialog>
    );
}
