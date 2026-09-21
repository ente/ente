import { AddSquareIcon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { Box } from "@mui/material";
import { SpaceBackIcon } from "components/BackIcon";
import { SpacePageMeta } from "components/PageMeta";
import { SpacePostPhotoInput } from "components/PostPhotoInput";
import { SpaceRouteFallback } from "components/RouteFallback";
import React from "react";
import { useSpaceAppState } from "state/app-state";
import { spaceEmptyStateButtonSx } from "styles/buttons";
import {
    spaceAppBackground,
    spaceAppBackgroundColor,
    spaceText,
    spaceTextMuted,
} from "styles/colors";
import { spaceTouchTargetSize } from "styles/touch-targets";
import { useSpaceRouter } from "utils/route-transitions";
import { spaceRoutes } from "utils/routes";

const background = spaceAppBackgroundColor;
const green = "#08C225";
const textBase = spaceText;
const textSecondary = spaceTextMuted;

const Page: React.FC = () => {
    const router = useSpaceRouter();
    const {
        profile,
        profileLoadError,
        profileLoadStatus,
        pendingPostPhotoFiles,
        setPendingPostPhotoFiles,
    } = useSpaceAppState();
    const inputRef = React.useRef<HTMLInputElement | null>(null);
    const isOpeningPost = Boolean(pendingPostPhotoFiles);

    React.useEffect(() => {
        if (profileLoadStatus == "ready" && !profile) {
            void router.replace(spaceRoutes.onboarding);
        }
    }, [profile, profileLoadStatus, router]);

    if (profileLoadStatus != "ready" || !profile) {
        return (
            <SpaceRouteFallback
                background={background}
                message={profileLoadError}
            />
        );
    }

    return (
        <>
            <SpacePageMeta themeColor={background} />
            <Box
                component="main"
                sx={{
                    background: spaceAppBackground,
                    color: textBase,
                    display: "grid",
                    minHeight: "100svh",
                    placeItems: { xs: "stretch", sm: "start center" },
                }}
            >
                <Box
                    sx={{
                        boxSizing: "border-box",
                        display: "grid",
                        gridTemplateRows: "56px minmax(0, 1fr)",
                        minHeight: "100svh",
                        mx: "auto",
                        width: "100%",
                        "@media (min-width: 600px)": { maxWidth: 390 },
                    }}
                >
                    <Box
                        component="header"
                        sx={{
                            alignItems: "center",
                            display: "flex",
                            height: 56,
                            px: 2,
                        }}
                    >
                        <Box
                            component="button"
                            type="button"
                            aria-label="Back to Space"
                            onClick={() => void router.push(spaceRoutes.home)}
                            sx={{
                                alignItems: "center",
                                bgcolor: "transparent",
                                border: 0,
                                borderRadius: "50%",
                                color: textBase,
                                cursor: "pointer",
                                display: "flex",
                                height: spaceTouchTargetSize,
                                justifyContent: "flex-start",
                                ml: "-2px",
                                p: 0,
                                width: spaceTouchTargetSize,
                                "&:focus-visible": {
                                    outline: `2px solid ${green}`,
                                    outlineOffset: 2,
                                },
                            }}
                        >
                            <SpaceBackIcon />
                        </Box>
                    </Box>
                    <Box
                        component="section"
                        sx={{
                            alignItems: "center",
                            alignSelf: "center",
                            display: "flex",
                            flexDirection: "column",
                            px: "28px",
                            pb: "48px",
                            textAlign: "center",
                        }}
                    >
                        <Box
                            component="h1"
                            sx={{
                                fontFamily: '"Nunito", sans-serif',
                                fontSize: 28,
                                fontWeight: 800,
                                lineHeight: "34px",
                                m: 0,
                            }}
                        >
                            What&apos;s up?
                        </Box>
                        <Box
                            component="p"
                            sx={{
                                color: textSecondary,
                                fontFamily:
                                    '"Inter Variable", Inter, sans-serif',
                                fontSize: 14,
                                fontWeight: 500,
                                lineHeight: "22px",
                                m: 0,
                                mt: "10px",
                                maxWidth: 280,
                            }}
                        >
                            Post a photo from your day.
                        </Box>
                        <SpacePostPhotoInput
                            inputRef={inputRef}
                            onSelect={setPendingPostPhotoFiles}
                        />
                        <Box
                            className="green-bg"
                            component="button"
                            type="button"
                            disabled={isOpeningPost}
                            onClick={() => inputRef.current?.click()}
                            sx={{ ...spaceEmptyStateButtonSx, mt: "28px" }}
                        >
                            <HugeiconsIcon
                                icon={AddSquareIcon}
                                size={18}
                                strokeWidth={1.8}
                            />
                            Post
                        </Box>
                    </Box>
                </Box>
            </Box>
        </>
    );
};

export default Page;
