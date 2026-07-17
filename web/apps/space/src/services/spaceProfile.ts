import { savedPartialLocalUser } from "ente-accounts-rs/services/accounts-db";
import { clientPackageName, desktopAppVersion, isDesktop } from "ente-base/app";
import { apiOrigin, apiURL } from "ente-base/origins";
import type { SpaceAccountCtxHandle } from "ente-space-wasm";
import type {
    SetupProfile,
    SetupProfileInput,
} from "screens/SetupProfileScreen";
import {
    cachedSpaceMediaBlobURL,
    rememberCachedSpaceMediaBlobURL,
    spaceProfileMediaCacheKey,
} from "services/spaceMediaCache";
import {
    restoreSpaceBrowserSessionIfNeeded,
    savedSpaceSessionToken,
} from "services/spacePersistentSession";
import {
    parseSpaceProfilePayload,
    spaceProfileTextField,
} from "services/spaceProfilePayload";
import { spaceRootKeyFromSpaceSession } from "services/spaceSecureSessionStorage";

const usernamePattern = /^[a-z0-9][a-z0-9._]*$/;
const minUsernameLength = 4;
const maxUsernameLength = 30;

interface SpaceAvatar {
    keyVersion: number;
    objectID: string;
    size?: number;
    updatedAt?: string;
}

type SpaceCover = SpaceAvatar;

interface OwnedSpace {
    spaceId: string;
    spaceSlug: string;
}

interface CreatedSpace {
    spaceId: string;
    spaceSlug: string;
}

interface SpaceLookup {
    spaceId: string;
    spaceSlug: string;
}

interface DecryptedSpaceProfile {
    spaceId: string;
    spaceSlug: string;
    profile: string;
    avatar?: SpaceAvatar;
    cover?: SpaceCover;
    updatedAt?: string;
}

interface UpdateSpaceProfileResponse {
    avatar?: SpaceAvatar;
    cover?: SpaceCover;
}

export type UsernameAvailability = "available" | "taken";

export const normalizeSpaceUsername = (username: string) =>
    username.trim().toLowerCase();

export const spaceUsernameValidationError = (username: string) => {
    const normalized = normalizeSpaceUsername(username);
    if (normalized.length < minUsernameLength) {
        return "Username must be at least 4 characters.";
    }
    if (normalized.length > maxUsernameLength) {
        return "Username must be 30 characters or less.";
    }
    if (!usernamePattern.test(normalized)) {
        return "Use lowercase letters, numbers, dots, or underscores.";
    }
    if (normalized.startsWith("ente")) {
        return "This username is reserved.";
    }
    return undefined;
};

const spaceProfilePayloadFor = (profile: SetupProfileInput) =>
    JSON.stringify({
        displayName: profile.fullName.trim(),
        fullName: profile.fullName.trim(),
        username: normalizeSpaceUsername(profile.username),
    });

const spaceHTTPStatus = (error: unknown) => {
    if (!error || typeof error != "object" || !("status" in error)) {
        return undefined;
    }
    const { status } = error as { status?: unknown };
    return typeof status == "number" ? status : undefined;
};

const spaceHTTPCode = (error: unknown) => {
    if (!error || typeof error != "object" || !("code" in error)) {
        return undefined;
    }
    const { code } = error as { code?: unknown };
    return typeof code == "string" ? code : undefined;
};

export const isSpaceSessionUnauthorized = (error: unknown) =>
    spaceHTTPStatus(error) == 401;

const defaultOwnedSpace = (spaces: OwnedSpace[]) => spaces[0];

const currentSpaceContextConfig = async () => {
    await restoreSpaceBrowserSessionIfNeeded();
    const baseUrl = await apiOrigin();
    const spaceRootKeyB64 = spaceRootKeyFromSpaceSession();
    const user = savedPartialLocalUser();
    const spaceSessionToken = savedSpaceSessionToken();

    if (!spaceRootKeyB64 || !user?.id || !spaceSessionToken) {
        return undefined;
    }

    return {
        cacheKey: [user.id, baseUrl, spaceSessionToken].join(":"),
        input: {
            baseUrl,
            clientPackage: clientPackageName,
            clientVersion: isDesktop ? desktopAppVersion : undefined,
            spaceRootKeyB64,
            spaceSessionToken,
        },
    };
};

let currentSpaceContext:
    | { cacheKey: string; ctx: SpaceAccountCtxHandle }
    | undefined;
let pendingCurrentSpaceContext:
    | { cacheKey: string; promise: Promise<SpaceAccountCtxHandle> }
    | undefined;
