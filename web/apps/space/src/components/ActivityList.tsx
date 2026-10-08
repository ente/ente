import { Box } from "@mui/material";
import { SpaceAvatarImage } from "components/AvatarImage";
import { formatTimeAgo } from "ente-base/date";
import { useDecodedImage } from "hooks/use-decoded-image";
import type { ReactNode } from "react";
import { spaceTextMuted } from "styles/colors";

export const SpaceActivityAvatar = ({
    avatarUrl,
    loading = false,
    size,
}: {
    avatarUrl?: string | null;
    loading?: boolean;
    size: number;
}) => {
    const image = useDecodedImage(avatarUrl);
    return (
        <Box
            sx={{
                alignItems: "center",
                borderRadius: "50%",
                display: "flex",
                flexShrink: 0,
                height: size,
                justifyContent: "center",
                overflow: "hidden",
                width: size,
            }}
        >
            {!loading && image.ready && (
                <SpaceAvatarImage src={image.failed ? null : image.src} />
            )}
        </Box>
    );
};

export const SpaceActivityIdentity = ({
    name,
    createdAtMs,
}: {
    name: ReactNode;
    createdAtMs: number;
}) => (
    <Box
        sx={{ alignItems: "center", display: "flex", gap: "4px", minWidth: 0 }}
    >
        <Box
            sx={{
                flex: "0 1 auto",
                fontFamily: '"Inter Variable", Inter, sans-serif',
                fontSize: 14,
                fontWeight: 700,
                lineHeight: "20px",
                minWidth: 0,
                overflow: "hidden",
                textOverflow: "ellipsis",
                whiteSpace: "nowrap",
            }}
        >
            {name}
        </Box>
        <Box
            aria-hidden
            component="span"
            sx={{
                color: spaceTextMuted,
                flexShrink: 0,
                fontFamily: '"Inter Variable", Inter, sans-serif',
                fontSize: 12,
                fontWeight: 600,
                lineHeight: "16px",
            }}
        >
            &middot;
        </Box>
        <Box
            component="time"
            dateTime={new Date(createdAtMs).toISOString()}
            sx={{
                color: spaceTextMuted,
                flexShrink: 0,
                fontFamily: '"Inter Variable", Inter, sans-serif',
                fontSize: 12,
                fontWeight: 600,
                lineHeight: "16px",
                whiteSpace: "nowrap",
            }}
        >
            {formatTimeAgo(createdAtMs * 1000)}
        </Box>
    </Box>
);

export const SpaceActivitySection = ({
    title,
    children,
}: {
    title: string;
    children: ReactNode;
}) => (
    <Box component="section" sx={{ mb: "10px" }}>
        <Box
            component="h2"
            sx={{
                color: spaceTextMuted,
                fontFamily: '"Inter Variable", Inter, sans-serif',
                fontSize: 13,
                fontWeight: 700,
                lineHeight: "18px",
                m: 0,
                pb: "4px",
                pt: "12px",
            }}
        >
            {title}
        </Box>
        <Box component="ul" sx={{ listStyle: "none", m: 0, p: 0 }}>
            {children}
        </Box>
    </Box>
);
