import { Add01Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { Box, Fade, Skeleton } from "@mui/material";
import { SpaceAvatarImage } from "components/AvatarImage";
import log from "ente-base/log";
import React from "react";
import type { SetupProfile } from "screens/SetupProfileScreen";
import type { SpacePost, SpacePostAssetURLLoader } from "services/space";
import { useSpaceAppState, type SpacePostPublishPhase } from "state/app-state";
import {
    spaceAppBackground,
    spaceSurface,
    spaceTextMuted,
} from "styles/colors";
import {
    spacePostTileRadius,
    spaceTileCircleInset,
    spaceTileCornerStyles,
} from "styles/tiles";
import { spaceDefaultCoverImagePath } from "utils/post-image";
import { thumbHashDataURLFromBase64 } from "utils/thumbhash";

const green = "#08C225";
const actionSize = 64;

const PostStatus: React.FC<{
    phase: SpacePostPublishPhase;
    expiresAtMs?: number;
}> = ({ phase, expiresAtMs }) => {
    const [dotCount, setDotCount] = React.useState(1);
    const [isVisible, setIsVisible] = React.useState(
        () => !expiresAtMs || expiresAtMs > Date.now(),
    );

    React.useEffect(() => {
        setIsVisible(!expiresAtMs || expiresAtMs > Date.now());
        if (!expiresAtMs) return;

        const timeoutID = window.setTimeout(
            () => setIsVisible(false),
            Math.max(0, expiresAtMs - Date.now()),
        );
        return () => window.clearTimeout(timeoutID);
    }, [expiresAtMs]);

    React.useEffect(() => {
        if (phase != "posting") return;

        setDotCount(1);
        const intervalID = window.setInterval(() => {
            setDotCount((count) => (count % 3) + 1);
        }, 500);
        return () => window.clearInterval(intervalID);
    }, [phase]);

    const label =
        phase == "posting"
            ? "Posting"
            : phase == "posted"
              ? "Posted"
              : "Failed";

    return (
        <Fade in={isVisible} appear={false} timeout={200} unmountOnExit>
            <Box
                role="status"
                aria-label={label}
                sx={{
                    bgcolor:
                        phase == "posted"
                            ? green
                            : phase == "failed"
                              ? "#F63A3A"
                              : "rgba(0, 0, 0, 0.64)",
                    borderRadius: "999px",
                    color: "#FFFFFF",
                    display: "inline-flex",
                    fontSize: 12,
                    fontWeight: 500,
                    left: "var(--space-tile-padding)",
                    lineHeight: "16px",
                    pointerEvents: "none",
                    position: "absolute",
                    px: "10px",
                    py: "4px",
                    top: "var(--space-tile-padding)",
                    whiteSpace: "nowrap",
                }}
            >
                {label}
                {phase == "posting" && (
                    <Box component="span" aria-hidden sx={{ width: 12 }}>
                        {".".repeat(dotCount)}
                    </Box>
                )}
            </Box>
        </Fade>
    );
};

interface SpaceOwnPostTileProps {
    profile: SetupProfile | null;
    post?: SpacePost;
    avatarSize?: number;
    isLoading?: boolean;
    isUnavailable?: boolean;
    isNewPostDisabled?: boolean;
    onLoadPostImage?: SpacePostAssetURLLoader;
    onOpenPost?: (imageUrl: string) => void;
    onOpenProfile?: () => void;
    onNewPost: () => void;
}

export const SpaceOwnPostTile: React.FC<SpaceOwnPostTileProps> = ({
    profile,
    post,
    avatarSize = 36,
    isLoading = false,
    isUnavailable = false,
    isNewPostDisabled = false,
    onLoadPostImage,
    onOpenPost,
    onOpenProfile,
    onNewPost,
}) => {
    const { cachedProfileAvatarUrl, postPublication } = useSpaceAppState();
    const tileRef = React.useRef<HTMLElement>(null);
    const publishPhase =
        postPublication?.post == post ? postPublication?.phase : undefined;
    const hasPublication = Boolean(publishPhase);
    const avatarUrl = profile ? profile.avatarUrl : cachedProfileAvatarUrl;
    const isAvatarLoading =
        !avatarUrl && (!profile || Boolean(profile.avatarObjectID));
    const [loadedImage, setLoadedImage] = React.useState<{
        post: SpacePost;
        url?: string;
        failed?: boolean;
    }>();
    const postImage = loadedImage?.post == post ? loadedImage : undefined;
    const imageUrl = post?.imageUrl ?? postImage?.url;
    const thumbHashDataURL = React.useMemo(
        () => thumbHashDataURLFromBase64(post?.thumbHash),
        [post?.thumbHash],
    );
    const unavailable =
        isUnavailable || post?.isUnavailable || postImage?.failed;
    const canOpenPost = Boolean(
        imageUrl &&
        !unavailable &&
        onOpenPost &&
        (!publishPhase || publishPhase == "posted"),
    );
    const loading =
        isLoading || Boolean(post?.imageAsset && !imageUrl && !unavailable);
    const isEmpty = !post && !loading && !unavailable;
    const coverUrl = isEmpty ? spaceDefaultCoverImagePath : imageUrl;

    React.useEffect(() => {
        if (hasPublication)
            tileRef.current?.scrollIntoView({ block: "nearest" });
    }, [hasPublication]);

    React.useEffect(() => {
        if (!post?.imageAsset || post.imageUrl || !onLoadPostImage) return;

        let cancelled = false;
        void onLoadPostImage(post.imageAsset)
            .then((url) => {
                if (!cancelled) setLoadedImage({ post, url });
            })
            .catch((error: unknown) => {
                log.warn("Failed to load own latest post image", error);
                if (!cancelled) setLoadedImage({ post, failed: true });
            });
        return () => {
            cancelled = true;
        };
    }, [onLoadPostImage, post]);

    return (
        <Box
            ref={tileRef}
            component="section"
            aria-label="Your latest post"
            sx={{
                ...spaceTileCornerStyles(spacePostTileRadius),
                aspectRatio: "1.7",
                bgcolor: unavailable ? spaceSurface : "transparent",
                flexShrink: 0,
                fontFamily: '"Inter Variable", Inter, sans-serif',
                overflow: "hidden",
                position: "relative",
                width: "100%",
                "& button:focus-visible": {
                    outline: `2px solid ${green}`,
                    outlineOffset: -4,
                },
            }}
        >
            <Box
                component="button"
                type="button"
                aria-label="Open your posts"
                disabled={!canOpenPost}
                onClick={() => imageUrl && onOpenPost?.(imageUrl)}
                sx={{
                    appearance: "none",
                    bgcolor: "transparent",
                    border: 0,
                    borderRadius: "inherit",
                    color: spaceTextMuted,
                    cursor: canOpenPost ? "pointer" : "default",
                    font: "inherit",
                    inset: 0,
                    p: 0,
                    position: "absolute",
                    width: "100%",
                }}
            >
                {(coverUrl || thumbHashDataURL) && !unavailable ? (
                    <>
                        {thumbHashDataURL && (
                            <Box
                                component="img"
                                alt=""
                                aria-hidden
                                src={thumbHashDataURL}
                                sx={{
                                    filter: "blur(14px)",
                                    height: "100%",
                                    inset: 0,
                                    objectFit: "cover",
                                    position: "absolute",
                                    transform: "scale(1.08)",
                                    width: "100%",
                                }}
                            />
                        )}
                        {coverUrl && (
                            <Box
                                component="img"
                                alt={
                                    isEmpty
                                        ? ""
                                        : post?.caption || "Your latest post"
                                }
                                src={coverUrl}
                                onError={() =>
                                    post &&
                                    setLoadedImage({ post, failed: true })
                                }
                                sx={{
                                    display: "block",
                                    height: "100%",
                                    objectFit: "cover",
                                    position: "relative",
                                    width: "100%",
                                }}
                            />
                        )}
                    </>
                ) : !loading ? (
                    <Box
                        sx={{
                            fontSize: 15,
                            pb: "56px",
                            px: "var(--space-tile-padding)",
                        }}
                    >
                        Couldn&apos;t load your latest post
                    </Box>
                ) : null}
                {isEmpty && (
                    <Box
                        sx={{
                            alignItems: "center",
                            bgcolor: "rgba(0, 0, 0, 0.18)",
                            display: "flex",
                            flexDirection: "column",
                            gap: "6px",
                            inset: 0,
                            justifyContent: "center",
                            position: "absolute",
                            px: "var(--space-tile-padding)",
                            textAlign: "center",
                        }}
                    >
                        <Box
                            component="span"
                            sx={{
                                bgcolor: "rgba(249, 252, 239, 0.94)",
                                borderRadius: "999px",
                                color: "#24351B",
                                fontSize: 12,
                                fontWeight: 600,
                                lineHeight: "18px",
                                px: "12px",
                                py: "3px",
                            }}
                        >
                            Your latest post will show up here
                        </Box>
                        <Box
                            component="span"
                            sx={{
                                backdropFilter: "blur(12px)",
                                bgcolor: "rgba(28, 28, 30, 0.48)",
                                borderRadius: "999px",
                                color: "#E3E7DA",
                                fontSize: 12,
                                fontWeight: 500,
                                lineHeight: "18px",
                                px: "10px",
                                py: "3px",
                            }}
                        >
                            Share a little moment from your day!
                        </Box>
                    </Box>
                )}
            </Box>
            <Box
                sx={{
                    bottom: 0,
                    height: "50%",
                    left: 0,
                    pointerEvents: "none",
                    position: "absolute",
                    right: 0,
                }}
            >
                <Box
                    component="button"
                    type="button"
                    aria-label="Open your profile"
                    onClick={onOpenProfile}
                    sx={{
                        alignItems: "center",
                        appearance: "none",
                        bgcolor: "transparent",
                        border: 0,
                        borderRadius: "50%",
                        bottom: spaceTileCircleInset(avatarSize),
                        cursor: onOpenProfile ? "pointer" : "default",
                        display: "flex",
                        height: avatarSize,
                        justifyContent: "center",
                        left: spaceTileCircleInset(avatarSize),
                        p: 0,
                        pointerEvents: "auto",
                        position: "absolute",
                        width: avatarSize,
                    }}
                >
                    <Box
                        sx={{
                            backgroundClip: "padding-box",
                            bgcolor: spaceAppBackground,
                            border: "3px solid rgba(28, 28, 30, 0.75)",
                            borderRadius: "50%",
                            boxSizing: "border-box",
                            flexShrink: 0,
                            height: avatarSize,
                            overflow: "hidden",
                            width: avatarSize,
                        }}
                    >
                        {isAvatarLoading ? (
                            <Skeleton
                                variant="circular"
                                sx={{
                                    bgcolor: spaceSurface,
                                    height: "100%",
                                    width: "100%",
                                }}
                            />
                        ) : (
                            <SpaceAvatarImage src={avatarUrl} />
                        )}
                    </Box>
                </Box>
                <Box
                    className="green-bg"
                    component="button"
                    type="button"
                    aria-label="New post"
                    disabled={isNewPostDisabled}
                    onClick={onNewPost}
                    sx={{
                        alignItems: "center",
                        appearance: "none",
                        bgcolor: green,
                        border: 0,
                        borderRadius: "50%",
                        bottom: spaceTileCircleInset(actionSize),
                        boxShadow: "0 4px 12px rgba(0, 0, 0, 0.32)",
                        color: "#FFFFFF",
                        cursor: isNewPostDisabled ? "default" : "pointer",
                        display: "flex",
                        height: actionSize,
                        justifyContent: "center",
                        opacity: isNewPostDisabled ? 0.6 : 1,
                        p: 0,
                        pointerEvents: "auto",
                        position: "absolute",
                        right: spaceTileCircleInset(actionSize),
                        width: actionSize,
                        "&:hover": { bgcolor: "#07B422" },
                        "&:focus-visible": { outlineColor: "#FFFFFF" },
                    }}
                >
                    <HugeiconsIcon icon={Add01Icon} size={32} strokeWidth={2} />
                </Box>
            </Box>
            {publishPhase && (
                <PostStatus
                    phase={publishPhase}
                    expiresAtMs={postPublication?.statusExpiresAtMs}
                />
            )}
        </Box>
    );
};
