import {
    replaceSavedLocalUser,
    savedPartialLocalUser,
} from "ente-accounts/services/accounts-db";
import { accountLogout } from "ente-accounts/services/logout";
import { ensureOk, publicRequestHeaders } from "ente-base/http";
import log from "ente-base/log";
import { apiURL } from "ente-base/origins";
import { removeAuthToken } from "ente-base/token";
import {
    decryptBox,
    encryptBox,
    generateKey,
    type SpaceKeyResponse,
} from "ente-space-wasm";
import { spaceBootstrapAuthHeaders } from "services/bootstrap-auth";
import {
    clearSpaceSecureSessionStorage,
    saveSpaceRootKeyInSpaceSession,
    spaceRootKeyFromSpaceSession,
} from "services/secure-session-storage";
import { z } from "zod";

const spaceBrowserSessionStorageKey = "spaceBrowserSession";
export const spaceSessionTokenHeader = "X-Space-Session-Token";

const OwnedSpace = z.object({
    spaceId: z.string(),
    spaceSlug: z.string(),
    rootWrappedSpaceKey: z.string(),
    publicKey: z.string().default(""),
    encryptedSecretKey: z.string().default(""),
    encryptedProfile: z.string().default(""),
    keyVersion: z.number(),
});
const OwnedSpaces = OwnedSpace.array();

const SpaceProfileAvatar = z.object({
    keyVersion: z.number(),
    objectID: z.string(),
    spaceId: z.string(),
});
export type SpaceProfileAvatar = z.infer<typeof SpaceProfileAvatar>;

const PersistedSpaceBrowserSession = z.object({
    encryptedSpaceRootKey: z.string(),
    email: z.string(),
    nonce: z.string(),
    ownedSpaces: OwnedSpaces.optional(),
    profileAvatar: SpaceProfileAvatar.optional(),
    sessionToken: z.string(),
    userId: z.number(),
});

const SpaceBrowserSessionResponse = z.object({ sessionToken: z.string() });

const SpaceBrowserSessionBootstrapResponse = z.object({
    sessionWrapKey: z.string(),
});

const SpaceEntityKeyResponse = z.object({
    encryptedKey: z.string(),
    header: z.string(),
});

const savedPersistedSession = () => {
    const value = localStorage.getItem(spaceBrowserSessionStorageKey);
    if (!value) return undefined;
    let parsed: unknown;
    try {
        parsed = JSON.parse(value);
    } catch {
        clearSpaceBrowserSession();
        return undefined;
    }
    const { data, success } = PersistedSpaceBrowserSession.safeParse(parsed);
    if (success) return data;
    clearSpaceBrowserSession();
    return undefined;
};

export const clearSpaceBrowserSession = () => {
    localStorage.removeItem(spaceBrowserSessionStorageKey);
    clearSpaceSecureSessionStorage();
};

export const logoutRevokedSpaceSession = async () => {
    clearSpaceBrowserSession();
    await accountLogout();
};

export const savedSpaceSessionToken = () =>
    savedPersistedSession()?.sessionToken;

export const savedSpaceOwnedSpaces = () => savedPersistedSession()?.ownedSpaces;

export const savedSpaceProfileAvatar = () =>
    savedPersistedSession()?.profileAvatar;

export const saveSpaceOwnedSpaces = (
    sessionToken: string,
    ownedSpaces: SpaceKeyResponse[],
) => {
    const persisted = savedPersistedSession();
    if (persisted?.sessionToken != sessionToken) return;
    localStorage.setItem(
        spaceBrowserSessionStorageKey,
        JSON.stringify({
            ...persisted,
            ownedSpaces: ownedSpaces.length ? ownedSpaces : undefined,
        }),
    );
};

export const saveSpaceProfileAvatar = (
    sessionToken: string,
    profileAvatar: SpaceProfileAvatar | undefined,
) => {
    const persisted = savedPersistedSession();
    if (persisted?.sessionToken != sessionToken) return;
    localStorage.setItem(
        spaceBrowserSessionStorageKey,
        JSON.stringify({ ...persisted, profileAvatar }),
    );
};

