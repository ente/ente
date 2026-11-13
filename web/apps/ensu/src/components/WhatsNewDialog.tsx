import type { WhatsNewEntry } from "@/services/whats-new-content";
import {
    Button,
    Dialog,
    DialogActions,
    DialogContent,
    DialogTitle,
    Stack,
    Typography,
} from "@mui/material";
import React from "react";

export interface WhatsNewDialogProps {
    readonly open: boolean;
    readonly entries: readonly WhatsNewEntry[];
    readonly onClose: () => void;
}

export const WhatsNewDialog: React.FC<WhatsNewDialogProps> = ({
    open,
    entries,
    onClose,
}) => (
    <Dialog open={open} onClose={onClose} maxWidth="xs" fullWidth>
        <DialogTitle sx={{ pb: 1 }}>{"What's new"}</DialogTitle>
        <DialogContent sx={{ pt: 0 }}>
            <Stack spacing={2}>
                {entries.map((entry, index) => (
                    <Stack key={`${entry.title}-${index}`} spacing={1}>
                        <Typography variant="h6">{entry.title}</Typography>
                        <Typography sx={{ color: "text.muted" }}>
                            {entry.description}
                        </Typography>
                    </Stack>
                ))}
            </Stack>
        </DialogContent>
        <DialogActions sx={{ px: 3, pb: 3 }}>
            <Button onClick={onClose} variant="contained" fullWidth>
                Continue
            </Button>
        </DialogActions>
    </Dialog>
);
