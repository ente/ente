import { Box, Skeleton } from "@mui/material";
import { SpaceAvatarImage } from "components/SpaceAvatarImage";
import { SpaceShareInviteButton } from "components/SpaceShareInviteButton";
import React from "react";
import type { SetupProfile } from "screens/SetupProfileScreen";

export const shareProfileLinkBackground = "#FAFAFA";

const green = "#08C225";
const textBase = "#000";
const textMuted = "#666";
const avatarSkeletonBackground = "#E6E6E6";
const headerHeight = 64;
const headerSideWidth = 32;

interface ShareProfileLinkScreenProps {
    onDone?: () => void;
    profile: SetupProfile;
    profileLink?: string;
}

export const ShareProfileLinkScreen: React.FC<ShareProfileLinkScreenProps> = ({
    onDone,
    profile,
    profileLink,
}) => {
    const displayName = profile.fullName.trim() || profile.username.trim();

    return (
        <Box
            component="main"
            sx={{
                bgcolor: shareProfileLinkBackground,
                color: textBase,
                display: "grid",
                minHeight: "100svh",
                overflow: "hidden",
                placeItems: { xs: "stretch", sm: "start center" },
            }}
        >
            <Box
                sx={{
                    bgcolor: shareProfileLinkBackground,
                    boxSizing: "border-box",
                    display: "flex",
                    flexDirection: "column",
                    minHeight: "100svh",
                    minWidth: 0,
                    mx: "auto",
                    overflowX: "hidden",
                    pb: "156px",
                    px: 3,
                    width: "100%",
                    "@media (min-width: 600px)": { maxWidth: 390 },
                }}
            >
                <Box
                    component="header"
                    sx={{
                        alignItems: "center",
                        bgcolor: shareProfileLinkBackground,
                        boxSizing: "border-box",
                        display: "grid",
                        gap: "12px",
                        gridTemplateColumns: `${headerSideWidth}px minmax(0, 1fr) ${headerSideWidth}px`,
                        height: headerHeight + 4,
                        left: "50%",
                        maxWidth: "100%",
                        pb: 2,
                        position: "fixed",
                        pt: 2,
                        px: 2,
                        top: 0,
                        transform: "translateX(-50%)",
                        width: "100%",
                        zIndex: 4,
                        "@media (min-width: 600px)": { maxWidth: 390 },
                    }}
                >
                    <Box />
                    <Box
                        sx={{
                            alignSelf: "center",
                            color: textBase,
                            justifySelf: "center",
                            lineHeight: 0,
                            minWidth: 0,
                            overflow: "visible",
                            placeSelf: "center",
                            width: 61,
                        }}
                    >
                        <Box
                            component="img"
                            alt="Space"
                            src="/images/space.svg"
                            sx={{
                                display: "block",
                                filter: "invert(1)",
                                height: 18,
                                width: "auto",
                            }}
                        />
                    </Box>
                    <Box />
                </Box>
                <Box aria-hidden sx={{ height: headerHeight + 4 }} />
                <Box
                    sx={{
                        alignItems: "center",
                        display: "flex",
                        flex: "1 1 auto",
                        flexDirection: "column",
                        justifyContent: "center",
                        maxWidth: "100%",
                        minHeight: 0,
                        minWidth: 0,
                        width: "100%",
                    }}
                >
                    <Box
                        sx={{
                            alignItems: "center",
                            aspectRatio: "1 / 1",
                            bgcolor: avatarSkeletonBackground,
                            borderRadius: "50%",
                            display: "flex",
                            height: 176,
                            justifyContent: "center",
                            overflow: "hidden",
                            width: 176,
                        }}
                    >
                        {profile.avatarUrl || !profile.avatarObjectID ? (
                            <SpaceAvatarImage src={profile.avatarUrl} />
                        ) : (
                            <Skeleton
                                variant="circular"
                                sx={{
                                    bgcolor: avatarSkeletonBackground,
                                    height: "100%",
                                    transform: "none",
                                    width: "100%",
                                }}
                            />
                        )}
                    </Box>

                    <Box
                        component="h2"
                        sx={{
                            fontFamily: '"Inter Variable", Inter, sans-serif',
                            fontSize: 24,
                            fontWeight: 600,
                            lineHeight: "32px",
                            m: 0,
                            mt: "24px",
                            textAlign: "center",
                        }}
                    >
                        Welcome, {displayName}
                    </Box>
                    <Box
                        component="p"
                        sx={{
                            color: textMuted,
                            fontFamily: '"Inter Variable", Inter, sans-serif',
                            fontSize: 14,
                            fontWeight: 500,
                            lineHeight: "20px",
                            m: 0,
                            maxWidth: "100%",
                            minWidth: 0,
                            mt: "12px",
                            overflowWrap: "break-word",
                            textAlign: "center",
                            width: "100%",
                        }}
                    >
                        Next, invite the people you want to share with
                    </Box>
                </Box>

                <Box
                    sx={{
                        bgcolor: shareProfileLinkBackground,
                        bottom: 0,
                        boxSizing: "border-box",
                        display: "flex",
                        flexDirection: "column",
                        gap: "10px",
                        left: "50%",
                        maxWidth: 390,
                        p: "16px 24px calc(20px + env(safe-area-inset-bottom))",
                        position: "fixed",
                        transform: "translateX(-50%)",
                        width: "100%",
                    }}
                >
                    <SpaceShareInviteButton
                        className="green-bg"
                        iconStrokeWidth={2}
                        profileLink={profileLink}
                        sx={{
                            alignItems: "center",
                            bgcolor: green,
                            border: 0,
                            borderRadius: "20px",
                            color: "white",
                            cursor: profileLink ? "pointer" : "default",
                            display: "flex",
                            gap: "10px",
                            fontFamily: '"Inter Variable", Inter, sans-serif',
                            fontSize: 14,
                            fontWeight: 600,
                            height: 48,
                            justifyContent: "center",
                            lineHeight: "20px",
                            p: "14px 24px",
                            width: "100%",
                            "&:disabled": { opacity: 0.56 },
                            "&:focus-visible": {
                                outline: `2px solid ${green}`,
                                outlineOffset: 3,
                            },
                            "&:hover": profileLink
                                ? { bgcolor: "#07AE22" }
                                : undefined,
                        }}
                    />
                    {onDone && (
                        <Box
                            component="button"
                            type="button"
                            onClick={onDone}
                            sx={{
                                alignItems: "center",
                                bgcolor: "#F2F2F2",
                                border: 0,
                                borderRadius: "20px",
                                color: textMuted,
                                cursor: "pointer",
                                display: "flex",
                                fontFamily:
                                    '"Inter Variable", Inter, sans-serif',
                                fontSize: 14,
                                fontWeight: 600,
                                height: 48,
                                justifyContent: "center",
                                lineHeight: "20px",
                                p: "14px 24px",
                                width: "100%",
                                "&:focus-visible": {
                                    outline: `2px solid ${green}`,
                                    outlineOffset: 2,
                                },
                                "&:hover": { bgcolor: "#ECECEC" },
                            }}
                        >
                            Done
                        </Box>
                    )}
                </Box>
            </Box>
        </Box>
    );
};
