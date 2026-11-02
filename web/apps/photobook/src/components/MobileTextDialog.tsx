import {
    Button,
    Dialog,
    DialogActions,
    DialogContent,
    DialogTitle,
    TextField,
} from "@mui/material";
import { useEffect, useState } from "react";

export default function MobileTextDialog({
    title,
    value,
    multiline = false,
    onSave,
    onClose,
}: {
    title: string;
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
            fullWidth
            maxWidth="xs"
            aria-labelledby="mobile-text-title"
            sx={{
                "& .MuiDialog-container": {
                    alignItems: "flex-start",
                    height: viewport?.height,
                    transform: viewport
                        ? `translateY(${viewport.top}px)`
                        : undefined,
                },
            }}
            slotProps={{
                paper: {
                    sx: {
                        m: 2,
                        mt: "max(16px, env(safe-area-inset-top))",
                        width: "calc(100% - 32px)",
                        maxHeight: "calc(100% - 32px)",
                    },
                },
            }}
        >
            <DialogTitle id="mobile-text-title">{title}</DialogTitle>
            <DialogContent>
                <TextField
                    autoFocus
                    fullWidth
                    multiline={multiline}
                    minRows={multiline ? 3 : undefined}
                    maxRows={6}
                    label={title}
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
                    sx={{ mt: 1, "& input, & textarea": { fontSize: 16 } }}
                />
            </DialogContent>
            <DialogActions sx={{ p: 2, "& button": { minHeight: 44 } }}>
                <Button variant="text" onClick={onClose}>
                    Cancel
                </Button>
                <Button variant="contained" onClick={save}>
                    Done
                </Button>
            </DialogActions>
        </Dialog>
    );
}