let currentSpaceProfile:
    | { cacheKey: string; profile: SetupProfile | null }
    | undefined;
let pendingCurrentSpaceProfile:
    | { cacheKey: string; promise: Promise<SetupProfile | null> }
    | undefined;
let currentSpaceContextGeneration = 0;

const cloneSetupProfile = (profile: SetupProfile | null) =>
    profile ? { ...profile } : null;

export const openCurrentSpaceContext = async () => {
    const config = await currentSpaceContextConfig();
    if (!config) return undefined;

    const { spaceOpenAccountCtx } = await import("ente-space-wasm");
    return await spaceOpenAccountCtx(config.input);
};

export const clearCurrentSpaceContext = () => {
    const cached = currentSpaceContext;
    currentSpaceContextGeneration += 1;
    currentSpaceContext = undefined;
    pendingCurrentSpaceContext = undefined;
    currentSpaceProfile = undefined;
    pendingCurrentSpaceProfile = undefined;
    cached?.ctx.free();
};

export const ensureCurrentSpaceContext = async () => {
    const config = await currentSpaceContextConfig();
    if (!config) throw new Error("Please sign in again.");

    if (currentSpaceContext?.cacheKey == config.cacheKey) {
        return currentSpaceContext.ctx;
    }

    if (currentSpaceContext) {
        clearCurrentSpaceContext();
    }

    if (pendingCurrentSpaceContext?.cacheKey == config.cacheKey) {
        return await pendingCurrentSpaceContext.promise;
    }

    const generation = currentSpaceContextGeneration;
    const promise = (async () => {
        const { spaceOpenAccountCtx } = await import("ente-space-wasm");
        return await spaceOpenAccountCtx(config.input);
    })()
        .then((ctx) => {
            if (
                currentSpaceContextGeneration != generation ||
                pendingCurrentSpaceContext?.cacheKey != config.cacheKey
            ) {
                ctx.free();
                throw new Error("Space context changed.");
            }
            currentSpaceContext = { cacheKey: config.cacheKey, ctx };
            pendingCurrentSpaceContext = undefined;
            return ctx;
        })
        .catch((error: unknown) => {
            if (pendingCurrentSpaceContext?.cacheKey == config.cacheKey) {
                pendingCurrentSpaceContext = undefined;
            }
            throw error;
        });

    pendingCurrentSpaceContext = { cacheKey: config.cacheKey, promise };
    return await promise;
};

export const releaseCurrentSpaceContext = (_ctx: SpaceAccountCtxHandle) => {
    void _ctx;
    // Shared context is freed by clearCurrentSpaceContext on logout/session change.
};

const avatarURLForRemoteAvatar = async (
    ctx: SpaceAccountCtxHandle,
    spaceId: string,
    avatar: SpaceAvatar | undefined,
) => {
    if (!avatar?.objectID) return null;
    return await cachedSpaceMediaBlobURL(
        spaceProfileMediaCacheKey(
            spaceId,
            "avatar",
            avatar.objectID,
            avatar.keyVersion,
        ),
        () =>
            ctx.downloadSpaceAvatar(
                spaceId,
                spaceId,
                avatar.objectID,
                avatar.keyVersion,
            ),
    );
};

const coverURLForRemoteCover = async (
    ctx: SpaceAccountCtxHandle,
    spaceId: string,
    cover: SpaceCover | undefined,
) => {
    if (!cover?.objectID) return null;
    return await cachedSpaceMediaBlobURL(
        spaceProfileMediaCacheKey(
            spaceId,
            "cover",
            cover.objectID,
            cover.keyVersion,
        ),
        () =>
            ctx.downloadSpaceCover(
                spaceId,
                spaceId,
                cover.objectID,
                cover.keyVersion,
            ),
    );
};

const profileFromDecryptedSpaceProfile = (
    spaceProfile: DecryptedSpaceProfile,
): SetupProfile => {
    const payload = parseSpaceProfilePayload(spaceProfile.profile);
    const fullName =
        spaceProfileTextField(payload.fullName) ||
        spaceProfileTextField(payload.displayName) ||
        spaceProfile.spaceSlug;

    return {
        avatarKeyVersion: spaceProfile.avatar?.keyVersion,
        avatarObjectID: spaceProfile.avatar?.objectID,
        avatarUpdatedAt: spaceProfile.avatar?.updatedAt,
        avatarUrl: null,
        coverKeyVersion: spaceProfile.cover?.keyVersion,
        coverObjectID: spaceProfile.cover?.objectID,
        coverUpdatedAt: spaceProfile.cover?.updatedAt,
        coverUrl: null,
        fullName,
        username: spaceProfile.spaceSlug,
        spaceId: spaceProfile.spaceId,
        spaceSlug: spaceProfile.spaceSlug,
    };
};

