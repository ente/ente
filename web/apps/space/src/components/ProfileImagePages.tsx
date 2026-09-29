import { SpacePageMeta } from "components/PageMeta";
import { SpaceRouteFallback } from "components/RouteFallback";
import log from "ente-base/log";
import React, { useEffect } from "react";
import {
    EditProfileCoverScreen,
    EditProfilePhotoScreen,
} from "screens/EditProfilePhotoScreen";
import { ProfileImageViewerScreen } from "screens/ProfileImageViewerScreen";
import {
    removeSpaceProfileAvatar,
    removeSpaceProfileCover,
    saveSpaceProfile,
    spaceProfileErrorMessage,
} from "services/profile";
import { useSpaceAppState } from "state/app-state";
import { spaceAppBackgroundColor } from "styles/colors";
import { useSpaceRouter } from "utils/route-transitions";
import {
    type ProfileImageFlowSource,
    profileImageFlowSourceFromQuery,
    spaceRoutes,
} from "utils/routes";

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
    source == "settings" ? spaceRoutes.settings : spaceRoutes.profile;

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
        setProfile,
    } = useSpaceAppState();
    const imageFlowSource = profileImageFlowSourceFromQuery(router.query.from);
    const backRoute = savedRouteFor(imageFlowSource);

    useEffect(() => {
        if (profileLoadStatus == "ready" && !profile) {
            void router.replace(spaceRoutes.onboarding);
        }
    }, [profile, profileLoadStatus, router]);

    const removeProfileImage = async () => {
        if (!profile) return;
        try {
            const savedProfile =
                variant == "cover"
                    ? await removeSpaceProfileCover(profile)
                    : await removeSpaceProfileAvatar(profile);
            setProfile((currentProfile) => {
                if (
                    !currentProfile ||
                    currentProfile.spaceId != savedProfile.spaceId
                ) {
                    return currentProfile;
                }
                if (variant == "cover") {
                    return currentProfile.avatarObjectID ==
                        savedProfile.avatarObjectID &&
                        currentProfile.avatarKeyVersion ==
                            savedProfile.avatarKeyVersion
                        ? {
                              ...savedProfile,
                              avatarUrl: currentProfile.avatarUrl,
                          }
                        : savedProfile;
                }
                return currentProfile.coverObjectID ==
                    savedProfile.coverObjectID &&
                    currentProfile.coverKeyVersion ==
                        savedProfile.coverKeyVersion
                    ? { ...savedProfile, coverUrl: currentProfile.coverUrl }
                    : savedProfile;
            });
        } catch (error) {
            log.error("Space profile image removal failed", error);
            throw new Error(
                spaceProfileErrorMessage(
                    error,
                    `Couldn't remove your ${variant == "cover" ? "cover image" : "profile picture"}. Please try again.`,
                ),
                { cause: error },
            );
        }
        void router.push(backRoute).catch((error: unknown) => {
            log.error("Failed to return to Space profile", error);
        });
    };

    if (profileLoadStatus != "ready" || !profile) {
        return (
            <SpaceRouteFallback
                background={spaceAppBackgroundColor}
                message={profileLoadError}
            />
        );
    }

    return (
        <>
            <SpacePageMeta themeColor={spaceAppBackgroundColor} />
            <ProfileImageViewerScreen
                profile={profile}
                variant={variant}
                onBack={() => void router.push(backRoute)}
                onRemoveImage={
                    (
                        variant == "cover"
                            ? profile.coverObjectID
                            : profile.avatarObjectID
                    )
                        ? removeProfileImage
                        : undefined
                }
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
                background={spaceAppBackgroundColor}
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
            log.error(
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
            <SpacePageMeta themeColor={spaceAppBackgroundColor} />
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
