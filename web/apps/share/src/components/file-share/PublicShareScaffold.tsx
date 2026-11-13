import { Box } from "@mui/material";
import React, { type ReactNode } from "react";

interface PublicShareScaffoldProps {
    children: ReactNode;
}

export const PublicShareScaffold: React.FC<PublicShareScaffoldProps> = ({
    children,
}) => {
    return (
        <Box
            sx={{
                minHeight: "100dvh",
                width: "100%",
                maxWidth: "100%",
                bgcolor: "accent.main",
                display: "flex",
                flexDirection: "column",
                alignItems: "center",
                p: { xs: 1.25, md: 2 },
                boxSizing: "border-box",
                overflowX: "hidden",
                "& ::selection": {
                    backgroundColor: "accent.main",
                    color: "fixed.white",
                },
                "& ::-moz-selection": {
                    backgroundColor: "accent.main",
                    color: "fixed.white",
                },
            }}
        >
            <Box
                sx={{
                    height: {
                        xs: "calc(100dvh - 20px)",
                        md: "calc(100dvh - 32px)",
                    },
                    width: "100%",
                    bgcolor: "background.default",
                    borderRadius: { xs: "24px", md: "34px" },
                    display: "flex",
                    flexDirection: "column",
                    alignItems: "center",
                    overflow: "hidden",
                }}
            >
                <Box
                    sx={{
                        width: "100%",
                        display: "flex",
                        alignItems: "center",
                        justifyContent: { xs: "center", md: "flex-end" },
                        minHeight: { xs: 88, md: 104 },
                        px: { xs: 3, md: 4.5 },
                    }}
                >
                    <a
                        href="https://ente.com/locker"
                        target="_blank"
                        rel="noopener noreferrer"
                        style={{ display: "block", lineHeight: 0 }}
                    >
                        <picture>
                            <source
                                srcSet="/images/ente-locker-white.svg"
                                media="(prefers-color-scheme: dark)"
                            />
                            <Box
                                component="img"
                                src="/images/ente-locker.svg"
                                alt="Ente Locker"
                                sx={{ height: "56px", cursor: "pointer" }}
                            />
                        </picture>
                    </a>
                </Box>
                <Box
                    sx={{
                        width: "100%",
                        flex: 1,
                        display: "flex",
                        flexDirection: "column",
                        minHeight: 0,
                    }}
                >
                    {children}
                </Box>
            </Box>
        </Box>
    );
};