export const loadExistingSpaceProfile = async (options?: {
    force?: boolean;
}) => {
    const config = await currentSpaceContextConfig();
    if (!config) return null;

    if (pendingCurrentSpaceProfile?.cacheKey == config.cacheKey) {
        return cloneSetupProfile(await pendingCurrentSpaceProfile.promise);
    }
    if (!options?.force && currentSpaceProfile?.cacheKey == config.cacheKey) {
        return cloneSetupProfile(currentSpaceProfile.profile);
    }

    const promise = (async () => {
        const ctx = await ensureCurrentSpaceContext();
        const spaces = (await ctx.listOwnedSpaces()) as OwnedSpace[];
        const space = defaultOwnedSpace(spaces);
        if (!space) return null;

        const spaceProfile = (await ctx.getSpaceProfile(
            space.spaceId,
            space.spaceId,
        )) as DecryptedSpaceProfile;
        return profileFromDecryptedSpaceProfile(spaceProfile);
    })();

    const pendingProfile = { cacheKey: config.cacheKey, promise };
    pendingCurrentSpaceProfile = pendingProfile;
    try {
        const profile = await promise;
        if (pendingCurrentSpaceProfile == pendingProfile) {
            currentSpaceProfile = { cacheKey: config.cacheKey, profile };
        }
        return cloneSetupProfile(profile);
    } finally {
        if (pendingCurrentSpaceProfile == pendingProfile) {
            pendingCurrentSpaceProfile = undefined;
        }
    }
};

export const loadExistingSpaceAvatar = async (
    spaceId: string | undefined,
    avatarObjectID: string | undefined,
    avatarKeyVersion: number | undefined,
) => {
    if (!spaceId || !avatarObjectID || !avatarKeyVersion) return null;

    const ctx = await openCurrentSpaceContext();
    if (!ctx) return null;

    try {
        return await avatarURLForRemoteAvatar(ctx, spaceId, {
            keyVersion: avatarKeyVersion,
            objectID: avatarObjectID,
        });
    } finally {
        ctx.free();
    }
};

export const loadExistingSpaceCover = async (
    spaceId: string | undefined,
    coverObjectID: string | undefined,
    coverKeyVersion: number | undefined,
) => {
    if (!spaceId || !coverObjectID || !coverKeyVersion) return null;

    const ctx = await openCurrentSpaceContext();
    if (!ctx) return null;

    try {
        return await coverURLForRemoteCover(ctx, spaceId, {
            keyVersion: coverKeyVersion,
            objectID: coverObjectID,
        });
    } finally {
        ctx.free();
    }
};

export const spaceUsernameAvailability = async (
    username: string,
): Promise<UsernameAvailability> => {
    const validationError = spaceUsernameValidationError(username);
    if (validationError) return "taken";

    const slug = normalizeSpaceUsername(username);
    const response = await fetch(
        await apiURL(
            `/space/public/slug-availability/${encodeURIComponent(slug)}`,
        ),
    );
    if (!response.ok) {
        throw new Error("Username availability check failed.");
    }
    const { available } = (await response.json()) as { available?: unknown };
    return available === true ? "available" : "taken";
};

