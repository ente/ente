export type CreateProfileSource = "login" | "verify";
export type ProfileImageFlowSource = "profile" | "settings";
export type VerifyFlow = "login" | "signup";

const valueFromQuery = (value: string | string[] | undefined) =>
    Array.isArray(value) ? value[0] : value;

const routeWithProfileImageFlowSource = (
    route: string,
    source?: ProfileImageFlowSource,
) => (source == "settings" ? `${route}?from=settings` : route);

export const postPhotoIdFromObjectKey = (objectKey: string) =>
    objectKey.slice(objectKey.lastIndexOf("/") + 1);

export const spaceRoutes = {
    friend: (username: string) => `/${encodeURIComponent(username)}`,
    friendPage: "/profile-link",
    friends: "/app/friends",
    home: "/app",
    login: "/login",
    message: (spaceId: string) =>
        `/app/messages/${encodeURIComponent(spaceId)}`,
    messages: "/app/messages",
    notifications: "/app/notifications",
    onboarding: "/",
    passkeysFinish: "/passkeys/finish",
    passkeysVerify: "/passkeys/verify",
    post: (spaceId: string, postId: number, objectKey?: string) =>
        `/app/posts/${encodeURIComponent(spaceId)}/${encodeURIComponent(String(postId))}${objectKey === undefined ? "" : `?photo=${encodeURIComponent(postPhotoIdFromObjectKey(objectKey))}`}`,
    editProfileCover: "/app/profile/cover-edit",
    editProfileCoverFrom: (source?: ProfileImageFlowSource) =>
        routeWithProfileImageFlowSource("/app/profile/cover-edit", source),
    editProfilePhoto: "/app/profile/photo-edit",
    editProfilePhotoFrom: (source?: ProfileImageFlowSource) =>
        routeWithProfileImageFlowSource("/app/profile/photo-edit", source),
    profile: "/app/profile",
    profileCover: "/app/profile/cover",
    profileCoverFrom: (source?: ProfileImageFlowSource) =>
        routeWithProfileImageFlowSource("/app/profile/cover", source),
    profilePhoto: "/app/profile/photo",
    profilePhotoFrom: (source?: ProfileImageFlowSource) =>
        routeWithProfileImageFlowSource("/app/profile/photo", source),
    settings: "/app/settings",
    settingsProfileName: "/app/settings/profile/name",
    createProfile: (from?: CreateProfileSource) =>
        from == "login" ? "/create-profile?from=login" : "/create-profile",
    addProfilePhoto: "/add-profile-photo",
    signup: "/signup",
    twoFactorVerify: "/two-factor/verify",
    verify: "/verify",
    verifyLogin: "/verify?flow=login",
} as const;

export const spaceBackFallback = (asPath: string, page = asPath) => {
    const [path = "/", search = ""] = asPath.split("?", 2);
    if (page == spaceRoutes.friendPage) return spaceRoutes.home;
    if (path.startsWith("/app/messages/")) return spaceRoutes.messages;
    if (path.startsWith("/app/posts/")) return spaceRoutes.home;

    const source = profileImageFlowSourceFromQuery(
        new URLSearchParams(search).get("from") ?? undefined,
    );
    if (path == spaceRoutes.profilePhoto || path == spaceRoutes.profileCover)
        return source == "settings"
            ? spaceRoutes.settings
            : spaceRoutes.profile;
    if (path == spaceRoutes.editProfilePhoto)
        return spaceRoutes.profilePhotoFrom(source);
    if (path == spaceRoutes.editProfileCover)
        return spaceRoutes.profileCoverFrom(source);

    return (
        {
            [spaceRoutes.friends]: spaceRoutes.home,
            [spaceRoutes.messages]: spaceRoutes.home,
            [spaceRoutes.notifications]: spaceRoutes.home,
            [spaceRoutes.profile]: spaceRoutes.home,
            [spaceRoutes.settings]: spaceRoutes.home,
            [spaceRoutes.settingsProfileName]: spaceRoutes.settings,
            "/app/post": spaceRoutes.home,
        } as Record<string, string | undefined>
    )[path];
};

export const verifyFlowFromQuery = (
    value: string | string[] | undefined,
): VerifyFlow => (valueFromQuery(value) == "login" ? "login" : "signup");

export const createProfileSourceFromQuery = (
    value: string | string[] | undefined,
): CreateProfileSource =>
    valueFromQuery(value) == "login" ? "login" : "verify";

export const profileImageFlowSourceFromQuery = (
    value: string | string[] | undefined,
): ProfileImageFlowSource =>
    valueFromQuery(value) == "settings" ? "settings" : "profile";

export const friendSpaceIdFromQuery = (value: string | string[] | undefined) =>
    valueFromQuery(value) ?? "";
