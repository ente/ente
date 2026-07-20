import { Box } from "@mui/material";
import { SpaceButtonSpinner } from "components/SpaceButtonSpinner";
import { SpaceMobileBestToast } from "components/SpaceMobileBestToast";
import { SpacePageMeta } from "components/SpacePageMeta";
import { SpaceRouteFallback } from "components/SpaceRouteFallback";
import React, { useEffect, useState } from "react";
import {
    OnboardingScreen,
    addFriendOnboardingTitle,
    onboardingGreen,
} from "screens/OnboardingScreen";
import { profileBackground } from "screens/ProfileScreen";
import {
    joinSpaceInvite,
    loadPublicSpaceIdentity,
    type PublicSpaceIdentity,
} from "services/space";
import {
    clearPendingSpaceInvite,
    clearPendingSpaceInviteFriend,
    savePendingSpaceInvite,
    savePendingSpaceInviteFriend,
    saveSentSpaceInviteFriend,
    savedPendingSpaceInvite,
    spaceInviteFromLocation,
    type PendingSpaceInvite,
} from "services/spaceInvite";
import {
    useSpaceAppState,
    type OnboardingEntrySource,
} from "state/spaceAppState";
import { spaceRoutes } from "utils/spaceRoutes";
import { useSpaceRouter } from "utils/spaceRouteTransitions";

type RouteMode =
    | { kind: "checking" }
    | { kind: "app" }
    | ({ kind: "public-profile" } & PendingSpaceInvite);

interface PageProps {
    invitePreview?: boolean;
}

const PublicProfileUnavailable: React.FC = () => (
    <Box
        className="green-bg"
        component="main"
        sx={{
            alignItems: "center",
            bgcolor: onboardingGreen,
            boxSizing: "border-box",
            color: "white",
            display: "grid",
            minHeight: "100svh",
            placeItems: "center",
            px: 3,
            textAlign: "center",
        }}
    >
        <Box sx={{ maxWidth: 314 }}>
            <Box
                component="h1"
                sx={{
                    fontFamily: "Nunito, sans-serif",
                    fontSize: 24,
                    fontWeight: 800,
                    letterSpacing: 0,
                    lineHeight: "29px",
                    m: 0,
                    whiteSpace: "nowrap",
                }}
            >
                Profile unavailable
            </Box>
        </Box>
        <SpaceMobileBestToast />
    </Box>
);

const onboardingEntrySourceFromPendingInvite = (
    pendingInvite?: PendingSpaceInvite,
): OnboardingEntrySource => (pendingInvite ? "add-friend-link" : "direct");

interface PublicFriendRequestScreenProps {
    identity: PublicSpaceIdentity;
    isAddingFriend: boolean;
    onAddFriend: () => void;
}

