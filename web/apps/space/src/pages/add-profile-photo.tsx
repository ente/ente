import { SpacePageMeta } from "components/SpacePageMeta";
import { SpaceRouteFallback } from "components/SpaceRouteFallback";
import log from "ente-base/log";
import React, { useEffect, useState } from "react";
import { SetupProfilePhotoScreen } from "screens/SetupProfilePhotoScreen";
import { setupProfileBackground } from "screens/SetupProfileScreen";
import { savedPendingSpaceInvite } from "services/spaceInvite";
import {
    saveSpaceProfile,
    spaceProfileErrorMessage,
} from "services/spaceProfile";
import { useSpaceAppState } from "state/spaceAppState";
import { sendPendingSpaceFriendRequest } from "utils/spacePendingFriendRequest";
import { spaceRoutes } from "utils/spaceRoutes";
import { useSpaceRouter } from "utils/spaceRouteTransitions";

const Page: React.FC = () => {
    const router = useSpaceRouter();
    const {
        pendingCreateProfile,
        profile,
        profileLoadError,
        profileLoadStatus,
        setPendingCreateProfile,
        setProfile,
        setSkipNextHomeFeedSkeleton,
    } = useSpaceAppState();
    const createProfileSource = pendingCreateProfile?.source ?? "verify";
    const [setupError, setSetupError] = useState<string>();
    const [isSubmitting, setIsSubmitting] = useState(false);
    useEffect(() => {
        if (profileLoadStatus != "ready" || isSubmitting) {
            return;
        }

        if (profile) {
            void sendPendingSpaceFriendRequest()
                .catch((error: unknown) =>
                    log.error("Failed to send pending friend request", error),
                )
                .finally(() => void router.replace(spaceRoutes.home));
        } else if (!pendingCreateProfile) {
            void router.replace(spaceRoutes.createProfile());
        }
    }, [
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
                        setProfile(savedProfile);
                        setPendingCreateProfile(null);
                        const handledPendingFriendRequest =
                            await sendPendingSpaceFriendRequest();
                        if (!handledPendingFriendRequest) {
                            setSkipNextHomeFeedSkeleton(true);
                        }
                        await router.push(spaceRoutes.home);
                    } catch (error) {
                        log.error("Space profile setup failed", error);
                        setSetupError(spaceProfileErrorMessage(error));
                        setIsSubmitting(false);
                    }
                }}
            />
        </>
    );
};

export default Page;
