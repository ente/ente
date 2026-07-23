/**
 * @file [Note: Accounts DB]
 *
 * The accounts package stores various state both during the login / signup
 * flow, and post login to identify the logged in user.
 *
 * This state is stored in local storage.
 *
 * Most of this state is meant to be transitory - various bits and bobs that we
 * accumulate and want to persist as the user goes through the login or signup
 * flow. One the user is successfully logged in and the first pull has
 * completed, then only a few of these are expected to remain:
 *
 * - "user"
 * - "keyAttributes"
 * - "originalKeyAttributes"
 * - "srpAttributes"
 */

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

/**
 * The local storage data about the user before login or signup is complete.
 *
 * [Note: Partial local user]
 *
 * During login or signup, the user object exists in various partial states in
 * local storage.
 *
 * - Initially, there is no user object in local storage.
 *
 * - When the user enters their email, the email property of the stored object
 *   is set, but nothing else.
 *
 * - After they verify their password, we have two cases: if second factor
 *   verification is not set, and when it is set.
 *
 * - If second factor verification is not set, then after verifying their
 *   password their {@link id} and {@link encryptedToken} will get filled in,
 *   and {@link isTwoFactorEnabled} will be set to false.
 *
 * - If they have second factor verification set, then after verifying their
 *   password {@link isTwoFactorEnabled} and {@link twoFactorSessionID} will
 *   also get filled in. Once they verify their TOTP based second factor, their
 *   {@link id} and {@link encryptedToken} will also get filled in.
 *
 * - If they have a passkey set as a second factor set, then after verifying
 *   their password the {@link passkeySessionID} will be set.
 *
 * - As the login or signup sequence completes, a {@link token} obtained from
 *   the {@link encryptedToken} will be written out, and the
 *   {@link encryptedToken} cleared since it is not needed anymore.
 *
 * So while the underlying storage is the same, we offer two APIs for code to
 * obtain the user:
 *
 * - Before login is complete, or when it is unknown if login is complete or
 *   not, then {@link savedPartialLocalUser} can be used to obtain a
 *   {@link PartialLocalUser} with all of its properties set to be optional (and
 *   some additional properties not available in the regular user object).
 *
 * - When we know that the login has completed, we can use either
 *   {@link savedLocalUser} (which returns `undefined` if our assumption is
 *   false) or {@link ensureSavedLocalUser} (which throws if our assumption is
 *   false) to obtain an object with all the properties expected to be present
 *   for a locally persisted user set to be required.
 */
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

/**
 * Zod schema for the {@link LocalUser} TypeScript type.
 *
 * The type itself is in `user.ts`.
 */
const LocalUser = z.object({
    id: z.number(),
    email: z.string(),
    token: z.string(),
    isTwoFactorEnabled: z.boolean().nullish().transform(nullToUndefined),
});

/**
 * Return the local storage value of the user's data.
 *
 * This function is meant to be called during the login or signup sequence.
 * After the user is logged in, use {@link savedLocalUser} or
 * {@link ensureLocalUser} instead.
 *
 * Use {@link replaceSavedLocalUser} to updated the saved value.
 */
export const savedPartialLocalUser = (): PartialLocalUser | undefined => {
    const jsonString = localStorage.getItem("user");
    if (!jsonString) return undefined;
    return PartialLocalUser.parse(JSON.parse(jsonString));
};

/**
 * Save the users data as we accrue it during the signup or login flow.
 *
 * See: [Note: Partial local user].
 *
 * This method replaces the existing data. Use {@link updateSavedLocalUser} to
 * update selected fields while keeping the other fields as it is.
 */
export const replaceSavedLocalUser = (partialLocalUser: PartialLocalUser) =>
    localStorage.setItem("user", JSON.stringify(partialLocalUser));

/**
 * Partially update the saved user data.
 *
 * This is a delta variant of {@link replaceSavedLocalUser}, which replaces the
 * entire saved object, while this function spreads the provided {@link updates}
 * onto the currently saved value.
 *
 * @param updates A subset of {@link PartialLocalUser} fields that we'd like to
 * update. The other fields, if present in local storage, remain unchanged.
 */
export const updateSavedLocalUser = (updates: Partial<PartialLocalUser>) =>
    replaceSavedLocalUser({ ...savedPartialLocalUser(), ...updates });

/**
 * Return data about the logged-in user, if someone is indeed logged in.
 * Otherwise return `undefined`.
 *
 * The user's data is stored in the browser's localStorage. Thus, this function
 * only works from the main thread, not from web workers since local storage is
 * not accessible to web workers.
 *
 * There is no setter corresponding to this function since this is only a view
 * on data saved using {@link replaceSavedLocalUser} or
 * {@link updateSavedLocalUser}.
 *
 * See: [Note: Partial local user] for more about the whole shebang.
 */
