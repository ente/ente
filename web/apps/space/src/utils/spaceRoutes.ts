export type CreateProfileSource = "login" | "verify";
export type ProfileImageFlowSource = "profile" | "settings";
export type VerifyFlow = "login" | "signup";

const valueFromQuery = (value: string | string[] | undefined) =>
    Array.isArray(value) ? value[0] : value;

const routeWithProfileImageFlowSource = (
    route: string,
    source?: ProfileImageFlowSource,
) => (source == "settings" ? `${route}?from=settings` : route);

export const spaceRoutes = {
    friend: (spaceId: string) => `/app/friends/${encodeURIComponent(spaceId)}`,
    friends: "/app/friends",
    home: "/app",
    invite: "/invite",
    login: "/login",
    message: (spaceId: string) =>
        `/app/messages/${encodeURIComponent(spaceId)}`,
    messages: "/app/messages",
    onboarding: "/",
    passkeysFinish: "/passkeys/finish",
    passkeysVerify: "/passkeys/verify",
    post: (spaceId: string, postId: number) =>
        `/app/posts/${encodeURIComponent(spaceId)}/${encodeURIComponent(String(postId))}`,
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
    settingsProfile: "/app/settings/profile",
    settingsProfileName: "/app/settings/profile/name",
    createProfile: (from?: CreateProfileSource) =>
        from == "login" ? "/create-profile?from=login" : "/create-profile",
    addProfilePhoto: "/add-profile-photo",
    signup: "/signup",
    twoFactorVerify: "/two-factor/verify",
    verify: "/verify",
    verifyLogin: "/verify?flow=login",
} as const;

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
