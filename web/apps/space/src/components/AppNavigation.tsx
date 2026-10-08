import {
    BubbleChatIcon,
    Home01Icon,
    PlusSignSquareIcon,
    UserCircleIcon,
    UserMultiple02Icon,
} from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { Box } from "@mui/material";
import { SpacePostPhotoInput } from "components/PostPhotoInput";
import log from "ente-base/log";
import React from "react";
import { loadCurrentUnreadStatus } from "services/space";
import { useSpaceAppState } from "state/app-state";
import {
    emptySpaceUnreadStatus,
    SpaceUnreadStatusContext,
} from "state/navigation";
import {
    spaceAppBackgroundColor,
    spaceText,
    spaceTextMuted,
} from "styles/colors";
import {
    spaceNavigationDestination,
    spaceUnreadStatusChangedEvent,
} from "utils/navigation";
import { useSpaceRouter } from "utils/route-transitions";
import { spaceRoutes } from "utils/routes";

export const SpaceAppLayout = ({ children }: { children: React.ReactNode }) => {
    const router = useSpaceRouter();
    const {
        pendingPostPhotoFiles,
        profile,
        profileLoadStatus,
        setPendingPostPhotoFiles,
    } = useSpaceAppState();
    const showNavigation = Boolean(
        router.pathname == spaceRoutes.home ||
        router.pathname.startsWith(`${spaceRoutes.home}/`) ||
        (profile && router.pathname == spaceRoutes.friendPage),
    );
    const spaceID =
        showNavigation && profileLoadStatus == "ready"
            ? profile?.spaceId
            : undefined;
    const [unreadStatus, setUnreadStatus] = React.useState(
        emptySpaceUnreadStatus,
    );
    const layoutRef = React.useRef<HTMLDivElement>(null);
    const postInputRef = React.useRef<HTMLInputElement>(null);
    const path = router.asPath.split(/[?#]/)[0] ?? router.pathname;

    React.useEffect(() => {
        if (!spaceID) {
            setUnreadStatus(emptySpaceUnreadStatus);
            return;
        }
        let cancelled = false;
        let sequence = 0;
        const refresh = () => {
            if (document.visibilityState == "hidden") return;
            const request = ++sequence;
            void loadCurrentUnreadStatus(spaceID)
                .then((status) => {
                    if (!cancelled && request == sequence)
                        setUnreadStatus(status);
                })
                .catch((error: unknown) =>
                    log.warn("Failed to load unread status", error),
                );
        };
        refresh();
        window.addEventListener("focus", refresh);
        window.addEventListener(spaceUnreadStatusChangedEvent, refresh);
        document.addEventListener("visibilitychange", refresh);
        return () => {
            cancelled = true;
            window.removeEventListener("focus", refresh);
            window.removeEventListener(spaceUnreadStatusChangedEvent, refresh);
            document.removeEventListener("visibilitychange", refresh);
        };
    }, [spaceID, path]);

    React.useEffect(() => {
        if (!showNavigation) return;
        const viewport = window.visualViewport;
        if (!viewport) return;
        const updateViewport = () => {
            layoutRef.current?.style.setProperty(
                "--space-viewport-height",
                `${viewport.height}px`,
            );
            layoutRef.current?.style.setProperty(
                "--space-keyboard-inset",
                `${Math.max(0, window.innerHeight - viewport.height - viewport.offsetTop)}px`,
            );
        };
        updateViewport();
        viewport.addEventListener("resize", updateViewport);
        viewport.addEventListener("scroll", updateViewport);
        return () => {
            viewport.removeEventListener("resize", updateViewport);
            viewport.removeEventListener("scroll", updateViewport);
        };
    }, [showNavigation]);

    const destinations = [
        { label: "Home", href: spaceRoutes.home, icon: Home01Icon, size: 25 },
        {
            label: "Messages",
            href: spaceRoutes.messages,
            icon: BubbleChatIcon,
            size: 25,
        },
        { label: "Post", icon: PlusSignSquareIcon, href: undefined, size: 25 },
        {
            label: "Friends",
            href: spaceRoutes.friends,
            icon: UserMultiple02Icon,
            size: 23,
        },
        {
            label: "Profile",
            href: spaceRoutes.profile,
            icon: UserCircleIcon,
            size: 24,
        },
    ];

    return (
        <SpaceUnreadStatusContext.Provider value={unreadStatus}>
            <Box
                ref={layoutRef}
                className={showNavigation ? "space-app-layout" : undefined}
            >
                {children}
                {showNavigation && (
                    <>
                        <SpacePostPhotoInput
                            inputRef={postInputRef}
                            onSelect={setPendingPostPhotoFiles}
                        />
                        <Box
                            component="nav"
                            aria-label="Main navigation"
                            sx={{
                                alignItems: "center",
                                bgcolor: spaceAppBackgroundColor,
                                bottom: "var(--space-keyboard-inset, 0px)",
                                display: "flex",
                                justifyContent: "space-between",
                                height: "calc(60px + env(safe-area-inset-bottom))",
                                pb: "env(safe-area-inset-bottom)",
                                left: "50%",
                                maxWidth: 390,
                                px: "10px",
                                position: "fixed",
                                transform: "translateX(-50%)",
                                viewTransitionName: "space-bottom-nav",
                                width: "100%",
                                zIndex: 20,
                            }}
                        >
                            {destinations.map(({ label, href, icon, size }) => {
                                const selected = Boolean(
                                    href &&
                                    href ==
                                        spaceNavigationDestination(
                                            router.pathname,
                                        ),
                                );
                                const isPost = label == "Post";
                                return (
                                    <Box
                                        key={label}
                                        component={isPost ? "button" : "a"}
                                        href={href}
                                        type={isPost ? "button" : undefined}
                                        disabled={
                                            isPost
                                                ? Boolean(pendingPostPhotoFiles)
                                                : undefined
                                        }
                                        aria-label={
                                            label == "Messages" &&
                                            unreadStatus.messagesUnread
                                                ? "Messages with unread activity"
                                                : label
                                        }
                                        aria-current={
                                            selected ? "page" : undefined
                                        }
                                        onClick={(
                                            event: React.MouseEvent<HTMLElement>,
                                        ) => {
                                            if (isPost) {
                                                postInputRef.current?.click();
                                            } else if (
                                                href &&
                                                !event.metaKey &&
                                                !event.ctrlKey &&
                                                !event.shiftKey &&
                                                !event.altKey
                                            ) {
                                                event.preventDefault();
                                                if (path == href)
                                                    window.scrollTo({
                                                        top: 0,
                                                        behavior: "smooth",
                                                    });
                                                else void router.push(href);
                                            }
                                        }}
                                        sx={{
                                            alignItems: "center",
                                            bgcolor: "transparent",
                                            border: 0,
                                            borderRadius: "24px",
                                            color: selected
                                                ? spaceText
                                                : spaceTextMuted,
                                            cursor: "pointer",
                                            display: "flex",
                                            height: 52,
                                            justifyContent: "center",
                                            minWidth: 0,
                                            width: 44,
                                            p: 0,
                                            textDecoration: "none",
                                            "&:focus-visible": {
                                                outline: "2px solid #08C225",
                                                outlineOffset: 2,
                                            },
                                            "&:disabled": {
                                                opacity: 0.6,
                                                cursor: "default",
                                            },
                                        }}
                                    >
                                        <Box
                                            sx={{
                                                alignItems: "center",
                                                display: "flex",
                                                height: size,
                                                justifyContent: "center",
                                                position: "relative",
                                                width: size,
                                                "& svg path:last-of-type":
                                                    label == "Messages"
                                                        ? { display: "none" }
                                                        : undefined,
                                            }}
                                        >
                                            <HugeiconsIcon
                                                icon={icon}
                                                size={size}
                                                strokeWidth={
                                                    selected ? 2.2 : 1.8
                                                }
                                            />
                                            {label == "Messages" &&
                                                unreadStatus.messagesUnread && (
                                                    <Box
                                                        aria-hidden
                                                        sx={{
                                                            bgcolor: "#F63A3A",
                                                            border: `2px solid ${spaceAppBackgroundColor}`,
                                                            borderRadius: "50%",
                                                            height: 10,
                                                            position:
                                                                "absolute",
                                                            right: 0,
                                                            top: 0,
                                                            width: 10,
                                                        }}
                                                    />
                                                )}
                                        </Box>
                                    </Box>
                                );
                            })}
                        </Box>
                    </>
                )}
            </Box>
        </SpaceUnreadStatusContext.Provider>
    );
};
