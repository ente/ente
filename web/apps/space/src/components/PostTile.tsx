import { Box } from "@mui/material";
import { SpacePostAvatar } from "components/PostAvatar";
import {
    SpacePostPhotosBadge,
    SpacePostVideoBadge,
} from "components/PostPhotosBadge";
import log from "ente-base/log";
import { useDecodedImage } from "hooks/use-decoded-image";
import React from "react";
import type { SpacePostAsset, SpacePostPhoto } from "services/space";
import { spaceSurface, spaceTextMuted } from "styles/colors";
import { spaceProfilePostRadius } from "styles/tiles";
import { spaceTouchTargetSize } from "styles/touch-targets";
import { thumbHashDataURLFromBase64 } from "utils/thumbhash";

const green = "#08C225";

export interface SpacePostTileItem {
    avatarUrl?: string | null;
    caption?: string;
    friendID?: string;
    height?: number;
    id: string;
    imageAsset?: SpacePostAsset;
    imageUrl?: string;
    photos?: SpacePostPhoto[];
    isUnavailable?: boolean;
    name?: string;
    postId?: number;
    spaceId?: string;
    timestampMs: number;
    thumbHash?: string;
    viewerLiked?: boolean;
    width?: number;
}

interface SpacePostTileProps {
    displayName: string;
    showAvatar?: boolean;
    subtlePhotosBadge?: boolean;
    onLoadAvatar?: () => Promise<string | null>;
    imageUrl?: string;
    index: number;
    isAvatarPending?: boolean;
    isUnavailable: boolean;
    item: SpacePostTileItem;
    loadRootMargin: string;
    onImageDecodeError: () => void;
    onLoadImage: () => Promise<string | undefined>;
    onOpen: (imageUrl: string) => void;
    onOpenProfile?: () => void;
    onRememberDimensions?: (itemID: string, image: HTMLImageElement) => void;
}