export const savedLocalUser = (): LocalUser | undefined => {
    const jsonString = localStorage.getItem("user");
    if (!jsonString) return undefined;
    // We might have some data, but not all of it. So do a non-throwing parse.
    const { success, data } = LocalUser.safeParse(JSON.parse(jsonString));
    return success ? data : undefined;
};

/**
 * Return true if the saved user token in local storage and the persisted auth
 * token are out of sync.
 *
 * Call this explicitly when validating app startup state. The synchronous local
 * user accessors intentionally avoid triggering async mismatch checks because
 * they are often used during render.
 */
export const isSavedUserTokenMismatch = async () => {
    const savedUserToken = savedPartialLocalUser()?.token;
    const authToken = await savedAuthToken();
    return authToken ? savedUserToken !== authToken : !!savedUserToken;
};

/**
 * Return true if the user's data is in local storage but not in IndexedDB.
 *
 * This acts a sanity check on IndexedDB by ensuring that if the user has a
 * token in local storage, then it should also be present in IndexedDB.
 */
export const isLocalStorageAndIndexedDBMismatch = async () =>
    savedPartialLocalUser()?.token && !(await savedAuthToken());

/**
 * Return the user's {@link KeyAttributes} if they are present in local storage.
 *
 * The key attributes are stored in the browser's localStorage. Thus, this
 * function only works from the main thread, not from web workers (local storage
 * is not accessible to web workers).
 *
 * See also: [Note: Original vs interactive key attributes]
 */
export const savedKeyAttributes = (): KeyAttributes | undefined => {
    const jsonString = localStorage.getItem("keyAttributes");
    if (!jsonString) return undefined;
    return RemoteKeyAttributes.parse(JSON.parse(jsonString));
};

/**
 * Save the user's {@link KeyAttributes} in local storage.
 *
 * Use {@link savedKeyAttributes} to retrieve them.
 */
export const saveKeyAttributes = (keyAttributes: KeyAttributes) =>
    localStorage.setItem("keyAttributes", JSON.stringify(keyAttributes));

/**
 * Return the user's original {@link KeyAttributes} if they are present in local
 * storage.
 *
 * [Note: Original vs interactive key attributes]
 *
 * This function is similar to {@link savedKeyAttributes} except it returns the
 * user's "original" key attributes. These are the key attributes that were
 * either freshly generated (if the user signed up on this client) or were
 * fetched from remote (otherwise).
 *
 * > NOTE: Currently the code does not guarantee that savedOriginalKeyAttributes
 * > will always be set when savedKeyAttributes is set.
 *
 * In contrast, the regular key attributes get overwritten by the local only
 * interactive key attributes for the user's convenience. See the documentation
 * of {@link generateAndSaveInteractiveKeyAttributes} for more details.
 */
export const savedOriginalKeyAttributes = (): KeyAttributes | undefined => {
    const jsonString = localStorage.getItem("originalKeyAttributes");
    if (!jsonString) return undefined;
    return RemoteKeyAttributes.parse(JSON.parse(jsonString));
};

/**
 * Save the user's {@link KeyAttributes} in local storage.
 *
 * Once saved, these values are not replaced (in contrast with the regular key
 * attributes which can get overwritten with interactive ones).
 *
 * Use {@link savedOriginalKeyAttributes} to retrieve them.
 */
export const saveOriginalKeyAttributes = (keyAttributes: KeyAttributes) =>
    localStorage.setItem(
        "originalKeyAttributes",
        JSON.stringify(keyAttributes),
    );

/**
 * Return the user's {@link SRPAttributes} if they are present in local storage.
 *
 * Like key attributes, SRP attributes are also stored in the browser's local
 * storage so will not be accessible to web workers.
 */
export const savedSRPAttributes = (): SRPAttributes | undefined => {
    const jsonString = localStorage.getItem("srpAttributes");
    if (!jsonString) return undefined;
    return RemoteSRPAttributes.parse(JSON.parse(jsonString));
};

/**
 * Save the user's {@link SRPAttributes} in local storage.
 *
 * Use {@link savedSRPAttributes} to retrieve them.
 */
export const saveSRPAttributes = (srpAttributes: SRPAttributes) =>
    localStorage.setItem("srpAttributes", JSON.stringify(srpAttributes));

