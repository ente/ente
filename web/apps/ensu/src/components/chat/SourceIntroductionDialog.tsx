import { Button, Dialog, Stack, Typography } from "@mui/material";
import React from "react";

interface SourceIntroductionDialogProps {
    open: boolean;
    onClose: () => void;
    onSetUpPacks: () => void;
    onSetUpNotes: () => void;
}

export const SourceIntroductionDialog: React.FC<
    SourceIntroductionDialogProps
> = ({ open, onClose, onSetUpPacks, onSetUpNotes }) => (
    <Dialog
        open={open}
        onClose={onClose}
        maxWidth="sm"
        fullWidth
        aria-labelledby="source-introduction-title"
        slotProps={{
            paper: { sx: { borderRadius: 3, bgcolor: "background.default" } },
        }}
    >
        <Stack sx={{ p: 3, gap: 2 }}>
            <Stack sx={{ gap: 1 }}>
                <Typography id="source-introduction-title" variant="h3">
                    Give Ensu more context
                </Typography>
                <Typography variant="small" sx={{ color: "text.muted" }}>
                    Add a knowledge pack or your notes to help Ensu answer
                    accurately.
                </Typography>
            </Stack>
            <Stack sx={{ gap: 1.5 }}>
                {[
                    {
                        title: "Ensu Packs",
                        description:
                            "Knowledge from Wikipedia to help Ensu get factual questions right.",
                        onSetUp: onSetUpPacks,
                    },
                    {
                        title: "Your Notes",
                        description:
                            "Use a local Markdown notes folder to chat with your own knowledge base.",
                        onSetUp: onSetUpNotes,
                    },
                ].map(({ title, description, onSetUp }) => (
                    <Stack
                        key={title}
                        sx={{
                            p: 2,
                            gap: 1,
                            borderRadius: 2,
                            bgcolor: "fill.faint",
                        }}
                    >
                        <Typography variant="h6">{title}</Typography>
                        <Typography
                            variant="small"
                            sx={{ color: "text.muted" }}
                        >
                            {description}
                        </Typography>
                        <Button
                            variant="contained"
                            color="accent"
                            size="large"
                            aria-label={`Set up ${title}`}
                            sx={{
                                alignSelf: "flex-start",
                                minHeight: 48,
                                px: 3,
                                typography: "body",
                                fontWeight: 600,
                            }}
                            onClick={onSetUp}
                        >
                            Set up
                        </Button>
                    </Stack>
                ))}
            </Stack>
            <Stack sx={{ gap: 0.5, alignItems: "center" }}>
                <Button
                    variant="text"
                    size="small"
                    sx={{
                        color: "text.primary",
                        textDecoration: "underline",
                        textUnderlineOffset: "3px",
                        "&:hover": { textDecoration: "underline" },
                    }}
                    onClick={onClose}
                >
                    Not now
                </Button>
                <Typography
                    variant="mini"
                    sx={{
                        color: "text.muted",
                        fontWeight: 400,
                        textAlign: "center",
                    }}
                >
                    You can set up Ensu Packs and Your Notes later from
                    Settings.
                </Typography>
            </Stack>
        </Stack>
    </Dialog>
);
