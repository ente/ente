import { Menu01Icon, Notification01Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { Box } from "@mui/material";
import React from "react";
import { useSpaceUnreadStatus } from "state/navigation";
import { spaceAppBackgroundColor, spaceText } from "styles/colors";
import { useSpaceRouter } from "utils/route-transitions";
import { spaceRoutes } from "utils/routes";

export const SpaceHomeHeader: React.FC = () => {
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
                height: 60,
                mx: "auto",
                px: 2,
                position: "sticky",
                top: 0,
                transform: visible ? "translateY(0)" : "translateY(-100%)",
                transition: "transform 220ms cubic-bezier(0.2, 0, 0, 1)",
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
                aria-label="Settings"
                onClick={() => void router.push(spaceRoutes.settings)}
                sx={{ ...actionSx, justifyContent: "flex-start" }}
            >
                <HugeiconsIcon
                    icon={Menu01Icon}
                    size={23}
                    strokeWidth={1.8}
                    absoluteStrokeWidth
                />
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
                                bgcolor: "#F63A3A",
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
