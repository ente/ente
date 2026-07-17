import { ArrowLeft02Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { Box, Skeleton } from "@mui/material";
import { spaceAppAvatarCropSize } from "components/SpaceAvatarCropPage";
import { SpaceAvatarImage } from "components/SpaceAvatarImage";
import React, { useRef } from "react";
import type { SetupProfile } from "screens/SetupProfileScreen";
import { spaceTouchTargetSize } from "styles/touchTargets";
import {
    spaceAvatarImageInputAccept,
    spaceCoverImageInputAccept,
    spaceDefaultCoverImagePath,
    spaceProfileCoverAspectRatio,
} from "utils/spacePostImage";

const green = "#08C225";
const textBase = "#000";
const profileBackground = "#FFFFFF";
const profileCoverBackground = "#1F1F1F";
const profileAvatarSkeletonBackground = "#E6E6E6";

interface ProfileImageViewerScreenProps {
    onBack: () => void;
    onSelectFile: (file: File) => void;
    profile: SetupProfile;
    variant: "avatar" | "cover";
}

export const ProfileImageViewerScreen: React.FC<
    ProfileImageViewerScreenProps
> = ({ onBack, onSelectFile, profile, variant }) => {
    const inputRef = useRef<HTMLInputElement | null>(null);
    const isCover = variant == "cover";
    const title = isCover ? "Cover image" : "Profile picture";
    const actionLabel = isCover
        ? "Change cover image"
        : "Change profile picture";
    const imageUrl = isCover ? profile.coverUrl : profile.avatarUrl;
    const isCoverURLPending = isCover && Boolean(profile.coverObjectID);
    const isAvatarURLPending =
        !isCover && Boolean(profile.avatarObjectID) && !imageUrl;
    const displayImageUrl =
        isCover && !imageUrl
            ? isCoverURLPending
                ? undefined
                : spaceDefaultCoverImagePath
            : imageUrl;

    const handleFileSelect: React.ChangeEventHandler<HTMLInputElement> = (
        event,
    ) => {
        const file = event.target.files?.[0];
        event.target.value = "";
        if (file) onSelectFile(file);
    };

    return (
        <Box
            component="main"
            sx={{
                bgcolor: profileBackground,
                color: textBase,
                display: "grid",
                minHeight: "100svh",
                overflowX: "hidden",
                placeItems: { xs: "stretch", sm: "start center" },
            }}
        >
            <Box
                sx={{
                    bgcolor: profileBackground,
                    boxSizing: "border-box",
                    display: "grid",
                    gridTemplateRows: "56px minmax(0, 1fr) auto",
                    minHeight: "100svh",
                    mx: "auto",
                    width: "100%",
                    "@media (min-width: 600px)": { maxWidth: 390 },
                }}
            >
                <Box
                    ref={inputRef}
                    component="input"
                    type="file"
                    accept={
                        isCover
                            ? spaceCoverImageInputAccept
                            : spaceAvatarImageInputAccept
                    }
                    onChange={handleFileSelect}
                    sx={{ display: "none" }}
                />
                <Box
                    component="header"
                    sx={{
                        alignItems: "center",
                        display: "grid",
                        gridTemplateColumns: `${spaceTouchTargetSize}px 1fr ${spaceTouchTargetSize}px`,
                        height: 56,
                        px: 2,
                        width: "100%",
                    }}
                >
                    <Box
                        component="button"
                        type="button"
                        aria-label="Back to profile"
                        onClick={onBack}
                        sx={{
                            alignItems: "center",
                            bgcolor: "transparent",
                            border: 0,
                            color: textBase,
                            cursor: "pointer",
                            display: "flex",
                            height: spaceTouchTargetSize,
                            justifyContent: "flex-start",
                            ml: "-2px",
                            p: 0,
                            width: spaceTouchTargetSize,
                            "&:focus-visible": {
                                borderRadius: "50%",
                                outline: `2px solid ${green}`,
                                outlineOffset: 2,
                            },
                        }}
                    >
                        <HugeiconsIcon
                            icon={ArrowLeft02Icon}
                            size={24}
                            strokeWidth={1.8}
                        />
                    </Box>
                    <Box
                        component="h1"
                        sx={{
                            color: textBase,
                            fontFamily: '"Inter Variable", Inter, sans-serif',
                            fontSize: 18,
                            fontWeight: 700,
                            justifySelf: "center",
                            lineHeight: "24px",
                            m: 0,
                        }}
                    >
                        {title}
                    </Box>
                    <Box />
                </Box>

                <Box
                    sx={{
                        alignItems: "center",
                        boxSizing: "border-box",
                        display: "flex",
                        justifyContent: "center",
                        minHeight: 0,
                        px: isCover ? 0 : 3,
                    }}
                >
                    {isCover ? (
                        <Box
                            sx={{
                                aspectRatio: `${spaceProfileCoverAspectRatio} / 1`,
                                bgcolor: profileCoverBackground,
                                overflow: "hidden",
                                width: "100%",
                            }}
                        >
                            {displayImageUrl ? (
                                <Box
                                    component="img"
                                    alt=""
                                    src={displayImageUrl}
                                    sx={{
                                        display: "block",
                                        height: "100%",
                                        objectFit: "cover",
                                        objectPosition: "center",
                                        width: "100%",
                                    }}
                                />
                            ) : (
                                <Skeleton
                                    variant="rectangular"
                                    sx={{
                                        bgcolor:
                                            profileAvatarSkeletonBackground,
                                        display: "block",
                                        height: "100%",
                                        transform: "none",
                                        width: "100%",
                                    }}
                                />
                            )}
                        </Box>
                    ) : (
                        <Box
                            sx={{
                                alignItems: "center",
                                aspectRatio: "1 / 1",
                                bgcolor: profileAvatarSkeletonBackground,
                                borderRadius: "50%",
                                display: "flex",
                                justifyContent: "center",
                                overflow: "hidden",
                                width: spaceAppAvatarCropSize,
                            }}
                        >
                            {isAvatarURLPending ? (
                                <Skeleton
                                    variant="circular"
                                    sx={{
                                        bgcolor:
                                            profileAvatarSkeletonBackground,
                                        height: "100%",
                                        transform: "none",
                                        width: "100%",
                                    }}
                                />
                            ) : (
                                <SpaceAvatarImage src={displayImageUrl} />
                            )}
                        </Box>
                    )}
                </Box>

                <Box
                    sx={{
                        boxSizing: "border-box",
                        pb: "calc(24px + env(safe-area-inset-bottom))",
                        px: 3,
                        pt: 3,
                    }}
                >
                    <Box
                        className="green-bg"
                        component="button"
                        type="button"
                        onClick={() => inputRef.current?.click()}
                        sx={{
                            alignItems: "center",
                            bgcolor: green,
                            border: 0,
                            borderRadius: "20px",
                            color: "white",
                            cursor: "pointer",
                            display: "flex",
                            fontFamily: '"Inter Variable", Inter, sans-serif',
                            fontSize: 14,
                            fontWeight: 500,
                            height: 44,
                            justifyContent: "center",
                            lineHeight: "20px",
                            px: 2,
                            width: "100%",
                            "&:focus-visible": {
                                outline: `2px solid ${green}`,
                                outlineOffset: 3,
                            },
                            "&:hover": { bgcolor: "#07AE22" },
                        }}
                    >
                        {actionLabel}
                    </Box>
                </Box>
            </Box>
        </Box>
    );
};
