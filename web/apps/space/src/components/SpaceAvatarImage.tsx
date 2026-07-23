import { Box } from "@mui/material";
import React from "react";

export const spaceDefaultProfilePicPath = "/images/default-profile-pic.png";

const avatarImageSx = {
    display: "block",
    height: "100%",
    objectFit: "cover",
    objectPosition: "center",
    width: "100%",
} as const;

interface SpaceAvatarImageProps {
    alt?: string;
    "aria-hidden"?: boolean;
    border?: string;
    borderRadius?: string | number;
    src?: string | null;
}

export const SpaceAvatarImage: React.FC<SpaceAvatarImageProps> = ({
    alt = "",
    "aria-hidden": ariaHidden,
    border,
    borderRadius,
    src,
}) => (
    <Box
        component="img"
        alt={alt}
        aria-hidden={ariaHidden}
        src={src || spaceDefaultProfilePicPath}
        sx={{
            ...avatarImageSx,
            ...(border ? { border } : {}),
            ...(borderRadius !== undefined ? { borderRadius } : {}),
        }}
    />
);
