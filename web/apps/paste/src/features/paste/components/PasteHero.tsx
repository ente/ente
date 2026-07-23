import { usePasteColorMode } from "@/features/paste/hooks/usePasteColorMode";
import { getPasteThemeTokens } from "@/features/paste/theme/pasteThemeTokens";
import { Typography } from "@mui/material";

export const PasteHero = () => {
    const { resolvedMode } = usePasteColorMode();
    const tokens = getPasteThemeTokens(resolvedMode);

    return (
        <Typography
            sx={{
                fontSize: { xs: "2rem", md: "2.3rem" },
                lineHeight: 1.05,
                fontWeight: 700,
                color: tokens.text.primary,
            }}
        >
            Ente Paste
        </Typography>
    );
};
