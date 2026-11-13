import { Box } from "@mui/material";
import { visuallyHidden } from "@mui/utils";
import { spaceAppBackgroundColor, spaceText } from "styles/colors";

export const SpaceSkipLink = () => (
    <Box
        component="a"
        href="#space-main-content"
        onClick={(event) => {
            event.preventDefault();
            const content = document.getElementById("space-main-content");
            if (!content) return;

            content.focus({ preventScroll: true });
            const { top } = content.getBoundingClientRect();
            if (top < 0 || top >= window.innerHeight) {
                content.scrollIntoView({ block: "start" });
            }
        }}
        sx={{
            bgcolor: spaceText,
            borderRadius: "8px",
            boxShadow: "0 4px 16px #00000040",
            color: spaceAppBackgroundColor,
            fontFamily: '"Inter Variable", Inter, sans-serif',
            fontSize: 14,
            fontWeight: 600,
            left: "50%",
            p: "12px 16px",
            position: "fixed",
            textDecoration: "none",
            top: "calc(env(safe-area-inset-top) + 8px)",
            transform: "translateX(-50%)",
            whiteSpace: "nowrap",
            zIndex: 1200,
            "&:focus-visible": {
                outline: "2px solid #08C225",
                outlineOffset: 2,
            },
            "&:not(:focus)": visuallyHidden,
        }}
    >
        Skip to main content
    </Box>
);
