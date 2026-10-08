import { retryAsyncOperation } from "ente-base/http";
import log from "ente-base/log";
import { logToDisk } from "ente-base/log-web";
import React, {
    useCallback,
    useEffect,
    useMemo,
    useRef,
    useState,
} from "react";
import type { SpaceLoginCredentials } from "screens/LoginScreen";
import type { SetupProfile } from "screens/SetupProfileScreen";
import { clearSpaceFeedMemoryCache } from "services/feed-cache";
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
    createCurrentMediaPost,
    loadCurrentCreatedPost,
    type PreparedSpacePostMedia,
    type SpacePostUploadSession,
} from "services/space";
import {
    initialFriends,
    type LocalSpaceFeedPost,
    type OnboardingEntrySource,
    type PendingCreateProfile,
    type RefreshSpaceProfileOptions,
    type SpaceAppState,
    SpaceAppStateContext,
    type SpacePostPublication,
    type SpaceProfileLoadStatus,
} from "state/app-state";
import {
    confirmLocalFeedPost,
    createLocalFeedPostID,
    failLocalFeedPost,
} from "utils/local-feed-post";
import { prepareSpacePostImageFromEdit } from "utils/post-image";
import { spacePostFrameAspectRatio } from "utils/post-photos";
import { prepareSpaceVideo } from "utils/post-video";

const postStatusDurationMs = 2000;

