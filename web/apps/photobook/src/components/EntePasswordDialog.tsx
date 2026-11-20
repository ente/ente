import { TextField } from "@mui/material";
import { useEffect, useRef } from "react";
import PhotoChoiceDialog from "./PhotoChoiceDialog";

interface EntePasswordDialogProps {
    open: boolean;
    password: string;
    error?: string;
    submitting: boolean;
    onPasswordChange: (v: string) => void;
    onSubmit: () => void;
    onCancel: () => void;
}

export default function EntePasswordDialog({
    open,
    password,
    error,
    submitting,
    onPasswordChange,
    onSubmit,
    onCancel,
}: EntePasswordDialogProps) {
    const inputRef = useRef<HTMLInputElement>(null);
    useEffect(() => {
        if (error) {
            inputRef.current?.focus();
            inputRef.current?.select();
        }
    }, [error]);
    return (
        <PhotoChoiceDialog
            open={open}
            icon="lock"
            title="Album password"
            description="Enter the album password to continue."
            primary={{
                label: submitting ? "Unlocking..." : "Unlock",
                onClick: onSubmit,
                disabled: submitting || !password,
            }}
            onClose={submitting ? undefined : onCancel}
        >
            <TextField
                autoFocus
                inputRef={inputRef}
                fullWidth
                type="password"
                label="Password"
                value={password}
                error={!!error}
                helperText={error}
                disabled={submitting}
                onChange={(event) => onPasswordChange(event.target.value)}
                onKeyDown={(event) => {
                    if (event.key === "Enter" && password && !submitting) {
                        event.preventDefault();
                        onSubmit();
                    }
                }}
            />
        </PhotoChoiceDialog>
    );
}
