import { Box } from "@mui/material";
import { SpaceAvatarImage } from "components/AvatarImage";
import React from "react";

interface SpacePostAvatarProps {
    plain?: boolean;
    ready: boolean;
    size: number;
    src?: string | null;
}

export const SpacePostAvatar: React.FC<SpacePostAvatarProps> = ({
    plain = false,
    ready,
    size,
    src,
}) => (
    <Box
        sx={{
            bgcolor: "rgba(255, 255, 255, 0.2)",
            borderRadius: "50%",
            flexShrink: 0,
            height: size,
            position: "relative",
            width: size,
        }}
    >
        {ready && (
            <Box
                key={src ?? "default-avatar"}
                sx={{
                    "@keyframes spaceAvatarFade": {
                        from: { opacity: 0 },
                        to: { opacity: 1 },
                    },
                    animation:
                        "spaceAvatarFade 320ms cubic-bezier(0.22, 1, 0.36, 1) both",
                    borderRadius: "50%",
                    height: "100%",
                    overflow: "hidden",
                    width: "100%",
                    "@media (prefers-reduced-motion: reduce)": {
                        animation: "none",
                    },
                }}
            >
                <SpaceAvatarImage src={src} borderRadius="50%" />
            </Box>
        )}
        {!plain && (
            <Box
                aria-hidden
                sx={{
                    border: "1px solid rgba(255, 255, 255, 0.16)",
                    borderRadius: "50%",
                    boxShadow: "0 1px 4px rgba(0, 0, 0, 0.24)",
                    inset: 0,
                    pointerEvents: "none",
                    position: "absolute",
                }}
            />
        )}
    </Box>
);
