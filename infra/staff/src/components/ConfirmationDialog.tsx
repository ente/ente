import {
    Button,
    Dialog,
    DialogActions,
    DialogContent,
    DialogContentText,
    DialogTitle,
    Paper,
    type SxProps,
    type Theme,
} from "@mui/material";
import type { ReactNode } from "react";

type DialogActionTone = "danger" | "success";

interface ConfirmationDialogAction {
    label: string;
    loadingLabel?: string;
    loading?: boolean;
    tone?: DialogActionTone;
    onClick: () => void;
}

interface ConfirmationDialogProps {
    open: boolean;
    title: string;
    children: ReactNode;
    onClose: () => void;
    actions: ConfirmationDialogAction[];
}

export const ConfirmationDialog: React.FC<ConfirmationDialogProps> = ({
    open,
    title,
    children,
    onClose,
    actions,
}) => {
    const isLoading = actions.some(({ loading }) => loading);

    return (
        <Dialog
            open={open}
            onClose={() => {
                if (!isLoading) onClose();
            }}
            aria-labelledby="alert-dialog-title"
            aria-describedby="alert-dialog-description"
            PaperComponent={Paper}
            sx={{
                width: 499,
                height: 286,
                margin: "auto",
                display: "flex",
                flexDirection: "column",
                alignItems: "center",
                justifyContent: "center",
            }}
            slotProps={{
                backdrop: {
                    style: { backgroundColor: "rgba(255, 255, 255, 0.9)" },
                },
            }}
        >
            <DialogTitle id="alert-dialog-title">{title}</DialogTitle>
            <DialogContent>
                <DialogContentText id="alert-dialog-description">
                    {children}
                </DialogContentText>
            </DialogContent>
            <DialogActions sx={{ justifyContent: "center" }}>
                <Button
                    disabled={isLoading}
                    onClick={onClose}
                    sx={cancelButtonSx}
                    type="button"
                >
                    Cancel
                </Button>
                {actions.map(
                    ({ label, loadingLabel, loading, tone, onClick }) => (
                        <Button
                            key={label}
                            onClick={onClick}
                            sx={actionButtonSx[tone ?? "danger"]}
                            disabled={isLoading}
                            type="button"
                        >
                            {loading && loadingLabel ? loadingLabel : label}
                        </Button>
                    ),
                )}
            </DialogActions>
        </Dialog>
    );
};

const cancelButtonSx: SxProps<Theme> = {
    bgcolor: "white",
    color: "black",
    "&:hover": { bgcolor: "#FAFAFA" },
};

const actionButtonSx: Record<DialogActionTone, SxProps<Theme>> = {
    danger: {
        bgcolor: "#F4473D",
        color: "white",
        "&:hover": { bgcolor: "#E53935" },
    },
    success: {
        bgcolor: "#4CAF50",
        color: "white",
        "&:hover": { bgcolor: "#45A049" },
    },
};