export const saveSpaceProfile = async (
    profile: SetupProfileInput,
    referredBySpaceId?: string,
): Promise<SetupProfile> => {
    const username = normalizeSpaceUsername(profile.username);

    const ctx = await ensureCurrentSpaceContext();
    try {
        const spaces = (await ctx.listOwnedSpaces()) as OwnedSpace[];
        const existingSpace =
            (profile.spaceId &&
                spaces.find((space) => space.spaceId == profile.spaceId)) ||
            defaultOwnedSpace(spaces);
        if (
            normalizeSpaceUsername(existingSpace?.spaceSlug ?? "") != username
        ) {
            const usernameError = spaceUsernameValidationError(username);
            if (usernameError) throw new Error(usernameError);
        }
        const profilePayload = spaceProfilePayloadFor({ ...profile, username });

        let spaceId: string;
        let spaceSlug = username;
        let updateResponse: UpdateSpaceProfileResponse | undefined;

        if (existingSpace) {
            spaceId = existingSpace.spaceId;
            spaceSlug = existingSpace.spaceSlug;
            if (normalizeSpaceUsername(spaceSlug) != username) {
                const updatedSlug = (await ctx.updateSpaceSlug(
                    spaceId,
                    username,
                )) as SpaceLookup;
                spaceSlug = updatedSlug.spaceSlug;
            }
        } else {
            const created = (await ctx.createSpace(
                username,
                profilePayload,
                referredBySpaceId?.trim() || undefined,
            )) as CreatedSpace;
            spaceId = created.spaceId;
            spaceSlug = created.spaceSlug;
        }

        let avatarUrl = profile.avatarUrl ?? null;
        let coverUrl = profile.coverUrl ?? null;
        if (profile.avatarFile) {
            const avatarBytes = new Uint8Array(
                await profile.avatarFile.arrayBuffer(),
            );
            updateResponse = (await ctx.updateSpaceProfileWithAvatar(
                spaceId,
                profilePayload,
                avatarBytes,
            )) as UpdateSpaceProfileResponse;
            avatarUrl = updateResponse.avatar?.objectID
                ? await rememberCachedSpaceMediaBlobURL(
                      spaceProfileMediaCacheKey(
                          spaceId,
                          "avatar",
                          updateResponse.avatar.objectID,
                          updateResponse.avatar.keyVersion,
                      ),
                      profile.avatarFile,
                  )
                : URL.createObjectURL(profile.avatarFile);
        } else if (profile.coverFile) {
            const coverBytes = new Uint8Array(
                await profile.coverFile.arrayBuffer(),
            );
            updateResponse = (await ctx.updateSpaceProfileWithCover(
                spaceId,
                profilePayload,
                coverBytes,
            )) as UpdateSpaceProfileResponse;
            coverUrl = updateResponse.cover?.objectID
                ? await rememberCachedSpaceMediaBlobURL(
                      spaceProfileMediaCacheKey(
                          spaceId,
                          "cover",
                          updateResponse.cover.objectID,
                          updateResponse.cover.keyVersion,
                      ),
                      profile.coverFile,
                  )
                : URL.createObjectURL(profile.coverFile);
        } else if (existingSpace) {
            updateResponse = (await ctx.updateSpaceProfile(
                spaceId,
                profilePayload,
            )) as UpdateSpaceProfileResponse;
        }

        const savedProfile = {
            avatarKeyVersion:
                updateResponse?.avatar?.keyVersion ?? profile.avatarKeyVersion,
            avatarObjectID:
                updateResponse?.avatar?.objectID ?? profile.avatarObjectID,
            avatarUpdatedAt:
                updateResponse?.avatar?.updatedAt ?? profile.avatarUpdatedAt,
            avatarUrl,
            coverKeyVersion:
                updateResponse?.cover?.keyVersion ?? profile.coverKeyVersion,
            coverObjectID:
                updateResponse?.cover?.objectID ?? profile.coverObjectID,
            coverUpdatedAt:
                updateResponse?.cover?.updatedAt ?? profile.coverUpdatedAt,
            coverUrl,
            fullName: profile.fullName.trim(),
            username: spaceSlug,
            spaceId,
            spaceSlug,
        };
        currentSpaceProfile = undefined;
        pendingCurrentSpaceProfile = undefined;
        return savedProfile;
    } catch (error) {
        if (spaceHTTPCode(error) == "ALREADY_EXISTS") {
            throw new Error("This username is already taken.", {
                cause: error,
            });
        }
        if (spaceHTTPCode(error) == "CONFLICT") {
            throw new Error(
                "A Space already exists for this account. Please refresh and try again.",
                { cause: error },
            );
        }
        throw error;
    } finally {
        releaseCurrentSpaceContext(ctx);
    }
};

export const spaceProfileErrorMessage = (error: unknown) => {
    const code = spaceHTTPCode(error);
    if (code == "ALREADY_EXISTS") return "This username is already taken.";
    if (code == "CONFLICT") {
        return "A Space already exists for this account. Please refresh and try again.";
    }
    const status = spaceHTTPStatus(error);
    if (status == 409) {
        return "This profile conflicts with the current account state. Please refresh and try again.";
    }
    if (status == 400) {
        const message = error instanceof Error ? error.message : "";
        if (message.toLowerCase().includes("reserved")) {
            return "This username is reserved.";
        }
        return "That username is not available. Please choose another.";
    }
    if (status == 401) return "Your session expired. Please sign in again.";
    if (status == 403) return "You do not have access to update this profile.";
    return error instanceof Error
        ? error.message
        : "Couldn't save your profile. Please try again.";
};