/**
 * Save {@link SRPSetupAttributes} in local storage for later use via
 * {@link unstashAfterUseSRPSetupAttributes}.
 *
 * See: [Note: SRP setup attributes]
 */
export const stashSRPSetupAttributes = (
    srpSetupAttributes: SRPSetupAttributes,
) =>
    localStorage.setItem(
        "srpSetupAttributes",
        JSON.stringify(srpSetupAttributes),
    );

/**
 * Retrieve the {@link SRPSetupAttributes}, if any, that were stashed by a
 * previous call to {@link stashSRPSetupAttributes}.
 *
 * - If they are found, then invoke the provided callback ({@link cb}) with the
 *   value. If the promise returned by the callback fulfills, then remove the
 *   stashed value from local storage.
 *
 * - If they are not found, then the callback is not invoked.
 */
export const unstashAfterUseSRPSetupAttributes = async (
    cb: (srpSetupAttributes: SRPSetupAttributes) => Promise<void>,
) => {
    const jsonString = localStorage.getItem("srpSetupAttributes");
    if (!jsonString) return;
    const srpSetupAttributes = SRPSetupAttributes.parse(JSON.parse(jsonString));
    await cb(srpSetupAttributes);
    localStorage.removeItem("srpSetupAttributes");
};

/**
 * Zod schema for the legacy format in which the {@link savedIsFirstLogin} and
 * {@link savedJustSignedUp} flags were saved in local storage.
 *
 * Starting 1.7.15-beta (July 2025), we started saving the booleans directly,
 * but when reading we fallback to the old format if needed. This fallback can
 * be removed, and soonish, since these are transient flags that are saved
 * during the login / signup sequence and wouldn't be expected to remain in the
 * user's local storage for long anyway. (tag: Migration).
 */
const LocalLegacyBooleanFlag = z.object({
    status: z.boolean().nullish().transform(nullToUndefined),
});

/**
 * Return `true` if it is the user's first login on this client.
 *
 * The {@link savedIsFirstLogin} flag is saved in local storage (using
 * {@link saveIsFirstLogin}) if we determine during the login flow that it a
 * fresh login on this client. If so, we
 *
 * - Generate interactive key attributes for them, and
 *
 * - Display them a special indicator post login to notify them that the first
 *   load might take extra time. At this point, we also clear the flag (the read
 *   and clear is done by the same {@link getAndClearIsFirstLogin} function).
 */
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

/**
 * Save a flag in local storage to indicate that this is the user's first login
 * on this client.
 *
 * This is the setter corresponding to {@link savedIsFirstLogin}.
 */
export const saveIsFirstLogin = () => {
    localStorage.setItem("isFirstLogin", JSON.stringify({ status: true }));
};

/**
 * Get the saved value of the local storage flag that indicates that this is the
 * user' first login on this client. Also remove the flag after reading.
 *
 * The flag can be set by using {@link saveIsFirstLogin}, and can be read
 * without clearing it by using {@link savedIsFirstLogin}.
 */
export const getAndClearIsFirstLogin = () => {
    const result = savedIsFirstLogin();
    localStorage.removeItem("isFirstLogin");
    return result;
};

/**
 * Return `true` if the user created a new account on this client during the
 * current (in-progress) or just completed login / signup sequence.
 */
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

/**
 * Save a flag in local storage to indicate that the user signed up for a
 * new Ente account during the current login / signup sequence.
 *
 * This is the setter corresponding to {@link savedJustSignedUp}.
 */
export const saveJustSignedUp = () => {
    localStorage.setItem("justSignedUp", JSON.stringify({ status: true }));
};

/**
 * Get the saved value of the local storage flag that indicates that the user just
 * signed up. Also remove the flag from local storage after reading.
 *
 * The flag can be set by using {@link saveJustSignedUp}, and can be read
 * without clearing it by using {@link savedJustSignedUp}.
 */
export const getAndClearJustSignedUp = () => {
    const result = savedJustSignedUp();
    localStorage.removeItem("justSignedUp");
    return result;
};

/**
 * Save the referral source entered by the user on the signup screen in local
 * storage.
 *
 * The saved value can be retrieved post email verification using
 * {@link unstashReferralSource}.
 */
export const stashReferralSource = (referralSource: string) => {
    localStorage.setItem("referralSource", referralSource);
};

/**
 * Retrieve the previously saved referral source (using
 * {@link stashReferralSource}), returning the saved value and also clearing it
 * from local storage.
 */
export const unstashReferralSource = () => {
    const referralSource = localStorage.getItem("referralSource");
    if (!referralSource) return undefined;
    localStorage.removeItem("referralSource");
    return referralSource;
};
