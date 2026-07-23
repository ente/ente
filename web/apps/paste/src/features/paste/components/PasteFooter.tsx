import { usePasteColorMode } from "@/features/paste/hooks/usePasteColorMode";
import { getPasteThemeTokens } from "@/features/paste/theme/pasteThemeTokens";
import { Box, Stack, Typography } from "@mui/material";
import { EnteLogo } from "ente-base/components/EnteLogo";

const productLinkSx = (color: string, hoverColor: string) => ({
    color,
    fontWeight: 700,
    fontSize: { xs: "0.74rem", sm: "0.8rem" },
    letterSpacing: "0.03em",
    textDecoration: "underline",
    textDecorationColor: "currentColor",
    textUnderlineOffset: "3px",
    cursor: "pointer",
    whiteSpace: "nowrap",
    transition: "color 180ms ease, text-decoration-color 180ms ease",
    "&:hover": {
        color: hoverColor,
        textDecoration: "underline",
        textDecorationColor: hoverColor,
    },
});

export const PasteFooter = () => {
    const { resolvedMode } = usePasteColorMode();
    const tokens = getPasteThemeTokens(resolvedMode);

    return (
        <Stack spacing={1.1} sx={{ alignItems: "center" }}>
            <Box
                component="a"
                href="https://ente.com"
                target="_blank"
                rel="noopener"
                aria-label="Ente"
                sx={{
                    lineHeight: 0,
                    color: tokens.text.footer,
                    transition: "color 180ms ease",
                    "&:hover": { color: "#08C225" },
                }}
            >
                <EnteLogo height={26} />
            </Box>

            <Stack
                direction="row"
                spacing={1}
                sx={{
                    alignItems: "center",
                    justifyContent: "center",
                    flexWrap: "nowrap",
                }}
            >
                <Typography
                    component="a"
                    href="https://ente.com"
                    target="_blank"
                    rel="noopener"
                    sx={productLinkSx(tokens.text.footer, "#08C225")}
                >
                    Photos
                </Typography>
                <Box
                    component="span"
                    sx={{
                        width: 5,
                        height: 5,
                        borderRadius: "50%",
                        bgcolor: tokens.text.footerDot,
                    }}
                />
                <Typography
                    component="a"
                    href="https://ente.com/locker"
                    target="_blank"
                    rel="noopener"
                    sx={productLinkSx(tokens.text.footer, "#076AE2")}
                >
                    Documents
                </Typography>
                <Box
                    component="span"
                    sx={{
                        width: 5,
                        height: 5,
                        borderRadius: "50%",
                        bgcolor: tokens.text.footerDot,
                    }}
                />
                <Typography
                    component="a"
                    href="https://ente.com/auth"
                    target="_blank"
                    rel="noopener"
                    sx={productLinkSx(tokens.text.footer, "#A75CFF")}
                >
                    Auth Codes
                </Typography>
            </Stack>
        </Stack>
    );
};
