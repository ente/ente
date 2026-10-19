import { Box, Stack, Typography } from "@mui/material";
import { t } from "i18next";

export function AlbumEmptyState() {
    return (
        <Stack
            sx={{
                alignItems: "center",
                gap: "30.31px",
                width: "100%",
                minWidth: 0,
                px: { xs: 0, sm: 3 },
                py: 3,
            }}
        >
            <Box
                aria-hidden
                sx={{
                    position: "relative",
                    width: "100%",
                    maxWidth: 265.209,
                    aspectRatio: "265.209 / 215.196",
                }}
            >
                <Box
                    component="img"
                    src="/images/empty-album/background.svg"
                    alt=""
                    sx={{
                        position: "absolute",
                        left: "-2.0305%",
                        top: "5.0024%",
                        width: "104.061%",
                        height: "auto",
                    }}
                />
                <Box
                    component="img"
                    src="/images/empty-album/duck.svg"
                    alt=""
                    sx={{
                        position: "absolute",
                        left: "8.1219%",
                        top: "10.79%",
                        width: "81.3604%",
                        height: "auto",
                    }}
                />
            </Box>
            <Typography
                sx={{
                    fontFamily: "'Outfit Variable', sans-serif",
                    fontWeight: 600,
                    fontSize: { xs: 28, sm: "36.372px" },
                    lineHeight: "1.333333",
                    color: "text.base",
                    textAlign: "center",
                }}
            >
                {t("nothing_to_see_here")}
            </Typography>
        </Stack>
    );
}
