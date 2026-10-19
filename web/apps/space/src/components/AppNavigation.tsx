import {
    BubbleChatIcon,
    Home01Icon,
    PlusSignIcon,
    UserMultiple02Icon,
} from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { Box } from "@mui/material";
import { preloadPostLikeAnimation } from "components/post-like-rive";
import { SpacePostPhotoInput } from "components/PostPhotoInput";
import log from "ente-base/log";
import { isSpaceIOS } from "hooks/use-pwa-install-prompt";
import React from "react";
import { loadCurrentUnreadStatus } from "services/space";
import { useSpaceAppState } from "state/app-state";
import {
    emptySpaceUnreadStatus,
    SpaceUnreadStatusContext,
} from "state/navigation";
import { spaceText } from "styles/colors";
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
    const isAppPage = Boolean(
        router.pathname == spaceRoutes.home ||
        router.pathname.startsWith(`${spaceRoutes.home}/`) ||
        (profile && router.pathname == spaceRoutes.friendPage),
    );
    const isConversation = router.pathname.startsWith(
        `${spaceRoutes.messages}/`,
    );
    const isSettingsPage =
        router.pathname == spaceRoutes.settings ||
        router.pathname == spaceRoutes.settingsProfileName ||
        router.pathname == spaceRoutes.profilePhoto ||
        router.pathname == spaceRoutes.editProfilePhoto ||
        router.pathname == spaceRoutes.profileCover ||
        router.pathname == spaceRoutes.editProfileCover;
    const isProfilePage =
        router.pathname == spaceRoutes.profile ||
        router.pathname == spaceRoutes.friendPage ||
        (router.pathname == spaceRoutes.friends &&
            typeof router.query.friend == "string" &&
            router.query.expanded == "1");
    const isNotificationsPage = router.pathname == spaceRoutes.notifications;
    const showNavigation =
        isAppPage &&
        Boolean(profile) &&
        !isConversation &&
        !isSettingsPage &&
        !isProfilePage &&
        !isNotificationsPage;
    const spaceID =
        isAppPage && profileLoadStatus == "ready"
            ? profile?.spaceId
            : undefined;
    const [unreadStatus, setUnreadStatus] = React.useState(
        emptySpaceUnreadStatus,
    );
    const layoutRef = React.useRef<HTMLDivElement>(null);
    const postInputRef = React.useRef<HTMLInputElement>(null);
    const path = router.asPath.split(/[?#]/)[0] ?? router.pathname;

    React.useEffect(() => {
        if (isAppPage) void preloadPostLikeAnimation();
    }, [isAppPage]);

    React.useEffect(() => {
        if (!spaceID) {
            setUnreadStatus(emptySpaceUnreadStatus);
            return;
        }
        let cancelled = false;
        let sequence = 0;
        const refresh = () => {
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
        window.addEventListener(spaceUnreadStatusChangedEvent, refresh);
        return () => {
            cancelled = true;
            window.removeEventListener(spaceUnreadStatusChangedEvent, refresh);
        };
    }, [spaceID, path]);

    React.useEffect(() => {
        if (!isAppPage) return;
        if (isSpaceIOS())
            layoutRef.current?.style.setProperty(
                "--space-bottom-nav-padding",
                "max(8px, env(safe-area-inset-bottom))",
            );
        const viewport = window.visualViewport;
        if (!viewport) return;
        const updateViewport = () => {
            const activeElement = document.activeElement;
            const isEditing =
                activeElement instanceof HTMLInputElement ||
                activeElement instanceof HTMLTextAreaElement ||
                (activeElement instanceof HTMLElement &&
                    activeElement.isContentEditable);
            const keyboardInset = isEditing
                ? Math.max(
                      0,
                      window.innerHeight -
                          viewport.height -
                          Math.max(0, viewport.offsetTop),
                  )
                : 0;
            layoutRef.current?.toggleAttribute(
                "data-space-keyboard-open",
                keyboardInset > 0,
            );
            layoutRef.current?.style.setProperty(
                "--space-viewport-height",
                `${viewport.height}px`,
            );
            layoutRef.current?.style.setProperty(
                "--space-viewport-offset-top",
                `${Math.max(0, viewport.offsetTop)}px`,
            );
            layoutRef.current?.style.setProperty(
                "--space-keyboard-inset",
                `${keyboardInset}px`,
            );
        };
        updateViewport();
        viewport.addEventListener("resize", updateViewport);
        viewport.addEventListener("scroll", updateViewport);
        document.addEventListener("focusin", updateViewport);
        document.addEventListener("focusout", updateViewport);
        return () => {
            viewport.removeEventListener("resize", updateViewport);
            viewport.removeEventListener("scroll", updateViewport);
            document.removeEventListener("focusin", updateViewport);
            document.removeEventListener("focusout", updateViewport);
        };
    }, [isAppPage]);

    const destinationGroups = [
        [
            {
                label: "Messages",
                href: spaceRoutes.messages,
                icon: BubbleChatIcon,
                size: 23,
            },
        ],
        [
            {
                label: "Space",
                href: spaceRoutes.home,
                icon: Home01Icon,
                size: 23,
            },
            {
                label: "Friends",
                href: spaceRoutes.friends,
                icon: UserMultiple02Icon,
                size: 22,
            },
        ],
        [{ label: "Post", icon: PlusSignIcon, href: undefined, size: 25 }],
    ];

    return (
        <SpaceUnreadStatusContext.Provider value={unreadStatus}>
            <Box
                ref={layoutRef}
                className={isAppPage ? "space-app-layout" : undefined}
                data-space-conversation={isConversation || undefined}
                data-space-settings={isSettingsPage || undefined}
                data-space-profile={isProfilePage || undefined}
                data-space-notifications={isNotificationsPage || undefined}
            >
                {children}
                {showNavigation && (
                    <>
                        <SpacePostPhotoInput
                            inputRef={postInputRef}
                            onSelect={setPendingPostPhotoFiles}
                        />
                        <Box
                            aria-hidden
                            sx={{
                                bottom: "var(--space-keyboard-inset, 0px)",
                                height: "calc(54px + var(--space-bottom-nav-padding))",
                                left: "50%",
                                pointerEvents: "none",
                                position: "fixed",
                                transform: "translateX(-50%)",
                                width: "calc(100% - 16px)",
                                zIndex: 19,
                                "@media (min-width: 600px)": { maxWidth: 374 },
                            }}
                        >
                            {[1, 2, 3].map((layer) => (
                                <Box
                                    key={layer}
                                    className={`space-bottom-nav-blur space-bottom-nav-blur-${layer}`}
                                />
                            ))}
                        </Box>
                        <Box
                            component="nav"
                            aria-label="Main navigation"
                            sx={{
                                alignItems: "center",
                                bottom: "var(--space-keyboard-inset, 0px)",
                                display: "grid",
                                columnGap: "16px",
                                gridTemplateColumns:
                                    "52px minmax(0, 208px) 52px",
                                justifyContent: "space-between",
                                height: "var(--space-bottom-nav-height)",
                                pb: "calc(12px + var(--space-bottom-nav-padding))",
                                pt: "8px",
                                left: "50%",
                                px: "16px",
                                position: "fixed",
                                transform: "translateX(-50%)",
                                width: "100%",
                                zIndex: 20,
                                "@media (min-width: 600px)": { maxWidth: 390 },
                            }}
                        >
                            {destinationGroups.map((destinations) => (
                                <Box
                                    key={destinations[0]!.label}
                                    data-space-bottom-nav-pill
                                    sx={{
                                        alignItems: "center",
                                        backdropFilter:
                                            "blur(24px) saturate(120%)",
                                        WebkitBackdropFilter:
                                            "blur(24px) saturate(120%)",
                                        bgcolor: "rgba(32, 32, 32, 0.7)",
                                        borderRadius: "999px",
                                        display: "flex",
                                        height: 52,
                                        minWidth: 0,
                                        p: "4px",
                                        viewTransitionName: `space-bottom-nav-${destinations[0]!.label.toLowerCase()}`,
                                    }}
                                >
                                    {destinations.map(
                                        ({ label, href, icon, size }) => {
                                            const selected = Boolean(
                                                href &&
                                                href ==
                                                    spaceNavigationDestination(
                                                        router.pathname,
                                                    ),
                                            );
                                            const isPost = label == "Post";
                                            const isCenter =
                                                destinations.length > 1;
                                            return (
                                                <Box
                                                    key={label}
                                                    component={
                                                        isPost ? "button" : "a"
                                                    }
                                                    href={href}
                                                    type={
                                                        isPost
                                                            ? "button"
                                                            : undefined
                                                    }
                                                    disabled={
                                                        isPost
                                                            ? Boolean(
                                                                  pendingPostPhotoFiles,
                                                              )
                                                            : undefined
                                                    }
                                                    aria-label={
                                                        label == "Messages" &&
                                                        unreadStatus.messagesUnread
                                                            ? "Messages with unread activity"
                                                            : label
                                                    }
                                                    aria-current={
                                                        selected
                                                            ? "page"
                                                            : undefined
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
                                                                window.scrollTo(
                                                                    {
                                                                        top: 0,
                                                                        behavior:
                                                                            "smooth",
                                                                    },
                                                                );
                                                            else
                                                                void router.push(
                                                                    href,
                                                                );
                                                        }
                                                    }}
                                                    sx={{
                                                        alignItems: "center",
                                                        appearance: "none",
                                                        bgcolor: selected
                                                            ? "rgba(255, 255, 255, 0.14)"
                                                            : "transparent",
                                                        border: 0,
                                                        borderRadius: "24px",
                                                        color: selected
                                                            ? spaceText
                                                            : "rgba(255, 255, 255, 0.75)",
                                                        cursor: "pointer",
                                                        display: "flex",
                                                        fontFamily:
                                                            '"Inter Variable", Inter, sans-serif',
                                                        fontSize: 14,
                                                        fontWeight: 500,
                                                        height: 44,
                                                        justifyContent:
                                                            "center",
                                                        minWidth: 0,
                                                        width: isCenter
                                                            ? "50%"
                                                            : 44,
                                                        p: 0,
                                                        textDecoration: "none",
                                                        "&:focus-visible": {
                                                            outline:
                                                                "2px solid #08C225",
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
                                                            alignItems:
                                                                "center",
                                                            display: "flex",
                                                            height: isCenter
                                                                ? undefined
                                                                : size,
                                                            justifyContent:
                                                                "center",
                                                            position:
                                                                "relative",
                                                            width: isCenter
                                                                ? undefined
                                                                : size,
                                                            "& svg":
                                                                label ==
                                                                    "Messages" &&
                                                                unreadStatus.messagesUnread
                                                                    ? {
                                                                          maskImage:
                                                                              "radial-gradient(circle at calc(100% - 5px) 5px, transparent 5.75px, #000 6px)",
                                                                          WebkitMaskImage:
                                                                              "radial-gradient(circle at calc(100% - 5px) 5px, transparent 5.75px, #000 6px)",
                                                                      }
                                                                    : undefined,
                                                            "& svg path:last-of-type":
                                                                label ==
                                                                "Messages"
                                                                    ? {
                                                                          display:
                                                                              "none",
                                                                      }
                                                                    : undefined,
                                                        }}
                                                    >
                                                        {isCenter ? (
                                                            label
                                                        ) : (
                                                            <HugeiconsIcon
                                                                icon={icon}
                                                                size={size}
                                                                strokeWidth={
                                                                    1.8
                                                                }
                                                                absoluteStrokeWidth
                                                            />
                                                        )}
                                                        {label == "Messages" &&
                                                            unreadStatus.messagesUnread && (
                                                                <Box
                                                                    aria-hidden
                                                                    className="space-unread-indicator"
                                                                    sx={{
                                                                        bgcolor:
                                                                            "#FF0000",
                                                                        borderRadius:
                                                                            "50%",
                                                                        height: 6.5,
                                                                        position:
                                                                            "absolute",
                                                                        right: "1.75px",
                                                                        top: "1.75px",
                                                                        width: 6.5,
                                                                    }}
                                                                />
                                                            )}
                                                    </Box>
                                                </Box>
                                            );
                                        },
                                    )}
                                </Box>
                            ))}
                        </Box>
                    </>
                )}
            </Box>
        </SpaceUnreadStatusContext.Provider>
    );
};
