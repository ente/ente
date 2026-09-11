import CloseIcon from "@mui/icons-material/Close";
import {
    Dialog,
    IconButton,
    Stack,
    Typography,
    type DialogProps,
} from "@mui/material";
import React from "react";

interface LegacyActionSheetProps {
    open: boolean;
    title: string;
    subtitle?: React.ReactNode;
    onClose: () => void;
    children: React.ReactNode;
}

export const LegacyActionSheet: React.FC<LegacyActionSheetProps> = ({
    open,
    title,
    subtitle,
    onClose,
    children,
}) => {
    const handleClose: DialogProps["onClose"] = () => {
        onClose();
    };

    return (
        <Dialog
            open={open}
            onClose={handleClose}
            fullWidth
            maxWidth={false}
            slotProps={{
                backdrop: { sx: { backgroundColor: "rgba(0, 0, 0, 0.55)" } },
                container: {
                    sx: { alignItems: { xs: "flex-end", sm: "center" } },
                },
                paper: {
                    sx: (theme) => ({
                        m: 0,
                        width: "min(100%, 440px)",
                        maxHeight: "calc(100vh - 48px)",
                        borderRadius: "24px",
                        backgroundColor: "background.default",
                        padding: "20px",
                        overflowY: "auto",
                        [theme.breakpoints.down("sm")]: {
                            width: "100%",
                            maxWidth: "100%",
                            borderRadius: "20px 20px 0 0",
                            paddingBottom: "34px",
                            m: 0,
                        },
                    }),
                },
            }}
        >
            <Stack sx={{ gap: 2.5 }}>
                <Stack
                    direction="row"
                    sx={{ alignItems: "center", gap: 1.5, minHeight: 38 }}
                >
                    <Typography
                        variant="h6"
                        sx={{
                            wordBreak: "break-word",
                            flex: 1,
                            lineHeight: "24px",
                        }}
                    >
                        {title}
                    </Typography>
                    <IconButton
                        onClick={onClose}
                        sx={{
                            width: 36,
                            height: 36,
                            p: 0,
                            borderRadius: "50%",
                            bgcolor: "background.paper",
                            flexShrink: 0,
                            "&:hover": { bgcolor: "fill.faintHover" },
                        }}
                    >
                        <CloseIcon sx={{ fontSize: 18 }} />
                    </IconButton>
                </Stack>
                {subtitle && (
                    <Typography
                        variant="small"
                        sx={{
                            color: "text.muted",
                            wordBreak: "break-word",
                            lineHeight: "20px",
                        }}
                    >
                        {subtitle}
                    </Typography>
                )}
                {children}
            </Stack>
        </Dialog>
    );
};
