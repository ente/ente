import { Box, Typography } from "@mui/material";

export default function BookBrand({
    showTitle = true,
    scale = 1,
}: {
    showTitle?: boolean;
    scale?: number;
}) {
    return (
        <Box sx={{ display: "flex", alignItems: "center", gap: scale }}>
            <Box
                component="img"
                src="/ente-branding.svg"
                alt="Ente"
                sx={{
                    display: "block",
                    height: {
                        xs: (showTitle ? 16 : 20) * scale,
                        sm: (showTitle ? 20 : 24) * scale,
                    },
                    width: "auto",
                    filter: "invert(1)",
                    "@media (max-width: 359px)": {
                        height: (showTitle ? 13 : 17) * scale,
                    },
                }}
            />
            {showTitle && (
                <Typography
                    sx={{
                        fontFamily: '"Gochi Hand", cursive',
                        fontSize: { xs: 24 * scale, sm: 32 * scale },
                        lineHeight: 1.2,
                        fontWeight: 400,
                        color: "#F2C14E",
                        transform: "translateY(1px)",
                        whiteSpace: "nowrap",
                        "@media (max-width: 359px)": { fontSize: 21 * scale },
                    }}
                >
                    photobook
                </Typography>
            )}
        </Box>
    );
}
