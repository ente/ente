import { AddSquareIcon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { Box } from "@mui/material";
import { SpaceBackIcon } from "components/BackIcon";
import { SpacePageMeta } from "components/PageMeta";
import { SpaceRouteFallback } from "components/RouteFallback";
import log from "ente-base/log";
import React from "react";
import { useSpaceAppState } from "state/app-state";
import { spaceTouchTargetSize } from "styles/touch-targets";
import { spacePostImageInputAccept } from "utils/post-image";
import { useSpaceRouter } from "utils/route-transitions";
import { spaceRoutes } from "utils/routes";

const background = "#F5F5F7";
const green = "#08C225";
const textBase = "#000000";
const textSecondary = "#6B6B6B";

const Page: React.FC = () => {
    const router = useSpaceRouter();
    const {
        profile,
        profileLoadError,
        profileLoadStatus,
        setPendingPostPhotoFile,
        setSkipNextHomeFeedSkeleton,
    } = useSpaceAppState();
    const inputRef = React.useRef<HTMLInputElement | null>(null);
    const [isOpeningPost, setIsOpeningPost] = React.useState(false);

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

    const handlePhotoSelect: React.ChangeEventHandler<HTMLInputElement> = (
        event,
    ) => {
        const file = event.target.files?.[0];
        event.target.value = "";
        if (!file) return;

        setIsOpeningPost(true);
        setPendingPostPhotoFile(file);
        setSkipNextHomeFeedSkeleton(true);
        void router.push(spaceRoutes.home).catch((error: unknown) => {
            log.error("Failed to open post photo draft", error);
            setPendingPostPhotoFile(null);
            setIsOpeningPost(false);
        });
    };

    return (
        <>
            <SpacePageMeta themeColor={background} />
            <Box
                component="main"
                sx={{
                    bgcolor: background,
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
                                fontSize: 15,
                                fontWeight: 500,
                                lineHeight: "22px",
                                m: 0,
                                mt: "10px",
                                maxWidth: 280,
                            }}
                        >
                            Post a moment, big or small.
                        </Box>
                        <Box
                            ref={inputRef}
                            component="input"
                            type="file"
                            accept={spacePostImageInputAccept}
                            onChange={handlePhotoSelect}
                            sx={{ display: "none" }}
                        />
                        <Box
                            className="green-bg"
                            component="button"
                            type="button"
                            disabled={isOpeningPost}
                            onClick={() => inputRef.current?.click()}
                            sx={{
                                alignItems: "center",
                                bgcolor: green,
                                border: 0,
                                borderRadius: "22px",
                                color: "#FFFFFF",
                                cursor: isOpeningPost ? "default" : "pointer",
                                display: "inline-flex",
                                fontFamily:
                                    '"Inter Variable", Inter, sans-serif',
                                fontSize: 15,
                                fontWeight: 700,
                                gap: "8px",
                                height: 48,
                                justifyContent: "center",
                                mt: "28px",
                                opacity: isOpeningPost ? 0.65 : 1,
                                px: "22px",
                                "&:focus-visible": {
                                    outline: `2px solid ${green}`,
                                    outlineOffset: 3,
                                },
                                "&:hover": isOpeningPost
                                    ? undefined
                                    : { bgcolor: "#07AE22" },
                            }}
                        >
                            <HugeiconsIcon
                                icon={AddSquareIcon}
                                size={20}
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
