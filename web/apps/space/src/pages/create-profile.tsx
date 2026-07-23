import { SpacePageMeta } from "components/SpacePageMeta";
import { SpaceRouteFallback } from "components/SpaceRouteFallback";
import React, { useEffect, useMemo, useState } from "react";
import {
    SetupProfileScreen,
    setupProfileBackground,
} from "screens/SetupProfileScreen";
import {
    spaceUsernameAvailability,
    spaceUsernameValidationError,
} from "services/spaceProfile";
import { useSpaceAppState } from "state/spaceAppState";
import { acceptPendingSpaceInvite } from "utils/spacePendingInvite";
import { createProfileSourceFromQuery, spaceRoutes } from "utils/spaceRoutes";
import { useSpaceRouter } from "utils/spaceRouteTransitions";

const Page: React.FC = () => {
    const router = useSpaceRouter();
    const {
        onboardingEntrySource,
        pendingCreateProfile,
        profile,
        profileLoadError,
        profileLoadStatus,
        refreshProfile,
        setPendingCreateProfile,
    } = useSpaceAppState();
    const backSource = createProfileSourceFromQuery(router.query.from);
    const isAddFriendLinkOnboarding =
        onboardingEntrySource == "add-friend-link";
    const [draftUsername, setDraftUsername] = useState(
        pendingCreateProfile?.username ?? "",
    );
    const [usernameStatus, setUsernameStatus] = useState<
        "available" | "unavailable"
    >();
    const existingProfileRoute = useMemo(
        () =>
            isAddFriendLinkOnboarding || backSource == "login"
                ? spaceRoutes.home
                : spaceRoutes.invite,
        [backSource, isAddFriendLinkOnboarding],
    );

    useEffect(() => {
        if (router.isReady) void refreshProfile();
    }, [refreshProfile, router.isReady]);

    useEffect(() => {
        if (profileLoadStatus == "ready" && profile) {
            void acceptPendingSpaceInvite()
                .catch((error: unknown) =>
                    console.error("Failed to accept pending invite", error),
                )
                .finally(() => void router.replace(existingProfileRoute));
        }
    }, [existingProfileRoute, profile, profileLoadStatus, router]);

    useEffect(() => {
        if (profileLoadStatus != "ready" || profile) return;

        const username = draftUsername.trim();
        if (!username) {
            setUsernameStatus(undefined);
            return;
        }

        const validationError = spaceUsernameValidationError(username);
        if (validationError) {
            setUsernameStatus("unavailable");
            return;
        }

        setUsernameStatus(undefined);

        let cancelled = false;
        const timeout = window.setTimeout(() => {
            void spaceUsernameAvailability(username)
                .then((availability) => {
                    if (cancelled) return;
                    setUsernameStatus(
                        availability == "taken" ? "unavailable" : "available",
                    );
                })
                .catch((error: unknown) => {
                    console.error("Username availability check failed", error);
                    if (!cancelled) {
                        setUsernameStatus(undefined);
                    }
                });
        }, 350);

        return () => {
            cancelled = true;
            window.clearTimeout(timeout);
        };
    }, [draftUsername, profile, profileLoadStatus]);

    if (profileLoadStatus != "ready" || profile) {
        return (
            <SpaceRouteFallback
                background={setupProfileBackground}
                message={profileLoadError}
            />
        );
    }

    return (
        <>
            <SpacePageMeta themeColor={setupProfileBackground} />
            <SetupProfileScreen
                initialProfile={pendingCreateProfile}
                onBack={() =>
                    void router.push(
                        backSource == "login"
                            ? spaceRoutes.login
                            : spaceRoutes.verify,
                    )
                }
                onContinue={(nextProfile) => {
                    setPendingCreateProfile({
                        ...nextProfile,
                        source: backSource,
                    });
                    void router.push(spaceRoutes.addProfilePhoto);
                }}
                onUsernameChange={setDraftUsername}
                usernameStatus={usernameStatus}
            />
        </>
    );
};

export default Page;
