import log from "ente-base/log";
import React, {
    useCallback,
    useEffect,
    useMemo,
    useRef,
    useState,
} from "react";
import type { SpaceLoginCredentials } from "screens/LoginScreen";
import type { SetupProfile } from "screens/SetupProfileScreen";
import { clearSpaceHomePostsMemoryCache } from "services/home-posts";
import type { PendingSpacePasskeyVerification } from "services/passkey-verification";
import { logoutRevokedSpaceSession } from "services/persistent-session";
import {
    clearCurrentSpaceContext,
    isSpaceSessionUnauthorized,
    loadCachedCurrentSpaceAvatar,
    loadExistingSpaceAvatar,
    loadExistingSpaceCover,
    loadExistingSpaceProfile,
} from "services/profile";
import {
    clearSpaceFriendsCache,
    clearSpaceMediaURLCache,
    createCurrentPhotoPost,
} from "services/space";
import {
    type OnboardingEntrySource,
    type PendingCreateProfile,
    type RefreshSpaceProfileOptions,
    type SpaceAppState,
    SpaceAppStateContext,
    type SpacePostPublication,
    type SpaceProfileLoadStatus,
    initialFriends,
} from "state/app-state";
import { prepareSpacePostImageFromEdit } from "utils/post-image";

export const SpaceAppStateProvider: React.FC<React.PropsWithChildren> = ({
    children,
}) => {
    const [cachedProfileAvatarUrl, setCachedProfileAvatarUrl] =
        useState<string>();
    const [friends, setFriends] = useState(initialFriends);
    const [isLiveSignupVerification, setIsLiveSignupVerification] =
        useState(false);
    const [onboardingEntrySource, setOnboardingEntrySource] =
        useState<OnboardingEntrySource>("direct");
    const [pendingLoginCredentials, setPendingLoginCredentials] =
        useState<SpaceLoginCredentials | null>(null);
    const [pendingPasskeyVerification, setPendingPasskeyVerification] =
        useState<PendingSpacePasskeyVerification | null>(null);
    const [pendingPostPhotoFile, setPendingPostPhotoFile] =
        useState<File | null>(null);
    const [pendingProfileAvatarFile, setPendingProfileAvatarFile] =
        useState<File | null>(null);
    const [pendingProfileCoverFile, setPendingProfileCoverFile] =
        useState<File | null>(null);
    const [pendingCreateProfile, setPendingCreateProfile] =
        useState<PendingCreateProfile | null>(null);
    const [profile, setProfile] = useState<SetupProfile | null>(null);
    const [profileLoadError, setProfileLoadError] = useState<string>();
    const [profileLoadStatus, setProfileLoadStatus] =
        useState<SpaceProfileLoadStatus>("loading");
    const [postPublication, setPostPublication] =
        useState<SpacePostPublication | null>(null);
    const [signupEmail, setSignupEmail] = useState("");
    const avatarURLRef = useRef<string | null>(null);
    const coverURLRef = useRef<string | null>(null);
    const profileRef = useRef<SetupProfile | null>(null);
    const profileLoadGenerationRef = useRef(0);
    const postPublishGenerationRef = useRef(0);

    const postPreviewUrl = postPublication?.previewUrl;
    useEffect(
        () => () => {
            if (postPreviewUrl) URL.revokeObjectURL(postPreviewUrl);
        },
        [postPreviewUrl],
    );

    const publishPost = useCallback(
        async (
            image: Parameters<SpaceAppState["publishPost"]>[0],
            caption: string,
        ) => {
            const profile = profileRef.current;
            const spaceId = profile?.spaceId;
            if (!spaceId) throw new Error("Missing space.");

            const generation = ++postPublishGenerationRef.current;
            let publication: SpacePostPublication = {
                phase: "posting",
                previewUrl: image.previewUrl,
                post: {
                    caption: caption.trim() || undefined,
                    friendID: spaceId,
                    height: image.height,
                    imageUrl: image.previewUrl,
                    name: profile.fullName,
                    postId: 0,
                    spaceId,
                    timestampMs: Date.now(),
                    viewerLiked: false,
                    width: image.width,
                },
            };
            setPostPublication(publication);
            try {
                const preparedImage = await prepareSpacePostImageFromEdit(
                    image.file,
                    image.cropArea,
                    image.rotationDegrees,
                );
                if (postPublishGenerationRef.current == generation) {
                    const previewUrl = URL.createObjectURL(preparedImage.file);
                    publication = {
                        ...publication,
                        previewUrl,
                        post: {
                            ...publication.post,
                            height: preparedImage.height,
                            imageUrl: previewUrl,
                            width: preparedImage.width,
                        },
                    };
                    setPostPublication(publication);
                }
                const post = await createCurrentPhotoPost({
                    caption,
                    file: preparedImage.file,
                    height: preparedImage.height,
                    spaceId,
                    thumbHash: preparedImage.thumbHash,
                    width: preparedImage.width,
                });
                if (postPublishGenerationRef.current == generation) {
                    setPostPublication({
                        ...publication,
                        phase: "posted",
                        post,
                    });
                }
                return post;
            } catch (error) {
                if (postPublishGenerationRef.current == generation) {
                    setPostPublication({ ...publication, phase: "failed" });
                }
                throw error;
            }
        },
        [],
    );

    const applyProfile = useCallback((nextProfile: SetupProfile | null) => {
        setCachedProfileAvatarUrl(undefined);
        const previousAvatarURL = avatarURLRef.current;
        if (previousAvatarURL && previousAvatarURL != nextProfile?.avatarUrl) {
            URL.revokeObjectURL(previousAvatarURL);
        }
        avatarURLRef.current = nextProfile?.avatarUrl?.startsWith("blob:")
            ? nextProfile.avatarUrl
            : null;
        const previousCoverURL = coverURLRef.current;
        if (previousCoverURL && previousCoverURL != nextProfile?.coverUrl) {
            URL.revokeObjectURL(previousCoverURL);
        }
        coverURLRef.current = nextProfile?.coverUrl?.startsWith("blob:")
            ? nextProfile.coverUrl
            : null;
        profileRef.current = nextProfile;
        setProfile(nextProfile);
    }, []);

    const loadProfileAvatar = useCallback(
        async (profileToHydrate: SetupProfile | null, generation: number) => {
            if (
                !profileToHydrate?.avatarObjectID ||
                !profileToHydrate.avatarKeyVersion ||
                profileToHydrate.avatarUrl
            ) {
                return;
            }

            try {
                const avatarUrl = await loadExistingSpaceAvatar(
                    profileToHydrate.spaceId,
                    profileToHydrate.avatarObjectID,
                    profileToHydrate.avatarKeyVersion,
                );
                if (!avatarUrl) return;

                const currentProfile = profileRef.current;
                if (
                    profileLoadGenerationRef.current != generation ||
                    !currentProfile ||
                    currentProfile.spaceId != profileToHydrate.spaceId ||
                    currentProfile.avatarObjectID !=
                        profileToHydrate.avatarObjectID ||
                    currentProfile.avatarKeyVersion !=
                        profileToHydrate.avatarKeyVersion
                ) {
                    URL.revokeObjectURL(avatarUrl);
                    return;
                }

                applyProfile({ ...currentProfile, avatarUrl });
            } catch (error) {
                log.warn("Failed to load space avatar", error);
            }
        },
        [applyProfile],
    );

    const loadProfileCover = useCallback(
        async (profileToHydrate: SetupProfile | null, generation: number) => {
            if (
                !profileToHydrate?.coverObjectID ||
                !profileToHydrate.coverKeyVersion ||
                profileToHydrate.coverUrl
            ) {
                return;
            }

            try {
                const coverUrl = await loadExistingSpaceCover(
                    profileToHydrate.spaceId,
                    profileToHydrate.coverObjectID,
                    profileToHydrate.coverKeyVersion,
                );
                if (!coverUrl) return;

                const currentProfile = profileRef.current;
                if (
                    profileLoadGenerationRef.current != generation ||
                    !currentProfile ||
                    currentProfile.spaceId != profileToHydrate.spaceId ||
                    currentProfile.coverObjectID !=
                        profileToHydrate.coverObjectID ||
                    currentProfile.coverKeyVersion !=
                        profileToHydrate.coverKeyVersion
                ) {
                    URL.revokeObjectURL(coverUrl);
                    return;
                }

                applyProfile({ ...currentProfile, coverUrl });
            } catch (error) {
                log.warn("Failed to load space cover", error);
            }
        },
        [applyProfile],
    );

    const refreshProfile = useCallback(
        async (options?: RefreshSpaceProfileOptions) => {
            const generation = ++profileLoadGenerationRef.current;
            setProfileLoadError(undefined);
            setProfileLoadStatus("loading");

            try {
                const [nextProfile, cachedAvatar] = await Promise.all([
                    loadExistingSpaceProfile({ force: true }),
                    loadCachedCurrentSpaceAvatar().then((cachedAvatar) => {
                        if (profileLoadGenerationRef.current == generation) {
                            setCachedProfileAvatarUrl(cachedAvatar?.avatarUrl);
                        }
                        return cachedAvatar;
                    }),
                ]);
                if (profileLoadGenerationRef.current == generation) {
                    const hydratedProfile =
                        nextProfile &&
                        cachedAvatar &&
                        cachedAvatar.spaceId == nextProfile.spaceId &&
                        cachedAvatar.objectID == nextProfile.avatarObjectID &&
                        cachedAvatar.keyVersion == nextProfile.avatarKeyVersion
                            ? {
                                  ...nextProfile,
                                  avatarUrl: cachedAvatar.avatarUrl,
                              }
                            : nextProfile;
                    setProfileLoadError(undefined);
                    applyProfile(hydratedProfile);
                    void loadProfileAvatar(hydratedProfile, generation);
                    void loadProfileCover(hydratedProfile, generation);
                    setProfileLoadStatus("ready");
                }
                return nextProfile;
            } catch (error) {
                if (isSpaceSessionUnauthorized(error)) {
                    await logoutRevokedSpaceSession();
                    window.location.replace("/");
                    return null;
                }
                log.error("Failed to load space profile", error);
                if (profileLoadGenerationRef.current == generation) {
                    setProfileLoadError(
                        "Couldn't load this page. Please try again later or contact support.",
                    );
                    setProfileLoadStatus("error");
                }
                if (options?.throwOnError) throw error;
                return null;
            }
        },
        [applyProfile, loadProfileAvatar, loadProfileCover],
    );

    const resetAfterLogout = useCallback(() => {
        profileLoadGenerationRef.current += 1;
        clearCurrentSpaceContext();
        clearSpaceFriendsCache();
        clearSpaceHomePostsMemoryCache();
        clearSpaceMediaURLCache();
        applyProfile(null);
        setProfileLoadError(undefined);
        setProfileLoadStatus("ready");
        postPublishGenerationRef.current += 1;
        setPostPublication(null);
        setPendingLoginCredentials(null);
        setPendingPasskeyVerification(null);
        setPendingPostPhotoFile(null);
        setPendingProfileAvatarFile(null);
        setPendingProfileCoverFile(null);
        setPendingCreateProfile(null);
        setOnboardingEntrySource("direct");
        setFriends(initialFriends());
    }, [applyProfile]);

    useEffect(() => {
        void refreshProfile();
    }, [refreshProfile]);

    const value = useMemo<SpaceAppState>(
        () => ({
            cachedProfileAvatarUrl,
            friends,
            isLiveSignupVerification,
            onboardingEntrySource,
            pendingLoginCredentials,
            pendingPasskeyVerification,
            pendingPostPhotoFile,
            pendingProfileAvatarFile,
            pendingProfileCoverFile,
            pendingCreateProfile,
            postPublication,
            profile,
            profileLoadError,
            profileLoadStatus,
            refreshProfile,
            resetAfterLogout,
            setPostPublication,
            publishPost,
            setFriends,
            setIsLiveSignupVerification,
            setOnboardingEntrySource,
            setPendingLoginCredentials,
            setPendingPasskeyVerification,
            setPendingPostPhotoFile,
            setPendingProfileAvatarFile,
            setPendingProfileCoverFile,
            setPendingCreateProfile,
            setProfile: applyProfile,
            setSignupEmail,
            signupEmail,
        }),
        [
            cachedProfileAvatarUrl,
            friends,
            isLiveSignupVerification,
            onboardingEntrySource,
            pendingLoginCredentials,
            pendingPasskeyVerification,
            pendingPostPhotoFile,
            pendingProfileAvatarFile,
            pendingProfileCoverFile,
            pendingCreateProfile,
            postPublication,
            profile,
            profileLoadError,
            profileLoadStatus,
            refreshProfile,
            resetAfterLogout,
            publishPost,
            signupEmail,
            applyProfile,
        ],
    );

    return (
        <SpaceAppStateContext.Provider value={value}>
            {children}
        </SpaceAppStateContext.Provider>
    );
};
