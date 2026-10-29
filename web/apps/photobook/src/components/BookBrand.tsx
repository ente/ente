import { Box, Typography } from "@mui/material";

export default function BookBrand({
    showTitle = true,
}: {
    showTitle?: boolean;
}) {
    return (
        <Box sx={{ display: "flex", alignItems: "center", gap: 1 }}>
            <Box
                component="img"
                src="/ente-branding.svg"
                alt="Ente"
                sx={{
                    display: "block",
                    height: {
                        xs: showTitle ? 16 : 20,
                        sm: showTitle ? 20 : 24,
                    },
                    width: "auto",
                    filter: "invert(1)",
                    "@media (max-width: 359px)": {
                        height: showTitle ? 13 : 17,
                    },
                }}
            />
            {showTitle && (
                <Typography
                    sx={{
                        fontFamily: '"Gochi Hand", cursive',
                        fontSize: { xs: 24, sm: 32 },
                        lineHeight: 1.2,
                        fontWeight: 400,
                        color: "#F2C14E",
                        transform: "translateY(1px)",
                        whiteSpace: "nowrap",
                        "@media (max-width: 359px)": { fontSize: 21 },
                    }}
                >
                    photobook
                </Typography>
            )}
        </Box>
    );
}