export const SpacePostTile: React.FC<SpacePostTileProps> = ({
    displayName,
    showAvatar = false,
    subtlePhotosBadge,
    onLoadAvatar,
    imageUrl,
    index,
    isAvatarPending = false,
    isUnavailable: isPostUnavailable,
    item,
    loadRootMargin,
    onImageDecodeError,
    onLoadImage,
    onOpen,
    onOpenProfile,
    onRememberDimensions,
}) => {
    const [shouldLoad, setShouldLoad] = React.useState(Boolean(imageUrl));
    const [readyImageUrl, setReadyImageUrl] = React.useState<string>();
    const [imageDecodeFailed, setImageDecodeFailed] = React.useState(false);
    const decodedAvatar = useDecodedImage(
        showAvatar ? item.avatarUrl : undefined,
        true,
    );
    const tileRef = React.useRef<HTMLButtonElement | null>(null);
    const thumbHashDataURL = React.useMemo(
        () => thumbHashDataURLFromBase64(item.thumbHash),
        [item.thumbHash],
    );
    const isCurrentImageReady = Boolean(imageUrl && readyImageUrl == imageUrl);
    const isUnavailable = isPostUnavailable || imageDecodeFailed;
    const photoCount = item.photos?.length ?? 1;

    React.useEffect(() => {
        if (imageUrl) setShouldLoad(true);
    }, [imageUrl]);

    React.useEffect(() => {
        if (isUnavailable) return;
        if (shouldLoad || imageUrl) return;
        const element = tileRef.current;
        if (!element) return;
        if (
            typeof window == "undefined" ||
            !("IntersectionObserver" in window)
        ) {
            setShouldLoad(true);
            return;
        }

        const observer = new IntersectionObserver(
            (entries) => {
                if (entries.some((entry) => entry.isIntersecting)) {
                    setShouldLoad(true);
                    observer.disconnect();
                }
            },
            { rootMargin: loadRootMargin },
        );
        observer.observe(element);
        return () => observer.disconnect();
    }, [imageUrl, isUnavailable, loadRootMargin, shouldLoad]);

    React.useEffect(() => {
        if (isUnavailable) return;
        if (!shouldLoad || imageUrl) return;
        void onLoadImage().catch((error: unknown) => {
            log.warn("Failed to load profile post image", error);
        });
    }, [imageUrl, isUnavailable, onLoadImage, shouldLoad]);

    React.useEffect(() => {
        if (shouldLoad && !isUnavailable) void onLoadAvatar?.();
    }, [isUnavailable, onLoadAvatar, shouldLoad]);

    return (
        <Box
            sx={{
                bgcolor: spaceSurface,
                borderRadius: `${spaceProfilePostRadius}px`,
                height: "100%",
                minWidth: 0,
                overflow: "hidden",
                position: "relative",
            }}
        >
            <Box
                ref={tileRef}
                component="button"
                type="button"
                aria-label={
                    isUnavailable
                        ? "Post unavailable"
                        : `Open ${displayName} post ${index + 1}${
                              photoCount > 1 ? `, ${photoCount} photos` : ""
                          }`
                }
                disabled={!imageUrl || isUnavailable}
                onClick={() => {
                    if (imageUrl && !isUnavailable) onOpen(imageUrl);
                }}
                sx={{
                    appearance: "none",
                    bgcolor: spaceSurface,
                    border: 0,
                    borderRadius: "inherit",
                    cursor: imageUrl && !isUnavailable ? "pointer" : "default",
                    display: "block",
                    height: "100%",
                    minWidth: 0,
                    opacity: 1,
                    overflow: "hidden",
                    p: 0,
                    position: "relative",
                    width: "100%",
                    "&:focus-visible": {
                        outline: `2px solid ${green}`,
                        outlineOffset: -2,
                    },
                }}
            >
                {!isUnavailable && thumbHashDataURL ? (
                    <Box
                        component="img"
                        alt=""
                        aria-hidden
                        src={thumbHashDataURL}
                        sx={{
                            display: "block",
                            filter: "blur(14px)",
                            height: "100%",
                            inset: 0,
                            objectFit: "cover",
                            objectPosition: "center",
                            position: "absolute",
                            transform: "scale(1.08)",
                            width: "100%",
                        }}
                    />
                ) : null}
                {!isUnavailable && imageUrl ? (
                    <Box
                        component="img"
                        alt={`${displayName} post ${index + 1}`}
                        onLoad={(event) => {
                            setReadyImageUrl(imageUrl);
                            onRememberDimensions?.(
                                item.id,
                                event.currentTarget,
                            );
                        }}
                        onError={() => {
                            log.warn(
                                `Post ${item.postId} is unavailable because the browser could not decode its image`,
                            );
                            setImageDecodeFailed(true);
                            onImageDecodeError();
                        }}
                        src={imageUrl}
                        sx={{
                            display: "block",
                            height: "100%",
                            inset: 0,
                            objectFit: "cover",
                            objectPosition: "center",
                            opacity:
                                isCurrentImageReady || !thumbHashDataURL
                                    ? 1
                                    : 0,
                            position: "absolute",
                            transition: thumbHashDataURL
                                ? "opacity 220ms ease"
                                : "none",
                            width: "100%",
                            "@media (prefers-reduced-motion: reduce)": {
                                opacity: 1,
                                transition: "none",
                            },
                        }}
                    />
                ) : null}
                {!isUnavailable && (
                    <>
                        <SpacePostPhotosBadge
                            count={photoCount}
                            inset={8}
                            subtle={subtlePhotosBadge}
                        />
                        <SpacePostVideoBadge
                            durationMs={item.photos?.[0]?.video?.durationMs}
                            size={18}
                        />
                    </>
                )}
                {isUnavailable && (
                    <Box
                        sx={{
                            alignItems: "center",
                            color: spaceTextMuted,
                            display: "flex",
                            fontSize: 12,
                            fontWeight: 600,
                            height: "100%",
                            justifyContent: "center",
                            width: "100%",
                        }}
                    >
                        Post unavailable
                    </Box>
                )}
            </Box>
            {showAvatar && (
                <Box
                    component="button"
                    type="button"
                    aria-label={`Open ${displayName}'s profile`}
                    disabled={!onOpenProfile}
                    onClick={onOpenProfile}
                    sx={{
                        alignItems: "flex-end",
                        appearance: "none",
                        bgcolor: "transparent",
                        border: 0,
                        borderRadius: "50%",
                        bottom: 0,
                        cursor: onOpenProfile ? "pointer" : "default",
                        display: "flex",
                        height: spaceTouchTargetSize,
                        left: 0,
                        p: "0 0 8px 8px",
                        position: "absolute",
                        width: spaceTouchTargetSize,
                        "&:focus-visible": {
                            outline: `2px solid ${green}`,
                            outlineOffset: -2,
                        },
                    }}
                >
                    <SpacePostAvatar
                        outerRing
                        ready={!isAvatarPending && decodedAvatar.ready}
                        size={26}
                        src={
                            decodedAvatar.failed ? undefined : decodedAvatar.src
                        }
                    />
                </Box>
            )}
        </Box>
    );
};
