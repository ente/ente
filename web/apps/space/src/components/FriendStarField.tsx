import { Box } from "@mui/material";
import type { CSSProperties } from "react";

const stars = (() => {
    let seed = 7319;
    const random = () => {
        seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0;
        return seed / 4294967296;
    };
    return Array.from({ length: 64 }, () => {
        const brightness = random() ** 2;
        return {
            x: 2 + random() * 96,
            y: 2 + random() * 96,
            size: 1.2 + brightness * 1.6,
            low: 0.12 + brightness * 0.16,
            high: 0.35 + brightness * 0.65,
            duration: 4 + random() * 7,
            delay: -random() * 20,
        };
    });
})();

export const FriendStarField = () => (
    <Box
        aria-hidden
        sx={{
            inset: 0,
            overflow: "hidden",
            pointerEvents: "none",
            position: "absolute",
            zIndex: -1,
            "& > span": {
                animation: "spaceStarTwinkle ease-in-out infinite",
                bgcolor: "#FFFFFF",
                borderRadius: "50%",
                opacity: "var(--star-high)",
                position: "absolute",
            },
            "@keyframes spaceStarTwinkle": {
                "0%, 100%": { opacity: "var(--star-low)" },
                "40%": { opacity: "var(--star-high)" },
            },
            "@media (prefers-reduced-motion: reduce)": {
                "& > span": { animation: "none" },
            },
        }}
    >
        {stars.map((star, index) => (
            <span
                key={index}
                style={
                    {
                        "--star-low": star.low,
                        "--star-high": star.high,
                        animationDelay: `${star.delay}s`,
                        animationDuration: `${star.duration}s`,
                        boxShadow:
                            star.high > 0.8
                                ? "0 0 4px 1px #ffffff30"
                                : undefined,
                        height: star.size,
                        left: `${star.x}%`,
                        top: `${star.y}%`,
                        width: star.size,
                    } as CSSProperties
                }
            />
        ))}
    </Box>
);
