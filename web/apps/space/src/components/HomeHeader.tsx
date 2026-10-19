import { Notification01Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { Box, Skeleton } from "@mui/material";
import { SpaceAvatarImage } from "components/AvatarImage";
import React from "react";
import type { SetupProfile } from "screens/SetupProfileScreen";
import { useSpaceAppState } from "state/app-state";
import { useSpaceUnreadStatus } from "state/navigation";
import {
    spaceAppBackgroundColor,
    spaceSurface,
    spaceText,
} from "styles/colors";
import { useSpaceRouter } from "utils/route-transitions";
import { spaceRoutes } from "utils/routes";

const headerAvatarImageSize = 28;
const avatarFadeSx = {
    "@keyframes spaceAvatarFade": { from: { opacity: 0 }, to: { opacity: 1 } },
    animation: "spaceAvatarFade 320ms cubic-bezier(0.22, 1, 0.36, 1) both",
    "@media (prefers-reduced-motion: reduce)": { animation: "none" },
} as const;

export const SpaceHomeHeader: React.FC<{ profile: SetupProfile | null }> = ({
    profile,
}) => {
    const router = useSpaceRouter();
    const { notificationsUnread } = useSpaceUnreadStatus();
    const [visible, setVisible] = React.useState(true);

    React.useEffect(() => {
        let previousY = window.scrollY;
        let frame = 0;
        const update = () => {
            frame = 0;
            const y = Math.max(0, window.scrollY);
            if (y <= 60) {
                setVisible(true);
                previousY = y;
            } else if (Math.abs(y - previousY) >= 8) {
                setVisible(y < previousY);
                previousY = y;
            }
        };
        const onScroll = () => {
            if (!frame) frame = window.requestAnimationFrame(update);
        };
        window.addEventListener("scroll", onScroll, { passive: true });
        return () => {
            window.removeEventListener("scroll", onScroll);
            window.cancelAnimationFrame(frame);
        };
    }, []);
    const actionSx = {
        alignItems: "center",
        bgcolor: "transparent",
        border: 0,
        borderRadius: "50%",
        color: spaceText,
        cursor: "pointer",
        display: "flex",
        height: 44,
        p: 0,
        position: "relative",
        width: 44,
        "&:focus-visible": { outline: "2px solid #08C225", outlineOffset: 2 },
    } as const;

    return (
        <Box
            component="header"
            sx={{
                alignItems: "center",
                bgcolor: spaceAppBackgroundColor,
                color: spaceText,
                display: "grid",
                gridTemplateColumns: "44px minmax(0, 1fr) 44px",
                height: "calc(68px + var(--space-ios-safe-area-top, 0px))",
                mx: "auto",
                pt: "var(--space-ios-safe-area-top, 0px)",
                pl: "max(16px, var(--space-ios-safe-area-left, 0px))",
                pr: "max(16px, var(--space-ios-safe-area-right, 0px))",
                position: "sticky",
                top: 0,
                transform: visible ? "translateY(0)" : "translateY(-100%)",
                transition: visible
                    ? "transform 340ms cubic-bezier(0.4, 0, 0.2, 1)"
                    : "transform 440ms cubic-bezier(0.4, 0, 0.2, 1)",
                width: "100%",
                zIndex: 10,
                "@media (prefers-reduced-motion: reduce)": {
                    transition: "none",
                },
                "@media (min-width: 600px)": { maxWidth: 390 },
            }}
        >
            <Box
                component="button"
                type="button"
                aria-label="Profile"
                onClick={() => void router.push(spaceRoutes.profile)}
                sx={{ ...actionSx, justifyContent: "flex-start" }}
            >
                <SpaceHomeHeaderAvatar profile={profile} />
            </Box>
            <Box
                component="img"
                alt="Space"
                src="/images/space.svg"
                sx={{
                    display: "block",
                    height: 20,
                    justifySelf: "center",
                    width: "auto",
                }}
            />
            <Box
                component="button"
                type="button"
                aria-label={
                    notificationsUnread
                        ? "Notifications with unread activity"
                        : "Notifications"
                }
                onClick={() => void router.push(spaceRoutes.notifications)}
                sx={{ ...actionSx, justifyContent: "flex-end" }}
            >
                <Box
                    component="span"
                    sx={{
                        display: "flex",
                        height: 23,
                        position: "relative",
                        width: 23,
                    }}
                >
                    <HugeiconsIcon
                        icon={Notification01Icon}
                        size={23}
                        strokeWidth={1.8}
                        absoluteStrokeWidth
                    />
                    {notificationsUnread && (
                        <Box
                            aria-hidden
                            className="space-unread-indicator"
                            sx={{
                                bgcolor: "#FF0000",
                                border: `2.5px solid ${spaceAppBackgroundColor}`,
                                borderRadius: "50%",
                                height: 11.5,
                                position: "absolute",
                                right: "-0.75px",
                                top: "-0.75px",
                                width: 11.5,
                            }}
                        />
                    )}
                </Box>
            </Box>
        </Box>
    );
};

const SpaceHomeHeaderAvatar: React.FC<{ profile: SetupProfile | null }> = ({
    profile,
}) => {
    const { cachedProfileAvatarUrl } = useSpaceAppState();
    const avatarUrl = profile ? profile.avatarUrl : cachedProfileAvatarUrl;

    return avatarUrl || (profile && !profile.avatarObjectID) ? (
        <Box
            key={avatarUrl ?? "default-avatar"}
            sx={{
                ...avatarFadeSx,
                borderRadius: "50%",
                filter: avatarUrl ? undefined : "brightness(0.9)",
                height: headerAvatarImageSize,
                overflow: "hidden",
                width: headerAvatarImageSize,
            }}
        >
            <SpaceAvatarImage src={avatarUrl} />
        </Box>
    ) : (
        <Skeleton
            variant="circular"
            sx={{
                bgcolor: spaceSurface,
                height: headerAvatarImageSize,
                transform: "none",
                width: headerAvatarImageSize,
            }}
        />
    );
};