const forgetBootstrapToken = async () => {
    const user = savedPartialLocalUser();
    if (user?.id && user.email) {
        replaceSavedLocalUser({ id: user.id, email: user.email });
    }
    await removeAuthToken();
};

export const createSpaceBrowserSession = async (
    spaceRootKey: string,
    authToken: string,
) => {
    const sessionWrapKey = await generateKey();
    const res = await fetch(await apiURL("/account/space/sessions"), {
        method: "POST",
        headers: {
            ...spaceBootstrapAuthHeaders(authToken),
            "Content-Type": "application/json",
        },
        body: JSON.stringify({ sessionWrapKey }),
    });
    ensureOk(res);
    const { sessionToken } = SpaceBrowserSessionResponse.parse(
        await res.json(),
    );

    const user = savedPartialLocalUser();
    if (!user?.id || !user.email) {
        throw new Error("Space user is missing.");
    }
    const box = await encryptBox(spaceRootKey, sessionWrapKey);
    localStorage.setItem(
        spaceBrowserSessionStorageKey,
        JSON.stringify({
            encryptedSpaceRootKey: box.encryptedData,
            email: user.email,
            nonce: box.nonce,
            sessionToken,
            userId: user.id,
        }),
    );
    saveSpaceRootKeyInSpaceSession(spaceRootKey);
    await forgetBootstrapToken();
};

let pendingRestore: Promise<boolean> | undefined;

export const restoreSpaceBrowserSessionIfNeeded = async () => {
    if (
        spaceRootKeyFromSpaceSession() &&
        savedPartialLocalUser()?.id &&
        savedSpaceSessionToken()
    ) {
        return true;
    }
    pendingRestore ??= restoreSpaceBrowserSession().finally(() => {
        pendingRestore = undefined;
    });
    return pendingRestore;
};

const restoreSpaceBrowserSession = async () => {
    const persisted = savedPersistedSession();
    if (!persisted) return false;

    const res = await fetch(await apiURL("/account/space/sessions/bootstrap"), {
        method: "POST",
        headers: {
            ...publicRequestHeaders(),
            [spaceSessionTokenHeader]: persisted.sessionToken,
        },
    });
    if (res.status == 401) {
        await logoutRevokedSpaceSession();
        window.location.replace("/");
        return false;
    }
    ensureOk(res);
    const bootstrap = SpaceBrowserSessionBootstrapResponse.parse(
        await res.json(),
    );
    let spaceRootKey: string;
    try {
        spaceRootKey = await decryptBox(
            {
                encryptedData: persisted.encryptedSpaceRootKey,
                nonce: persisted.nonce,
            },
            bootstrap.sessionWrapKey,
        );
    } catch (error) {
        log.error(`Failed to decrypt Space browser session: ${String(error)}`);
        clearSpaceBrowserSession();
        return false;
    }
    replaceSavedLocalUser({ id: persisted.userId, email: persisted.email });
    saveSpaceRootKeyInSpaceSession(spaceRootKey);
    await removeAuthToken();
    return true;
};

export const getOrCreateSpaceRootKey = async (
    masterKey: string,
    authToken: string,
) => {
    const candidate = await generateKey();
    const { encryptedData: encryptedKey, nonce: header } = await encryptBox(
        candidate,
        masterKey,
    );
    const res = await fetch(await apiURL("/user-entity/key/ensure"), {
        method: "POST",
        headers: {
            ...spaceBootstrapAuthHeaders(authToken),
            "Content-Type": "application/json",
        },
        body: JSON.stringify({ type: "space", encryptedKey, header }),
    });
    ensureOk(res);
    const ensured = SpaceEntityKeyResponse.parse(await res.json());
    return decryptBox(
        { encryptedData: ensured.encryptedKey, nonce: ensured.header },
        masterKey,
    );
};

export const revokeSpaceBrowserSessions = async () => {
    const sessionToken = savedSpaceSessionToken();
    if (!sessionToken) return;

    const res = await fetch(await apiURL("/account/space/sessions/current"), {
        method: "DELETE",
        headers: {
            ...publicRequestHeaders(),
            [spaceSessionTokenHeader]: sessionToken,
        },
    });
    if (res.status != 401) ensureOk(res);
};
