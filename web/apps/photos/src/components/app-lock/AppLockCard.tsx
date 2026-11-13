import { Box, Paper } from "@mui/material";
import type { PropsWithChildren, ReactNode } from "react";

const APP_LOCK_MODAL_WIDTH = 408;

interface AppLockCardProps {
    closeAction?: ReactNode;
    width?: number;
}

export const AppLockCard = ({
    children,
    closeAction,
    width = APP_LOCK_MODAL_WIDTH,
}: PropsWithChildren<AppLockCardProps>) => (
    <Paper
        elevation={0}
        sx={(theme) => ({
            width: `${String(width)}px`,
            maxWidth: "calc(100% - 32px)",
            boxSizing: "border-box",
            borderRadius: "28px",
            backgroundColor: "#fff",
            border: "1px solid #E0E0E0",
            boxShadow: "none",
            overflow: "visible",
            ...theme.applyStyles("dark", {
                backgroundColor: "#1B1B1B",
                border: "1px solid rgba(255, 255, 255, 0.18)",
            }),
        })}
    >
        <Box
            sx={{
                position: "relative",
                width: "100%",
                pt: closeAction ? 2 : 6,
                px: 2,
                pb: 2.5,
            }}
        >
            {closeAction && (
                <Box
                    sx={{
                        width: "100%",
                        display: "flex",
                        justifyContent: "flex-end",
                        mb: 1,
                    }}
                >
                    {closeAction}
                </Box>
            )}
            <Box
                sx={{
                    width: "100%",
                    display: "flex",
                    justifyContent: "center",
                }}
            >
                {children}
            </Box>
        </Box>
    </Paper>
);
