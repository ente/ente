import { ImageDelete02Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { Box } from "@mui/material";
import { SpacePostVideoBadge } from "components/PostPhotosBadge";
import type { SpacePostPreview } from "services/space";
import { spaceSurfaceHover, spaceTextMuted } from "styles/colors";

export const SpacePostPreviewThumbnail = ({
    post,
}: {
    post?: SpacePostPreview;
}) =>
    post?.imageUrl ? (
        <Box sx={{ position: "relative", width: 44, height: 44 }}>
            <Box
                component="img"
                alt=""
                src={post.imageUrl}
                sx={{
                    borderRadius: "20%",
                    display: "block",
                    height: "100%",
                    objectFit: "cover",
                    objectPosition: "center",
                    width: "100%",
                }}
            />
            <SpacePostVideoBadge durationMs={post.durationMs} />
        </Box>
    ) : (
        <Box
            aria-label={
                post?.isUnavailable
                    ? "Post image unavailable"
                    : post?.hasLoadError
                      ? "Couldn't load post image"
                      : "Loading post image"
            }
            role="img"
            sx={{
                alignItems: "center",
                bgcolor: spaceSurfaceHover,
                borderRadius: "20%",
                color: spaceTextMuted,
                display: "flex",
                height: 44,
                justifyContent: "center",
                width: 44,
            }}
        >
            {post?.isUnavailable && (
                <HugeiconsIcon
                    icon={ImageDelete02Icon}
                    size={18}
                    strokeWidth={1.5}
                />
            )}
        </Box>
    );
