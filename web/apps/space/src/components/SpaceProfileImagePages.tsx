import { SpacePageMeta } from "components/SpacePageMeta";
import { SpaceRouteFallback } from "components/SpaceRouteFallback";
import React, { useEffect } from "react";
import {
    EditProfileCoverScreen,
    EditProfilePhotoScreen,
} from "screens/EditProfilePhotoScreen";
import { ProfileImageViewerScreen } from "screens/ProfileImageViewerScreen";
import { profileBackground } from "screens/ProfileScreen";
import {
    saveSpaceProfile,
    spaceProfileErrorMessage,
} from "services/spaceProfile";
import { useSpaceAppState } from "state/spaceAppState";
import {
    type ProfileImageFlowSource,
    profileImageFlowSourceFromQuery,
    spaceRoutes,
} from "utils/spaceRoutes";
import { useSpaceRouter } from "utils/spaceRouteTransitions";

type ProfileImageVariant = "avatar" | "cover";

const profileRouteFor = (
    variant: ProfileImageVariant,
    source: ProfileImageFlowSource,
) =>
    variant == "cover"
        ? spaceRoutes.profileCoverFrom(source)
        : spaceRoutes.profilePhotoFrom(source);

const editProfileRouteFor = (
    variant: ProfileImageVariant,
    source: ProfileImageFlowSource,
) =>
    variant == "cover"
        ? spaceRoutes.editProfileCoverFrom(source)
        : spaceRoutes.editProfilePhotoFrom(source);

const savedRouteFor = (source: ProfileImageFlowSource) =>
    source == "settings" ? spaceRoutes.settingsProfile : spaceRoutes.profile;

export const SpaceProfileImageViewerPage: React.FC<{
    variant: ProfileImageVariant;
}> = ({ variant }) => {
    const router = useSpaceRouter();
    const {
        profile,
        profileLoadError,
        profileLoadStatus,
        setPendingProfileAvatarFile,
        setPendingProfileCoverFile,
    } = useSpaceAppState();
    const imageFlowSource = profileImageFlowSourceFromQuery(router.query.from);
    const backRoute = savedRouteFor(imageFlowSource);

    useEffect(() => {
        if (profileLoadStatus == "ready" && !profile) {
            void router.replace(spaceRoutes.onboarding);
        }
    }, [profile, profileLoadStatus, router]);

    if (profileLoadStatus != "ready" || !profile) {
        return (
            <SpaceRouteFallback
                background={profileBackground}
                message={profileLoadError}
            />
        );
    }

    return (
        <>
            <SpacePageMeta themeColor={profileBackground} />
            <ProfileImageViewerScreen
                profile={profile}
                variant={variant}
                onBack={() => void router.push(backRoute)}
                onSelectFile={(file) => {
                    if (variant == "cover") {
                        setPendingProfileCoverFile(file);
                    } else {
                        setPendingProfileAvatarFile(file);
                    }
                    void router.push(
                        editProfileRouteFor(variant, imageFlowSource),
                    );
                }}
            />
        </>
    );
};

export const SpaceProfileImageEditPage: React.FC<{
    variant: ProfileImageVariant;
}> = ({ variant }) => {
    const router = useSpaceRouter();
    const {
        pendingProfileAvatarFile,
        pendingProfileCoverFile,
        profile,
        profileLoadError,
        profileLoadStatus,
        setPendingProfileAvatarFile,
        setPendingProfileCoverFile,
        setProfile,
    } = useSpaceAppState();
    const imageFlowSource = profileImageFlowSourceFromQuery(router.query.from);
    const profileImageRoute = profileRouteFor(variant, imageFlowSource);
    const savedRoute = savedRouteFor(imageFlowSource);
    const pendingFile =
        variant == "cover" ? pendingProfileCoverFile : pendingProfileAvatarFile;

    useEffect(() => {
        if (profileLoadStatus == "ready" && !profile) {
            void router.replace(spaceRoutes.onboarding);
        }
    }, [profile, profileLoadStatus, router]);

    useEffect(() => {
        if (profileLoadStatus == "ready" && profile && !pendingFile) {
            void router.replace(profileImageRoute);
        }
    }, [pendingFile, profile, profileImageRoute, profileLoadStatus, router]);

    if (profileLoadStatus != "ready" || !profile || !pendingFile) {
        return (
            <SpaceRouteFallback
                background={profileBackground}
                message={profileLoadError}
            />
        );
    }

    const clearPendingFile = () => {
        if (variant == "cover") {
            setPendingProfileCoverFile(null);
        } else {
            setPendingProfileAvatarFile(null);
        }
    };

    const saveProfileImage = async (file: File) => {
        try {
            const savedProfile = await saveSpaceProfile(
                variant == "cover"
                    ? { ...profile, coverFile: file }
                    : { ...profile, avatarFile: file },
            );
            setProfile(savedProfile);
            await router.push(savedRoute);
            clearPendingFile();
        } catch (error) {
            console.error(
                variant == "cover"
                    ? "Space cover update failed"
                    : "Space avatar update failed",
                error,
            );
            throw new Error(spaceProfileErrorMessage(error), { cause: error });
        }
    };

    const handleBack = () => {
        clearPendingFile();
        void router.push(profileImageRoute);
    };

    return (
        <>
            <SpacePageMeta themeColor={profileBackground} />
            {variant == "cover" ? (
                <EditProfileCoverScreen
                    coverFile={pendingFile}
                    onBack={handleBack}
                    onSave={saveProfileImage}
                />
            ) : (
                <EditProfilePhotoScreen
                    avatarFile={pendingFile}
                    onBack={handleBack}
                    onSave={saveProfileImage}
                />
            )}
        </>
    );
};