export const SpaceAppStateProvider: React.FC<React.PropsWithChildren> = ({
    children,
}) => {
    const [cachedProfileAvatarUrl, setCachedProfileAvatarUrl] =
        useState<string>();
    const [friends, setFriends] = useState(initialFriends);
    const [localFeedPosts, setLocalFeedPosts] = useState<LocalSpaceFeedPost[]>(
        [],
    );
    const [isLiveSignupVerification, setIsLiveSignupVerification] =
        useState(false);
    const [onboardingEntrySource, setOnboardingEntrySource] =
        useState<OnboardingEntrySource>("direct");
    const [pendingLoginCredentials, setPendingLoginCredentials] =
        useState<SpaceLoginCredentials | null>(null);
    const [pendingPasskeyVerification, setPendingPasskeyVerification] =
        useState<PendingSpacePasskeyVerification | null>(null);
    const [pendingPostPhotoFiles, setPendingPostPhotoFiles] = useState<
        File[] | null
    >(null);
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
    const postReadbacksRef = useRef(new Map<string, () => Promise<void>>());
    const postPreparationsRef = useRef(new Map<string, AbortController>());
    const postUploadsRef = useRef(
        new Map<string, () => ReturnType<SpaceAppState["publishPost"]>>(),
    );

    useEffect(() => {
        const readbacks = postReadbacksRef.current;
        const uploads = postUploadsRef.current;
        const preparations = postPreparationsRef.current;
        const retryReadbacks = () => {
            readbacks.forEach((readback) => void readback());
        };
        window.addEventListener("online", retryReadbacks);
        window.addEventListener("focus", retryReadbacks);
        return () => {
            window.removeEventListener("online", retryReadbacks);
            window.removeEventListener("focus", retryReadbacks);
            readbacks.clear();
            uploads.clear();
            preparations.forEach((controller) => controller.abort());
            preparations.clear();
        };
    }, []);

    const previewURLsRef = useRef(new Set<string>());
    useEffect(() => {
        const urls = new Set(
            localFeedPosts.flatMap((item) =>
                item.status == "pending" || item.status == "failed"
                    ? [item.imageUrl]
                    : [],
            ),
        );
        if (postPublication?.previewUrl) urls.add(postPublication.previewUrl);
        previewURLsRef.current.forEach((url) => {
            if (!urls.has(url)) URL.revokeObjectURL(url);
        });
        previewURLsRef.current = urls;
    }, [localFeedPosts, postPublication?.previewUrl]);
    useEffect(
        () => () => {
            previewURLsRef.current.forEach((url) => URL.revokeObjectURL(url));
        },
        [],
    );

    const publishPost = useCallback(
        async (
            images: Parameters<SpaceAppState["publishPost"]>[0],
            caption: string,
        ) => {
            const profile = profileRef.current;
            const spaceId = profile?.spaceId;
            if (!spaceId) throw new Error("Missing space.");

            const cover = images[0]!;
            const previewUrl = cover.previewUrl;
            const localPostId = createLocalFeedPostID();
            const timestampMs = Date.now();
            setLocalFeedPosts((current) => [
                {
                    avatarUrl: profile.avatarUrl,
                    caption: caption.trim() || undefined,
                    frameAspectRatio: spacePostFrameAspectRatio(images),
                    friendID: spaceId,
                    height: cover.height,
                    id: localPostId,
                    imageUrl: previewUrl,
                    name: profile.fullName.trim() || profile.username.trim(),
                    photoCount: images.length,
                    spaceId,
                    status: "pending",
                    timestampMs,
                    width: cover.width,
                },
                ...current,
            ]);
            const publication: SpacePostPublication = {
                phase: "posting",
                previewUrl,
                post: {
                    caption: caption.trim() || undefined,
                    friendID: spaceId,
                    height: cover.height,
                    imageUrl: previewUrl,
                    name: profile.fullName,
                    postId: 0,
                    spaceId,
                    timestampMs,
                    viewerLiked: false,
                    width: cover.width,
                },
            };
            const prepared: PreparedSpacePostMedia[] = [];
            const videoCount = images.filter((image) => image.video).length;
            const mediaCounts = {
                photo: images.length - videoCount,
                video: videoCount,
            };
            const session: SpacePostUploadSession = {
                requestId: crypto.randomUUID(),
                uploads: [],
            };
            let pending: ReturnType<SpaceAppState["publishPost"]> | undefined;
            let attempt = 0;
            const upload = () => {
                if (pending) return pending;
                const generation = ++postPublishGenerationRef.current;
                const startedAt = Date.now();
                attempt += 1;
                const controller = new AbortController();
                const { signal } = controller;
                const cancelExports = () =>
                    images.forEach((image) => image.videoExport?.cancel());
                signal.addEventListener("abort", cancelExports, { once: true });
                postPreparationsRef.current.set(localPostId, controller);
                setPostPublication(publication);
                setLocalFeedPosts((current) =>
                    current.map((item) =>
                        item.id == localPostId && item.status == "failed"
                            ? {
                                  ...item,
                                  status: "pending",
                                  processing: undefined,
                              }
                            : item,
                    ),
                );
                pending = (async () => {
                    try {
                        const processingCounts = { photo: 0, video: 0 };
                        for (const [index, image] of images.entries()) {
                            signal.throwIfAborted();
                            const mediaType = image.video ? "video" : "photo";
                            const mediaIndex = ++processingCounts[mediaType];
                            if (prepared[index]) continue;
                            if (videoCount > 0 || images.length >= 3) {
                                const count = mediaCounts[mediaType];
                                const processing =
                                    images.length == 1
                                        ? "Processing"
                                        : `Processing ${mediaType}${count > 1 ? ` ${mediaIndex}/${count}` : ""}`;
                                setLocalFeedPosts((current) =>
                                    current.map((item) =>
                                        item.id == localPostId &&
                                        item.status == "pending"
                                            ? { ...item, processing }
                                            : item,
                                    ),
                                );
                            }
                            try {
                                prepared[index] = image.video
                                    ? await prepareSpaceVideo(
                                          image.file,
                                          image.video,
                                          signal,
                                          attempt == 1
                                              ? image.videoExport?.promise
                                              : undefined,
                                      )
                                    : await prepareSpacePostImageFromEdit(
                                          image.file,
                                          image.cropArea,
                                          image.rotationDegrees,
                                      );
                            } catch (error) {
                                const details =
                                    error instanceof Error
                                        ? {
                                              name: error.name,
                                              message: error.message,
                                              stack: error.stack,
                                          }
                                        : error;
                                logToDisk(
                                    `[error] Space post preparation failed request=${session.requestId} item=${index + 1}/${images.length} media=${image.video ? "video" : "photo"} bytes=${image.file.size} error=${JSON.stringify(details)}`.replaceAll(
                                        spaceId,
                                        "[space-id]",
                                    ),
                                );
                                throw error;
                            }
                        }
                        signal.throwIfAborted();
                        postPreparationsRef.current.delete(localPostId);
                        setLocalFeedPosts((current) =>
                            current.map((item) =>
                                item.id == localPostId &&
                                item.status == "pending"
                                    ? { ...item, processing: undefined }
                                    : item,
                            ),
                        );
                        if (!postUploadsRef.current.has(localPostId))
                            throw new DOMException("Canceled", "AbortError");
                        const postId = await createCurrentMediaPost({
                            caption,
                            images: prepared,
                            spaceId,
                            session,
                        });
                        const posted = { ...publication.post, postId };
                        postUploadsRef.current.delete(localPostId);
                        logToDisk(
                            `[info] Space post published request=${session.requestId} attempt=${attempt} elapsedMs=${Date.now() - startedAt}`,
                        );
                        if (profileRef.current?.spaceId != spaceId)
                            return posted;
                        setLocalFeedPosts((current) =>
                            current.map((item) =>
                                item.id == localPostId &&
                                item.status == "pending"
                                    ? { ...item, postId }
                                    : item,
                            ),
                        );
                        if (postPublishGenerationRef.current == generation) {
                            setPostPublication({
                                ...publication,
                                phase: "posted",
                                post: posted,
                                statusExpiresAtMs:
                                    Date.now() + postStatusDurationMs,
                            });
                        }
                        let reading = false;
                        const readback = async () => {
                            if (reading) return;
                            reading = true;
                            try {
                                const post = await retryAsyncOperation(
                                    () => {
                                        if (
                                            !postReadbacksRef.current.has(
                                                localPostId,
                                            )
                                        )
                                            throw new DOMException(
                                                "Canceled",
                                                "AbortError",
                                            );
                                        return loadCurrentCreatedPost(
                                            spaceId,
                                            session.postId!,
                                            prepared,
                                        );
                                    },
                                    {
                                        abortIfNeeded: (error) => {
                                            if (
                                                !postReadbacksRef.current.has(
                                                    localPostId,
                                                )
                                            )
                                                throw error;
                                        },
                                    },
                                );
                                if (!postReadbacksRef.current.has(localPostId))
                                    return;
                                post.avatarUrl = profile.avatarUrl;
                                postReadbacksRef.current.delete(localPostId);
                                confirmLocalFeedPost(
                                    setLocalFeedPosts,
                                    localPostId,
                                    post,
                                );
                                if (
                                    postPublishGenerationRef.current ==
                                    generation
                                )
                                    setPostPublication(
                                        (current) =>
                                            current && { ...current, post },
                                    );
                            } catch (error) {
                                log.warn(
                                    "Failed to refresh a published post",
                                    error,
                                );
                            } finally {
                                reading = false;
                            }
                        };
                        postReadbacksRef.current.set(localPostId, readback);
                        void readback();
                        return posted;
                    } catch (error) {
                        const details =
                            error instanceof Error
                                ? {
                                      name: error.name,
                                      message: error.message,
                                      stack: error.stack,
                                  }
                                : error;
                        logToDisk(
                            `[error] Space post failed request=${session.requestId} attempt=${attempt} elapsedMs=${Date.now() - startedAt} error=${JSON.stringify(details)}`.replaceAll(
                                spaceId,
                                "[space-id]",
                            ),
                        );
                        failLocalFeedPost(setLocalFeedPosts, localPostId);
                        if (postPublishGenerationRef.current == generation) {
                            setPostPublication({
                                ...publication,
                                phase: "failed",
                            });
                        }
                        throw error;
                    }
                })().finally(() => {
                    signal.removeEventListener("abort", cancelExports);
                    cancelExports();
                    postPreparationsRef.current.delete(localPostId);
                    pending = undefined;
                });
                return pending;
            };
            postUploadsRef.current.set(localPostId, upload);
            return upload();
        },
        [],
    );

    const retryPost = useCallback(async (localPostId: string) => {
        await postUploadsRef.current
            .get(localPostId)?.()
            .catch(() => undefined);
    }, []);

    const applyProfile = useCallback<SpaceAppState["setProfile"]>((update) => {
        const nextProfile =
            typeof update == "function" ? update(profileRef.current) : update;
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
        clearSpaceFeedMemoryCache();
        setLocalFeedPosts([]);
        clearSpaceMediaURLCache();
        applyProfile(null);
        setProfileLoadError(undefined);
        setProfileLoadStatus("ready");
        postPublishGenerationRef.current += 1;
        postReadbacksRef.current.clear();
        postUploadsRef.current.clear();
        postPreparationsRef.current.forEach((controller) => controller.abort());
        postPreparationsRef.current.clear();
        setPostPublication(null);
        setPendingLoginCredentials(null);
        setPendingPasskeyVerification(null);
        setPendingPostPhotoFiles(null);
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
            localFeedPosts,
            onboardingEntrySource,
            pendingLoginCredentials,
            pendingPasskeyVerification,
            pendingPostPhotoFiles,
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
            retryPost,
            setFriends,
            setLocalFeedPosts,
            setIsLiveSignupVerification,
            setOnboardingEntrySource,
            setPendingLoginCredentials,
            setPendingPasskeyVerification,
            setPendingPostPhotoFiles,
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
            localFeedPosts,
            onboardingEntrySource,
            pendingLoginCredentials,
            pendingPasskeyVerification,
            pendingPostPhotoFiles,
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
            retryPost,
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
