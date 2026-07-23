import { usePasteColorMode } from "@/features/paste/hooks/usePasteColorMode";
import { getPasteThemeTokens } from "@/features/paste/theme/pasteThemeTokens";
import GitHubIcon from "@mui/icons-material/GitHub";
import { Box, IconButton, Stack, Typography } from "@mui/material";
import { EnteLogo } from "ente-base/components/EnteLogo";
import type { ReactNode } from "react";

interface PasteFrameProps {
    children: ReactNode;
    footer: ReactNode;
}

export const PasteFrame = ({ children, footer }: PasteFrameProps) => {
    const { resolvedMode } = usePasteColorMode();
    const tokens = getPasteThemeTokens(resolvedMode);

    return (
        <Box
            sx={{
                minHeight: "100dvh",
                width: "100%",
                maxWidth: "100%",
                bgcolor: tokens.frame.outerBg,
                fontFamily: '"Inter Variable", sans-serif',
                display: "flex",
                flexDirection: "column",
                alignItems: "stretch",
                p: { xs: 1.25, md: 2 },
                boxSizing: "border-box",
                overflowX: "hidden",
            }}
        >
            <Box
                sx={{
                    position: "relative",
                    minHeight: {
                        xs: "calc(100dvh - 20px)",
                        md: "calc(100dvh - 32px)",
                    },
                    flex: 1,
                    width: "100%",
                    maxWidth: "100%",
                    bgcolor: tokens.frame.innerBg,
                    borderRadius: { xs: "24px", md: "34px" },
                    display: "grid",
                    gridTemplateRows: "auto 1fr auto",
                    alignItems: "stretch",
                    boxShadow: `inset 0 0 0 1px ${tokens.frame.innerBorder}`,
                    overflowX: "hidden",
                    "& ::selection": {
                        backgroundColor: tokens.frame.selectionBg,
                        color: tokens.frame.selectionText,
                    },
                    "& ::-moz-selection": {
                        backgroundColor: tokens.frame.selectionBg,
                        color: tokens.frame.selectionText,
                    },
                }}
            >
                <Box
                    sx={{
                        width: "100%",
                        display: "flex",
                        alignItems: "center",
                        justifyContent: "space-between",
                        px: { xs: 3, md: 4.5 },
                        pt: { xs: 3, md: 3.5 },
                    }}
                >
                    <Stack
                        component="a"
                        href="https://paste.ente.com"
                        direction="row"
                        spacing={0.35}
                        aria-label="Go to Ente Paste home"
                        sx={{
                            alignItems: "center",
                            color: tokens.frame.logoTint,
                            lineHeight: 0,
                            textDecoration: "none",
                        }}
                    >
                        <Box>
                            <EnteLogo height={22} />
                        </Box>
                        <Typography
                            component="span"
                            sx={{
                                fontFamily:
                                    '"Gochi Hand", "Comic Sans MS", "Bradley Hand", cursive',
                                fontSize: { xs: "1.92rem", md: "2.16rem" },
                                lineHeight: 1,
                                letterSpacing: "0.01em",
                                color: tokens.frame.logoTint,
                                mt: { xs: "2px", md: "3px" },
                            }}
                        >
                            paste
                        </Typography>
                    </Stack>
                    <Stack
                        direction="row"
                        spacing={0.85}
                        sx={{ alignItems: "center" }}
                    >
                        <IconButton
                            component="a"
                            href="https://github.com/ente/ente"
                            target="_blank"
                            rel="noopener noreferrer"
                            aria-label="View source on GitHub"
                            sx={{
                                width: 42,
                                height: 42,
                                bgcolor: "transparent",
                                color: tokens.frame.headerIcon,
                                "&:hover": {
                                    bgcolor: tokens.frame.headerIconHoverBg,
                                },
                            }}
                        >
                            <GitHubIcon sx={{ fontSize: 30 }} />
                        </IconButton>
                    </Stack>
                </Box>
                <Box
                    sx={{
                        width: "100%",
                        display: "flex",
                        alignItems: "center",
                        justifyContent: "center",
                        px: { xs: 3, md: 5 },
                        py: { xs: 2, md: 3 },
                    }}
                >
                    <Box sx={{ width: "100%", maxWidth: 700 }}>{children}</Box>
                </Box>
                <Box
                    sx={{
                        width: "100%",
                        maxWidth: 700,
                        mx: "auto",
                        px: { xs: 3, md: 5 },
                        pt: { xs: 2, md: 2.5 },
                        pb: { xs: 3, md: 3.25 },
                    }}
                >
                    {footer}
                </Box>
            </Box>
        </Box>
    );
};
