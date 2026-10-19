import { Box } from "@mui/material";
import type { Theme } from "@mui/material/styles";

const SECONDARY_ACTION_BG_LIGHT = "#F2F2F2";
const SECONDARY_ACTION_BG_DARK = "rgba(255, 255, 255, 0.08)";
const ILLUSTRATION_ICON_LIGHT = "#111";
const ILLUSTRATION_ICON_DARK = "#fff";

const illustrationSvgSx = (theme: Theme) => ({
    "--app-lock-illustration-fill": SECONDARY_ACTION_BG_LIGHT,
    "--app-lock-illustration-icon": ILLUSTRATION_ICON_LIGHT,
    ...theme.applyStyles("dark", {
        "--app-lock-illustration-fill": SECONDARY_ACTION_BG_DARK,
        "--app-lock-illustration-icon": ILLUSTRATION_ICON_DARK,
    }),
});

const LOCK_ILLUSTRATION_SRC = new URL("./lock.svg", import.meta.url).toString();

export const LockIllustration = () => (
    <Box
        component="img"
        src={LOCK_ILLUSTRATION_SRC}
        alt=""
        aria-hidden
        draggable={false}
        sx={{
            width: 124,
            maxWidth: "100%",
            height: "auto",
            display: "block",
            lineHeight: 0,
            userSelect: "none",
        }}
    />
);

export const LogoutIllustration = () => (
    <Box sx={illustrationSvgSx}>
        <svg
            width="126"
            height="121"
            viewBox="0 0 126 121"
            fill="none"
            xmlns="http://www.w3.org/2000/svg"
            aria-hidden
        >
            <circle
                cx="67"
                cy="52"
                r="34"
                fill="var(--app-lock-illustration-fill)"
            />
            <g
                transform="translate(67 52) scale(1.18) translate(-12 -12)"
                stroke="var(--app-lock-illustration-icon)"
                fill="none"
                strokeWidth="1.6"
                strokeLinecap="round"
                strokeLinejoin="round"
            >
                <path d="M7.86907 4C4.97674 5.49689 3 8.51664 3 11.9981C3 16.9686 7.02944 20.9981 12 20.9981C16.9706 20.9981 21 16.9686 21 11.9981C21 8.51664 19.0233 5.49689 16.1309 4" />
                <path d="M12 3V10" />
            </g>
        </svg>
    </Box>
);

export const CooldownIllustration = () => (
    <Box sx={illustrationSvgSx}>
        <svg
            width="126"
            height="121"
            viewBox="0 0 126 121"
            fill="none"
            xmlns="http://www.w3.org/2000/svg"
            aria-hidden
        >
            <circle
                cx="67"
                cy="52"
                r="34"
                fill="var(--app-lock-illustration-fill)"
            />
            <g
                transform="translate(67 52) scale(1.18) translate(-12 -12)"
                stroke="var(--app-lock-illustration-icon)"
                fill="none"
                strokeWidth="2"
                strokeLinecap="round"
                strokeLinejoin="round"
            >
                <path d="M12 22C6.47714 22 2.00003 17.5228 2.00003 12C2.00003 6.47715 6.47718 2 12 2C16.4777 2 20.2257 4.94289 21.5 9H19" />
                <path d="M12 8V12L14 14" />
                <path d="M21.9551 13C21.9848 12.6709 22 12.3373 22 12M15 22C15.3416 21.8876 15.6753 21.7564 16 21.6078M20.7906 17C20.9835 16.6284 21.1555 16.2433 21.305 15.8462M18.1925 20.2292C18.5369 19.9441 18.8631 19.6358 19.1688 19.3065" />
            </g>
        </svg>
    </Box>
);
