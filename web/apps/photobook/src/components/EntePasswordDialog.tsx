"use client";

import {
    Button,
    Dialog,
    DialogActions,
    DialogContent,
    DialogTitle,
    TextField,
    Typography,
} from "@mui/material";

interface EntePasswordDialogProps {
    open: boolean;
    password: string;
    onPasswordChange: (v: string) => void;
    onSubmit: () => void;
    onCancel: () => void;
}

export default function EntePasswordDialog({
    open,
    password,
    onPasswordChange,
    onSubmit,
    onCancel,
}: EntePasswordDialogProps) {
    return (
        <Dialog open={open} onClose={onCancel} maxWidth="xs" fullWidth>
            <DialogTitle
                sx={{
                    fontFamily: "var(--font-inter), sans-serif",
                    fontWeight: 700,
                }}
            >
                Album password
            </DialogTitle>
            <DialogContent>
                <Typography
                    sx={{ color: "text.secondary", mb: 2, fontSize: "0.95rem" }}
                >
                    This album is password-protected. Enter the password shared
                    with you.
                </Typography>
                <TextField
                    autoFocus
                    fullWidth
                    variant="outlined"
                    type="password"
                    placeholder="Password"
                    value={password}
                    onChange={(e) => onPasswordChange(e.target.value)}
                    onKeyDown={(e) => {
                        if (e.key === "Enter") {
                            e.preventDefault();
                            onSubmit();
                        }
                    }}
                />
            </DialogContent>
            <DialogActions sx={{ px: 3, pb: 2 }}>
                <Button onClick={onCancel} sx={{ color: "text.secondary" }}>
                    Cancel
                </Button>
                <Button
                    onClick={onSubmit}
                    variant="contained"
                    sx={{
                        background: "#08C225",
                        fontWeight: 700,
                        "&:hover": { background: "#07AE22" },
                    }}
                >
                    Unlock
                </Button>
            </DialogActions>
        </Dialog>
    );
}
