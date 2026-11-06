import { accentGreen } from "@/theme/buttons";
import { uiColors } from "@/theme/colors";
import {
    dialogActionSx,
    dialogCloseButtonSx,
    dialogDescriptionSx,
    dialogHeaderSx,
    dialogPaperSx,
    dialogTitleSx,
} from "@/theme/dialogs";
import {
    Box,
    Button,
    Dialog,
    IconButton,
    TextField,
    Typography,
} from "@mui/material";
import { useEffect, useState } from "react";
import { CloseIcon, TitleIcon } from "./icons";

export default function MobileTextDialog({
    title,
    description,
    value,
    multiline = false,
    onSave,
    onClose,
}: {
    title: string;
    description?: string;
    value: string;
    multiline?: boolean;
    onSave: (value: string) => void;
    onClose: () => void;
}) {
    const [draft, setDraft] = useState(value);
    const [viewport, setViewport] = useState<{ height: number; top: number }>();
    useEffect(() => {
        const visualViewport = window.visualViewport;
        if (!visualViewport) return;
        const measure = () =>
            setViewport({
                height: visualViewport.height,
                top: visualViewport.offsetTop,
            });
        measure();
        visualViewport.addEventListener("resize", measure);
        visualViewport.addEventListener("scroll", measure);
        return () => {
            visualViewport.removeEventListener("resize", measure);
            visualViewport.removeEventListener("scroll", measure);
        };
    }, []);
    const save = () => {
        onSave(draft);
        onClose();
    };
    return (
        <Dialog
            open
            onClose={onClose}
            maxWidth={false}
            aria-labelledby="mobile-text-title"
            aria-describedby={
                description ? "mobile-text-description" : undefined
            }
            sx={{
                "& .MuiDialog-container": {
                    alignItems: "center",
                    height: viewport?.height,
                    transform: viewport
                        ? `translateY(${viewport.top}px)`
                        : undefined,
                },
            }}
            slotProps={{
                backdrop: { sx: { bgcolor: "rgba(0,0,0,0.5)" } },
                paper: {
                    sx: { ...dialogPaperSx, maxHeight: "calc(100% - 32px)" },
                },
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
                        <TitleIcon sx={{ fontSize: 72 }} />
                    </Box>
                    <Box sx={dialogHeaderSx}>
                        <Typography
                            component="h2"
                            id="mobile-text-title"
                            sx={dialogTitleSx}
                        >
                            {title}
                        </Typography>
                        {description && (
                            <Typography
                                id="mobile-text-description"
                                sx={dialogDescriptionSx}
                            >
                                {description}
                            </Typography>
                        )}
                    </Box>
                    <TextField
                        autoFocus
                        fullWidth
                        multiline={multiline}
                        minRows={multiline ? 3 : undefined}
                        maxRows={6}
                        variant="standard"
                        slotProps={{ htmlInput: { "aria-label": title } }}
                        value={draft}
                        onChange={(event) => setDraft(event.target.value)}
                        onKeyDown={(event) => {
                            if (
                                event.key === "Enter" &&
                                !multiline &&
                                !event.nativeEvent.isComposing
                            ) {
                                event.preventDefault();
                                save();
                            }
                        }}
                        sx={{
                            "& .MuiInput-root": {
                                minHeight: 54,
                                bgcolor: "rgba(255,255,255,0.08)",
                                borderRadius: "12px",
                                "&::before": {
                                    borderBottom:
                                        "1px solid rgba(255,255,255,0.3)",
                                },
                                "&::after": {
                                    borderBottom: `2px solid ${accentGreen}`,
                                },
                                "&:hover:not(.Mui-disabled)::before": {
                                    borderBottom:
                                        "1px solid rgba(255,255,255,0.5)",
                                },
                            },
                            "& input, & textarea": {
                                px: "16px",
                                fontSize: 16,
                                color: "#FFFFFF",
                                "&::placeholder": {
                                    color: "rgba(255,255,255,0.5)",
                                    opacity: 1,
                                },
                            },
                        }}
                    />
                    <Button
                        variant="contained"
                        fullWidth
                        onClick={save}
                        onMouseDown={(event) => event.preventDefault()}
                        sx={dialogActionSx}
                    >
                        Save
                    </Button>
                </Box>
            </Box>
        </Dialog>
    );
}