const PublicFriendRequestScreen: React.FC<PublicFriendRequestScreenProps> = ({
    identity,
    isAddingFriend,
    onAddFriend,
}) => (
    <Box
        component="main"
        sx={{
            bgcolor: "white",
            boxSizing: "border-box",
            display: "grid",
            minHeight: "100svh",
            p: { xs: 1, sm: 0 },
            placeItems: "stretch",
        }}
    >
        <Box
            className="green-bg"
            sx={{
                alignItems: "center",
                bgcolor: onboardingGreen,
                borderRadius: { xs: "32px", sm: 0 },
                boxSizing: "border-box",
                color: "white",
                display: "flex",
                flexDirection: "column",
                justifyContent: "space-between",
                minHeight: { xs: "calc(100svh - 16px)", sm: "100svh" },
                overflow: "hidden",
                position: "relative",
                textAlign: "center",
                width: "100%",
                "@media (max-width: 599.95px)": {
                    background:
                        'url("/images/invite-bg.jpg") center / cover no-repeat',
                },
            }}
        >
            <Box
                component="header"
                sx={{
                    alignItems: "center",
                    display: "grid",
                    flexShrink: 0,
                    gridTemplateColumns: "40px 1fr 40px",
                    height: 40,
                    maxWidth: 390,
                    mt: "clamp(24px, 5.5svh, 44px)",
                    mx: "auto",
                    px: 3,
                    width: "100%",
                }}
            >
                <Box />
                <Box
                    component="a"
                    href="/"
                    aria-label="Go to Space"
                    sx={{
                        display: "block",
                        justifySelf: "center",
                        lineHeight: 0,
                        textDecoration: "none",
                        width: 101,
                    }}
                >
                    <Box
                        component="span"
                        sx={{
                            bgcolor: { xs: "#CBE78F", sm: "white" },
                            display: "block",
                            height: 30,
                            mask: 'url("/images/space.svg") center / contain no-repeat',
                            WebkitMask:
                                'url("/images/space.svg") center / contain no-repeat',
                            width: 101,
                        }}
                    />
                </Box>
                <Box />
            </Box>
            <Box
                sx={{
                    alignItems: "center",
                    display: "flex",
                    flexDirection: "column",
                    justifyContent: "center",
                    maxWidth: 390,
                    minHeight: 0,
                    px: 3,
                    width: "100%",
                }}
            >
                <Box
                    component="h1"
                    sx={{
                        fontFamily: "Nunito, sans-serif",
                        fontSize: 28,
                        fontWeight: 800,
                        letterSpacing: 0,
                        lineHeight: "34px",
                        m: 0,
                        maxWidth: "100%",
                        overflowWrap: "anywhere",
                    }}
                >
                    <Box component="span" sx={{ display: "block" }}>
                        {`See @${identity.username}’s`}
                    </Box>
                    everyday moments
                </Box>
                <Box
                    component="p"
                    sx={{
                        color: "rgba(255, 255, 255, 0.7)",
                        fontFamily: '"Inter Variable", Inter, sans-serif',
                        fontSize: 14,
                        fontWeight: 500,
                        lineHeight: "20px",
                        m: "12px auto 0",
                        maxWidth: 260,
                    }}
                >
                    {`Add @${identity.username} as a friend to see what they're up to on Ente Space`}
                </Box>
            </Box>
            <Box
                sx={{
                    boxSizing: "border-box",
                    flexShrink: 0,
                    maxWidth: 390,
                    mx: "auto",
                    pb: "calc(env(safe-area-inset-bottom) + clamp(36px, calc(5.5svh + 12px), 56px))",
                    px: 3,
                    pt: 3,
                    width: "100%",
                }}
            >
                <Box
                    component="button"
                    type="button"
                    disabled={isAddingFriend}
                    aria-label={isAddingFriend ? "Adding friend" : undefined}
                    aria-busy={isAddingFriend ? true : undefined}
                    onClick={onAddFriend}
                    sx={{
                        alignItems: "center",
                        appearance: "none",
                        bgcolor: { xs: "white", sm: "black" },
                        border: 0,
                        borderRadius: "24px",
                        color: { xs: "black", sm: "white" },
                        cursor: isAddingFriend ? "default" : "pointer",
                        display: "flex",
                        fontFamily: '"Inter Variable", Inter, sans-serif',
                        fontSize: 16,
                        fontWeight: 700,
                        justifyContent: "center",
                        lineHeight: "24px",
                        minHeight: 60,
                        p: "18px 24px",
                        mx: "auto",
                        width: "min(100%, 300px)",
                        "&:hover": isAddingFriend
                            ? undefined
                            : { bgcolor: { xs: "#F4F4F4", sm: "#121212" } },
                        "&:focus-visible": {
                            outline: "2px solid rgba(255 255 255 / 0.88)",
                            outlineOffset: 3,
                        },
                    }}
                >
                    {isAddingFriend ? <SpaceButtonSpinner /> : "Add Friend"}
                </Box>
            </Box>
        </Box>
        <SpaceMobileBestToast />
    </Box>
);

