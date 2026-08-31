import { SpacePageMeta } from "components/PageMeta";
import { SpaceRouteFallback } from "components/RouteFallback";
import log from "ente-base/log";
import React, { useEffect, useState } from "react";
import {
    SetupProfileScreen,
    setupProfileBackground,
} from "screens/SetupProfileScreen";
import { savedSpaceSessionToken } from "services/persistent-session";
import {
    spaceUsernameAvailability,
    spaceUsernameValidationError,
} from "services/profile";
import { useSpaceAppState } from "state/app-state";
import { sendPendingSpaceFriendRequest } from "utils/pending-friend-request";
import { useSpaceRouter } from "utils/route-transitions";
import { createProfileSourceFromQuery, spaceRoutes } from "utils/routes";

const Page: React.FC = () => {
    const router = useSpaceRouter();
    const {
        pendingCreateProfile,
        profile,
        profileLoadError,
        profileLoadStatus,
        refreshProfile,
        setPendingCreateProfile,
    } = useSpaceAppState();
    const backSource = createProfileSourceFromQuery(router.query.from);
    const [draftUsername, setDraftUsername] = useState(
        pendingCreateProfile?.username ?? "",
    );
    const [usernameStatus, setUsernameStatus] = useState<
        "available" | "unavailable"
    >();
    const [hasSpaceSession, setHasSpaceSession] = useState(false);
    useEffect(() => {
        if (!router.isReady) return;
        if (!savedSpaceSessionToken()) {
            void router.replace(spaceRoutes.onboarding);
            return;
        }

        setHasSpaceSession(true);
        void refreshProfile();
    }, [refreshProfile, router]);

    useEffect(() => {
        if (profileLoadStatus == "ready" && profile) {
            void sendPendingSpaceFriendRequest()
                .catch((error: unknown) =>
                    log.error("Failed to send pending friend request", error),
                )
                .finally(() => void router.replace(spaceRoutes.home));
        }
    }, [profile, profileLoadStatus, router]);

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
                    log.error("Username availability check failed", error);
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

    if (!hasSpaceSession || profileLoadStatus != "ready" || profile) {
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
