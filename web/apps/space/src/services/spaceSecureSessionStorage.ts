import { z } from "zod";

const windowNamePrefix = "ente-space-secure-session:";
const sessionStorageKey = "enteSpaceSecureSession";
const legacyAccountsSessionKeys = ["encryptionKey", "keyEncryptionKey"];

const SecureSessionState = z.object({
    authMasterKey: z.string().optional(),
    keyEncryptionKey: z.string().optional(),
    spaceRootKey: z.string().optional(),
});

type SecureSessionState = z.infer<typeof SecureSessionState>;

const SecureSessionShare = z.object({
    length: z.number().int().nonnegative(),
    share: z.string(),
});

type SecureSessionShare = z.infer<typeof SecureSessionShare>;

const textEncoder = new TextEncoder();
const textDecoder = new TextDecoder();

const bytesToBase64 = (bytes: Uint8Array) => {
    let binary = "";
    for (const byte of bytes) binary += String.fromCharCode(byte);
    return btoa(binary);
};

const base64ToBytes = (value: string) => {
    const binary = atob(value);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) {
        bytes[i] = binary.charCodeAt(i);
    }
    return bytes;
};

const hasSecret = (state: SecureSessionState) =>
    state.authMasterKey !== undefined ||
    state.keyEncryptionKey !== undefined ||
    state.spaceRootKey !== undefined;

const clearLegacyAccountsSessionKeys = () => {
    for (const key of legacyAccountsSessionKeys) sessionStorage.removeItem(key);
};

const readWindowShare = () => {
    if (!window.name.startsWith(windowNamePrefix)) return undefined;
    try {
        return SecureSessionShare.parse(
            JSON.parse(window.name.slice(windowNamePrefix.length)),
        );
    } catch {
        window.name = "";
        return undefined;
    }
};

const readSessionShare = () => {
    const value = sessionStorage.getItem(sessionStorageKey);
    if (!value) return undefined;
    try {
        return SecureSessionShare.parse(JSON.parse(value));
    } catch {
        sessionStorage.removeItem(sessionStorageKey);
        return undefined;
    }
};

const splitSecret = (
    secret: string,
): [SecureSessionShare, SecureSessionShare] => {
    const secretBytes = textEncoder.encode(secret);
    const shareA = crypto.getRandomValues(new Uint8Array(secretBytes.length));
    const shareB = new Uint8Array(shareA);
    for (let i = 0; i < secretBytes.length; i++) {
        shareB[i] = shareB[i]! ^ secretBytes[i]!;
    }
    return [
        { length: secretBytes.length, share: bytesToBase64(shareA) },
        { length: secretBytes.length, share: bytesToBase64(shareB) },
    ];
};

const mergeSecret = (
    windowShare: SecureSessionShare,
    sessionShare: SecureSessionShare,
) => {
    if (windowShare.length != sessionShare.length) return undefined;
    const shareA = base64ToBytes(windowShare.share);
    const shareB = base64ToBytes(sessionShare.share);
    if (shareA.length != shareB.length || shareA.length != windowShare.length) {
        return undefined;
    }
    const secretBytes = new Uint8Array(windowShare.length);
    for (let i = 0; i < secretBytes.length; i++) {
        secretBytes[i] = shareA[i]! ^ shareB[i]!;
    }
    return textDecoder.decode(secretBytes);
};

const secureSessionState = (): SecureSessionState => {
    const windowShare = readWindowShare();
    const sessionShare = readSessionShare();
    if (!windowShare || !sessionShare) return {};
    const secret = mergeSecret(windowShare, sessionShare);
    if (!secret) return {};
    try {
        return SecureSessionState.parse(JSON.parse(secret));
    } catch {
        clearSpaceSecureSessionStorage();
        return {};
    }
};

const saveSecureSessionState = (state: SecureSessionState) => {
    clearLegacyAccountsSessionKeys();
    if (!hasSecret(state)) {
        clearSpaceSecureSessionStorage();
        return;
    }
    const [windowShare, sessionShare] = splitSecret(JSON.stringify(state));
    window.name = `${windowNamePrefix}${JSON.stringify(windowShare)}`;
    sessionStorage.setItem(sessionStorageKey, JSON.stringify(sessionShare));
};

export const clearSpaceSecureSessionStorage = () => {
    if (window.name.startsWith(windowNamePrefix)) window.name = "";
    sessionStorage.removeItem(sessionStorageKey);
    clearLegacyAccountsSessionKeys();
};

export const authMasterKeyFromSpaceSession = () =>
    secureSessionState().authMasterKey;

export const saveAuthMasterKeyInSpaceSession = (authMasterKey: string) => {
    saveSecureSessionState({ ...secureSessionState(), authMasterKey });
};

export const clearAuthMasterKeyFromSpaceSession = () => {
    saveSecureSessionState({
        ...secureSessionState(),
        authMasterKey: undefined,
    });
};

export const spaceRootKeyFromSpaceSession = () =>
    secureSessionState().spaceRootKey;

export const saveSpaceRootKeyInSpaceSession = (spaceRootKey: string) => {
    saveSecureSessionState({ ...secureSessionState(), spaceRootKey });
};

export const stashSpaceKeyEncryptionKeyInSessionStore = (kek: string) => {
    saveSecureSessionState({ ...secureSessionState(), keyEncryptionKey: kek });
};

export const unstashSpaceKeyEncryptionKeyFromSession = () => {
    const state = secureSessionState();
    const kek = state.keyEncryptionKey;
    if (kek === undefined) return undefined;
    saveSecureSessionState({ ...state, keyEncryptionKey: undefined });
    return kek;
};