export const Page: React.FC<PageProps> = ({ invitePreview }) => {
    const router = useSpaceRouter();
    const {
        onboardingEntrySource,
        profile,
        profileLoadError,
        profileLoadStatus,
        refreshProfile,
        setOnboardingEntrySource,
    } = useSpaceAppState();
    const [routeMode, setRouteMode] = useState<RouteMode>({ kind: "checking" });
    const [publicIdentity, setPublicIdentity] =
        useState<PublicSpaceIdentity | null>(null);
    const [publicError, setPublicError] = useState<string>();
    const [pendingInviteUsername, setPendingInviteUsername] = useState("");
    const [isAddingFriend, setIsAddingFriend] = useState(false);

    useEffect(() => {
        const publicInvite = spaceInviteFromLocation();
        if (!publicInvite) {
            const pendingInvite = savedPendingSpaceInvite();
            setOnboardingEntrySource(
                onboardingEntrySourceFromPendingInvite(pendingInvite),
            );
            if (pendingInvite) {
                setPendingInviteUsername(pendingInvite.spaceUsername);
            }
        }
        setRouteMode(
            publicInvite
                ? { kind: "public-profile", ...publicInvite }
                : { kind: "app" },
        );
    }, [setOnboardingEntrySource]);

    useEffect(() => {
        if (routeMode.kind != "public-profile") return;

        let cancelled = false;
        setPublicError(undefined);
        setPublicIdentity(null);
        void loadPublicSpaceIdentity(routeMode.spaceUsername)
            .then((identity) => {
                if (!cancelled) setPublicIdentity(identity);
            })
            .catch(() => {
                if (!cancelled) setPublicError("This profile is unavailable.");
            });

        return () => {
            cancelled = true;
        };
    }, [routeMode]);

    useEffect(() => {
        if (
            routeMode.kind == "app" &&
            profileLoadStatus == "ready" &&
            profile
        ) {
            void router.replace(spaceRoutes.home);
        }
    }, [profile, profileLoadStatus, routeMode.kind, router]);

    const hasProfileLoadError =
        routeMode.kind == "app" && profileLoadStatus == "error";

    if (hasProfileLoadError) {
        return (
            <SpaceRouteFallback
                background={profileBackground}
                message={profileLoadError}
            />
        );
    }

    if (
        routeMode.kind == "checking" ||
        (routeMode.kind == "app" &&
            (profileLoadStatus == "loading" || Boolean(profile)))
    ) {
        return (
            <SpaceRouteFallback
                background={profileBackground}
                preview={invitePreview ? "invite" : "home"}
            />
        );
    }

    if (routeMode.kind == "public-profile") {
        if (!publicIdentity && !publicError) {
            return <SpaceRouteFallback background={profileBackground} />;
        }

        if (!publicIdentity) {
            return (
                <>
                    <SpacePageMeta
                        themeColor={profileBackground}
                        preview="invite"
                    />
                    <PublicProfileUnavailable />
                </>
            );
        }

        const inviteFriend = {
            fullName: "",
            username: publicIdentity.username,
        };
        const addFriend = async () => {
            const invite = {
                spaceId: publicIdentity.spaceId,
                spaceUsername: publicIdentity.username,
            };
            savePendingSpaceInvite(invite);
            savePendingSpaceInviteFriend(inviteFriend);
            setOnboardingEntrySource("add-friend-link");
            setIsAddingFriend(true);
            try {
                const readyProfile =
                    profileLoadStatus == "ready"
                        ? profile
                        : await refreshProfile({ throwOnError: true });
                if (!readyProfile) {
                    window.location.assign("/");
                    return;
                }

                const status = await joinSpaceInvite(invite);
                clearPendingSpaceInvite();
                clearPendingSpaceInviteFriend();
                if (status == "requested") {
                    saveSentSpaceInviteFriend(inviteFriend);
                }
                void router.push(spaceRoutes.home);
            } catch (error) {
                setIsAddingFriend(false);
                console.error("Failed to send friend request", error);
            }
        };

        return (
            <>
                <SpacePageMeta
                    themeColor={profileBackground}
                    preview="invite"
                />
                <PublicFriendRequestScreen
                    identity={publicIdentity}
                    isAddingFriend={isAddingFriend}
                    onAddFriend={() => void addFriend()}
                />
            </>
        );
    }

    const isAddFriendLinkOnboarding =
        onboardingEntrySource == "add-friend-link";

    return (
        <>
            <SpacePageMeta themeColor={onboardingGreen} preview="home" />
            <OnboardingScreen
                onCreateAccount={() => void router.push(spaceRoutes.signup)}
                onLogin={() => void router.push(spaceRoutes.login)}
                title={
                    isAddFriendLinkOnboarding
                        ? addFriendOnboardingTitle(pendingInviteUsername)
                        : undefined
                }
            />
        </>
    );
};

export default Page;
