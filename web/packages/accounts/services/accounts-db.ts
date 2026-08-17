// All of the state in this file is kept in the browser's localStorage, which
// is not accessible to web workers, so these functions only work on the main
// thread.

import { savedAuthToken } from "ente-base/token";
import { nullToUndefined } from "ente-utils/transform";
import { z } from "zod";
import {
    RemoteSRPAttributes,
    SRPSetupAttributes,
    type SRPAttributes,
} from "./srp";
import {
    RemoteKeyAttributes,
    type KeyAttributes,
    type LocalUser,
} from "./user";

export interface PartialLocalUser {
    id?: number;
    email?: string;
    token?: string;
    encryptedToken?: string;
    isTwoFactorEnabled?: boolean;
    twoFactorSessionID?: string;
    passkeySessionID?: string;
}

const PartialLocalUser = z.object({
    id: z.number().nullish().transform(nullToUndefined),
    email: z.string().nullish().transform(nullToUndefined),
    token: z.string().nullish().transform(nullToUndefined),
    encryptedToken: z.string().nullish().transform(nullToUndefined),
    isTwoFactorEnabled: z.boolean().nullish().transform(nullToUndefined),
    twoFactorSessionID: z.string().nullish().transform(nullToUndefined),
    passkeySessionID: z.string().nullish().transform(nullToUndefined),
});

const LocalUser = z.object({
    id: z.number(),
    email: z.string(),
    token: z.string(),
    isTwoFactorEnabled: z.boolean().nullish().transform(nullToUndefined),
});

export const savedPartialLocalUser = (): PartialLocalUser | undefined => {
    const jsonString = localStorage.getItem("user");
    if (!jsonString) return undefined;
    return PartialLocalUser.parse(JSON.parse(jsonString));
};

export const replaceSavedLocalUser = (partialLocalUser: PartialLocalUser) =>
    localStorage.setItem("user", JSON.stringify(partialLocalUser));

export const updateSavedLocalUser = (updates: Partial<PartialLocalUser>) =>
    replaceSavedLocalUser({ ...savedPartialLocalUser(), ...updates });

export const savedLocalUser = (): LocalUser | undefined => {
    const jsonString = localStorage.getItem("user");
    if (!jsonString) return undefined;
    // During login the saved user object can be partial, so do a non-throwing
    // parse.
    const { success, data } = LocalUser.safeParse(JSON.parse(jsonString));
    return success ? data : undefined;
};

// The synchronous local user accessors intentionally do not run this async
// consistency check since they are often called during render. Call this
// explicitly when validating app startup state.
export const isSavedUserTokenMismatch = async () => {
    const savedUserToken = savedPartialLocalUser()?.token;
    const authToken = await savedAuthToken();
    return authToken ? savedUserToken !== authToken : !!savedUserToken;
};

export const isLocalStorageAndIndexedDBMismatch = async () =>
    savedPartialLocalUser()?.token && !(await savedAuthToken());

export const savedKeyAttributes = (): KeyAttributes | undefined => {
    const jsonString = localStorage.getItem("keyAttributes");
    if (!jsonString) return undefined;
    return RemoteKeyAttributes.parse(JSON.parse(jsonString));
};

export const saveKeyAttributes = (keyAttributes: KeyAttributes) =>
    localStorage.setItem("keyAttributes", JSON.stringify(keyAttributes));

// Unlike the "keyAttributes" entry, which can get overwritten by locally
// generated interactive key attributes, the "originalKeyAttributes" entry
// retains the key attributes that were freshly generated at signup or fetched
// from remote.
export const savedOriginalKeyAttributes = (): KeyAttributes | undefined => {
    const jsonString = localStorage.getItem("originalKeyAttributes");
    if (!jsonString) return undefined;
    return RemoteKeyAttributes.parse(JSON.parse(jsonString));
};

export const saveOriginalKeyAttributes = (keyAttributes: KeyAttributes) =>
    localStorage.setItem(
        "originalKeyAttributes",
        JSON.stringify(keyAttributes),
    );

export const savedSRPAttributes = (): SRPAttributes | undefined => {
    const jsonString = localStorage.getItem("srpAttributes");
    if (!jsonString) return undefined;
    return RemoteSRPAttributes.parse(JSON.parse(jsonString));
};

export const saveSRPAttributes = (srpAttributes: SRPAttributes) =>
    localStorage.setItem("srpAttributes", JSON.stringify(srpAttributes));

export const stashSRPSetupAttributes = (
    srpSetupAttributes: SRPSetupAttributes,
) =>
    localStorage.setItem(
        "srpSetupAttributes",
        JSON.stringify(srpSetupAttributes),
    );

export const unstashAfterUseSRPSetupAttributes = async (
    cb: (srpSetupAttributes: SRPSetupAttributes) => Promise<void>,
) => {
    const jsonString = localStorage.getItem("srpSetupAttributes");
    if (!jsonString) return;
    const srpSetupAttributes = SRPSetupAttributes.parse(JSON.parse(jsonString));
    await cb(srpSetupAttributes);
    localStorage.removeItem("srpSetupAttributes");
};

// Legacy format in which the "isFirstLogin" and "justSignedUp" flags were
// saved. Readers fall back to it since it can still be present in users' local
// storage. (tag: Migration)
const LocalLegacyBooleanFlag = z.object({
    status: z.boolean().nullish().transform(nullToUndefined),
});

export const savedIsFirstLogin = () => {
    const jsonString = localStorage.getItem("isFirstLogin");
    if (!jsonString) return false;
    try {
        return z.boolean().parse(JSON.parse(jsonString));
    } catch {
        return (
            LocalLegacyBooleanFlag.parse(JSON.parse(jsonString)).status ?? false
        );
    }
};

export const saveIsFirstLogin = () => {
    localStorage.setItem("isFirstLogin", JSON.stringify(true));
};

export const getAndClearIsFirstLogin = () => {
    const result = savedIsFirstLogin();
    localStorage.removeItem("isFirstLogin");
    return result;
};

export const savedJustSignedUp = () => {
    const jsonString = localStorage.getItem("justSignedUp");
    if (!jsonString) return false;
    try {
        return z.boolean().parse(JSON.parse(jsonString));
    } catch {
        return (
            LocalLegacyBooleanFlag.parse(JSON.parse(jsonString)).status ?? false
        );
    }
};

export const saveJustSignedUp = () => {
    localStorage.setItem("justSignedUp", JSON.stringify(true));
};

export const getAndClearJustSignedUp = () => {
    const result = savedJustSignedUp();
    localStorage.removeItem("justSignedUp");
    return result;
};

export const stashReferralSource = (referralSource: string) => {
    localStorage.setItem("referralSource", referralSource);
};

export const unstashReferralSource = () => {
    const referralSource = localStorage.getItem("referralSource");
    if (!referralSource) return undefined;
    localStorage.removeItem("referralSource");
    return referralSource;
};
