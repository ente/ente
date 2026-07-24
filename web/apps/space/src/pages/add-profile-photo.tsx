import { SpacePageMeta } from "components/SpacePageMeta";
import { SpaceRouteFallback } from "components/SpaceRouteFallback";
import React, { useEffect, useMemo, useState } from "react";
import { SetupProfilePhotoScreen } from "screens/SetupProfilePhotoScreen";
import { setupProfileBackground } from "screens/SetupProfileScreen";
import { savedPendingSpaceInvite } from "services/spaceInvite";
import {
    saveSpaceProfile,
    spaceProfileErrorMessage,
} from "services/spaceProfile";
import { useSpaceAppState } from "state/spaceAppState";
import { acceptPendingSpaceInvite } from "utils/spacePendingInvite";
import { spaceRoutes } from "utils/spaceRoutes";
import { useSpaceRouter } from "utils/spaceRouteTransitions";

const Page: React.FC = () => {
    const router = useSpaceRouter();
    const {
        onboardingEntrySource,
        pendingCreateProfile,
        profile,
        profileLoadError,
        profileLoadStatus,
        setPendingCreateProfile,
        setProfile,
        setSkipNextHomeFeedSkeleton,
    } = useSpaceAppState();
    const createProfileSource = pendingCreateProfile?.source ?? "verify";
    const isAddFriendLinkOnboarding =
        onboardingEntrySource == "add-friend-link";
    const [setupError, setSetupError] = useState<string>();
    const [isSubmitting, setIsSubmitting] = useState(false);
    const existingProfileRoute = useMemo(
        () =>
            isAddFriendLinkOnboarding || createProfileSource == "login"
                ? spaceRoutes.home
                : spaceRoutes.invite,
        [createProfileSource, isAddFriendLinkOnboarding],
    );

    useEffect(() => {
        if (profileLoadStatus != "ready" || isSubmitting) {
            return;
        }

        if (profile) {
            void acceptPendingSpaceInvite()
                .catch((error: unknown) =>
                    console.error("Failed to accept pending invite", error),
                )
                .finally(() => void router.replace(existingProfileRoute));
        } else if (!pendingCreateProfile) {
            void router.replace(spaceRoutes.createProfile());
        }
    }, [
        existingProfileRoute,
        isSubmitting,
        pendingCreateProfile,
        profile,
        profileLoadStatus,
        router,
    ]);

    if (profileLoadStatus != "ready" || profile || !pendingCreateProfile) {
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
            <SetupProfilePhotoScreen
                errorMessage={setupError}
                isSubmitting={isSubmitting}
                onBack={() =>
                    void router.push(
                        spaceRoutes.createProfile(createProfileSource),
                    )
                }
                onContinue={async (avatarFile) => {
                    setIsSubmitting(true);
                    setSetupError(undefined);
                    try {
                        const savedProfile = await saveSpaceProfile(
                            {
                                avatarFile,
                                avatarUrl: null,
                                fullName: pendingCreateProfile.fullName,
                                username: pendingCreateProfile.username,
                            },
                            savedPendingSpaceInvite()?.spaceId,
                        );
                        const acceptedInvite = await acceptPendingSpaceInvite();
                        setProfile(savedProfile);
                        setPendingCreateProfile(null);
                        if (!acceptedInvite) {
                            setSkipNextHomeFeedSkeleton(true);
                        }
                        await router.push(
                            isAddFriendLinkOnboarding
                                ? spaceRoutes.home
                                : spaceRoutes.invite,
                        );
                    } catch (error) {
                        console.error("Space profile setup failed", error);
                        setSetupError(spaceProfileErrorMessage(error));
                        setIsSubmitting(false);
                    }
                }}
            />
        </>
    );
};

export default Page;
