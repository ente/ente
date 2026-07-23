import { savedKeyAttributes } from "ente-accounts-rs/services/accounts-db";
import { getUserRecoveryKey } from "ente-accounts-rs/services/recovery-key";
import { masterKeyFromSession } from "ente-accounts-rs/services/session-storage";
import { ensureLocalUser } from "ente-accounts-rs/services/user";
import { clientPackageName, desktopAppVersion, isDesktop } from "ente-base/app";
import { ensureArrayBufferBacked } from "ente-base/bytes";
import { retryAsyncOperation } from "ente-base/http";
import log from "ente-base/log";
import { apiOrigin } from "ente-base/origins";
import { savedAuthToken } from "ente-base/token";
import type { ContactsCtxHandle } from "ente-wasm";
import { loadEnteWasm } from "ente-wasm/load";
import { useCallback, useEffect, useMemo, useSyncExternalStore } from "react";
import {
    saveContactDisplayRecords,
    saveContactsSinceTime,
    saveWrappedRootContactKey,
    savedContactDisplayRecords,
    savedContactsSinceTime,
    savedWrappedRootContactKey,
} from "./db";
import {
    knownEmailOrUndefined,
    normalizeEmail,
    resolveContactDisplayFromSnapshot,
} from "./resolver";
import type {
    ContactDisplayRecord,
    ContactLookup,
    ContactsDisplaySnapshot,
    LegacyContactState,
    LegacyInfo,
    LegacyRecoveryBundle,
    LegacyRecoveryStatus,
    ResolvedContactAvatar,
    ResolvedContactDisplay,
    WrappedRootContactKey,
} from "./types";
export type {
    ContactDisplayRecord,
    ContactLookup,
    ContactsDisplaySnapshot,
    LegacyContactRecord,
    LegacyContactState,
    LegacyInfo,
    LegacyRecoveryBundle,
    LegacyRecoverySession,
    LegacyRecoveryStatus,
    LegacyUser,
    ResolvedContactAvatar,
    ResolvedContactDisplay,
    WrappedRootContactKey,
} from "./types";

const CONTACT_DIFF_LIMIT = 500;
const AVATAR_FAILURE_TTL_MS = 60_000;
const CONTACTS_CACHE_SCHEMA_VERSION = 2;

interface RemoteContactRecord {
    id: string;
    contactUserId: number | bigint;
    email?: string | null;
    name?: string | null;
    profilePictureAttachmentID?: string | null;
    profilePictureAttachmentId?: string | null;
    isDeleted: boolean;
    updatedAt: number | bigint;
}

interface RemoteLegacyUser {
    id: number | bigint;
    email: string;
}

interface RemoteLegacyContactRecord {
    user: RemoteLegacyUser;
    emergencyContact: RemoteLegacyUser;
    state: LegacyContactState;
    recoveryNoticeInDays: number | bigint;
}

interface RemoteLegacyRecoverySession {
    id: string;
    user: RemoteLegacyUser;
    emergencyContact: RemoteLegacyUser;
    status: LegacyRecoveryStatus;
    waitTill: number | bigint;
    createdAt: number | bigint;
}

interface RemoteLegacyInfo {
    contacts: RemoteLegacyContactRecord[];
    recoverSessions: RemoteLegacyRecoverySession[];
    othersEmergencyContact: RemoteLegacyContactRecord[];
    othersRecoverySession: RemoteLegacyRecoverySession[];
}

interface ContactsReadyInput {
    userID: number;
    masterKeyB64: string;
}

type ContactsSessionInput = ContactsReadyInput & {
    sessionKey: string;
    baseURL: string;
    authToken: string;
    generation: number;
};

type RootKeySource = "cache" | "unresolved";

interface OpenedContactsCtx {
    ctx: ContactsCtxHandle;
    wrappedRootContactKey?: WrappedRootContactKey;
    rootKeySource: RootKeySource;
}

interface ContactsState {
    snapshot: ContactsDisplaySnapshot;
    listeners: Set<() => void>;
    currentSessionKey: string | undefined;
    sessionGeneration: number;
    currentAuthToken: string | undefined;
    ctx: ContactsCtxHandle | undefined;
    readyPromise: Promise<void> | undefined;
    contactsByID: Map<string, ContactDisplayRecord>;
    contactIDByUserID: Map<number, string>;
    contactIDByEmail: Map<string, string>;
    avatarURLByContactID: Map<string, string>;
    avatarLoadsByContactID: Map<string, Promise<void>>;
    avatarFailureUntilByContactID: Map<string, number>;
    avatarListenersByContactID: Map<string, Set<() => void>>;
}

const emptySnapshot = (): ContactsDisplaySnapshot => ({
    isHydrated: false,
    recordsByUserID: new Map(),
    recordsByEmail: new Map(),
    avatarURLsByContactID: new Map(),
});

const state: ContactsState = {
    snapshot: emptySnapshot(),
    listeners: new Set(),
    currentSessionKey: undefined,
    sessionGeneration: 0,
    currentAuthToken: undefined,
    ctx: undefined,
    readyPromise: undefined,
    contactsByID: new Map(),
    contactIDByUserID: new Map(),
    contactIDByEmail: new Map(),
    avatarURLByContactID: new Map(),
    avatarLoadsByContactID: new Map(),
    avatarFailureUntilByContactID: new Map(),
    avatarListenersByContactID: new Map(),
};

const buildSessionKey = (baseURL: string, userID: number) =>
    `${encodeURIComponent(baseURL)}:${userID}:v${CONTACTS_CACHE_SCHEMA_VERSION}`;

const emitAvatarURL = (contactID: string) => {
    const listeners = state.avatarListenersByContactID.get(contactID);
    if (!listeners) {
        return;
    }
    for (const listener of listeners) {
        listener();
    }
};

const cleanupAvatarURL = (contactID: string, shouldEmit = false) => {
    const current = state.avatarURLByContactID.get(contactID);
    if (current) {
        URL.revokeObjectURL(current);
        state.avatarURLByContactID.delete(contactID);
        if (shouldEmit) {
            emitAvatarURL(contactID);
        }
    }
    state.avatarLoadsByContactID.delete(contactID);
    state.avatarFailureUntilByContactID.delete(contactID);
};

const isCurrentSession = (sessionKey: string, generation: number) =>
    state.currentSessionKey === sessionKey &&
    state.sessionGeneration === generation;

const clearInMemoryState = () => {
    for (const avatarURL of state.avatarURLByContactID.values()) {
        URL.revokeObjectURL(avatarURL);
    }
    state.ctx = undefined;
    state.currentAuthToken = undefined;
    state.readyPromise = undefined;
    state.contactsByID = new Map();
    state.contactIDByUserID = new Map();
    state.contactIDByEmail = new Map();
    state.avatarURLByContactID = new Map();
    state.avatarLoadsByContactID = new Map();
    state.avatarFailureUntilByContactID = new Map();
};

const emitSnapshot = (isHydrated = true) => {
    state.snapshot = {
        isHydrated,
        recordsByUserID: new Map(
            [...state.contactIDByUserID.entries()]
                .map(([userID, contactID]) => [
                    userID,
                    state.contactsByID.get(contactID),
                ])
                .filter(
                    (entry): entry is [number, ContactDisplayRecord] =>
                        entry[1] !== undefined,
                ),
        ),
        recordsByEmail: new Map(
            [...state.contactIDByEmail.entries()]
                .map(([email, contactID]) => [
                    email,
                    state.contactsByID.get(contactID),
                ])
                .filter(
                    (entry): entry is [string, ContactDisplayRecord] =>
                        entry[1] !== undefined,
                ),
        ),
        avatarURLsByContactID: new Map(state.avatarURLByContactID),
    };

    for (const listener of state.listeners) {
        listener();
    }
};

const removeContact = (contactID: string) => {
    const previous = state.contactsByID.get(contactID);
    if (!previous) return;

    state.contactsByID.delete(contactID);
    state.contactIDByUserID.delete(previous.contactUserId);
    const normalizedEmail = normalizeEmail(previous.resolvedEmail);
    if (normalizedEmail) {
        state.contactIDByEmail.delete(normalizedEmail);
    }
    cleanupAvatarURL(contactID, true);
};

const upsertContact = (record: ContactDisplayRecord) => {
    const previous = state.contactsByID.get(record.contactId);
    if (previous) {
        if (previous.contactUserId !== record.contactUserId) {
            state.contactIDByUserID.delete(previous.contactUserId);
        }
        const previousEmail = normalizeEmail(previous.resolvedEmail);
        const nextEmail = normalizeEmail(record.resolvedEmail);
        if (previousEmail && previousEmail !== nextEmail) {
            state.contactIDByEmail.delete(previousEmail);
        }
        if (
            previous.profilePictureAttachmentID !==
            record.profilePictureAttachmentID
        ) {
            cleanupAvatarURL(record.contactId, true);
        }
    }

    state.contactsByID.set(record.contactId, record);
    state.contactIDByUserID.set(record.contactUserId, record.contactId);

    const normalizedEmail = normalizeEmail(record.resolvedEmail);
    if (normalizedEmail) {
        state.contactIDByEmail.set(normalizedEmail, record.contactId);
    }
};

const contactDisplayRecordFromRemote = (
    record: RemoteContactRecord,
): ContactDisplayRecord => ({
    contactId: record.id,
    contactUserId: Number(record.contactUserId),
    resolvedEmail: knownEmailOrUndefined(record.email),
    displayName: knownEmailOrUndefined(record.name),
    profilePictureAttachmentID: knownEmailOrUndefined(
        record.profilePictureAttachmentID ?? record.profilePictureAttachmentId,
    ),
    updatedAt: Number(record.updatedAt),
});

export const resolveContactDisplay = (
    lookup: ContactLookup,
): ResolvedContactDisplay =>
    resolveContactDisplayFromSnapshot(state.snapshot, lookup);

export const resolveKnownEmail = (lookup: ContactLookup) =>
    resolveContactDisplay(lookup).actualEmail;

export const contactsDisplaySubscribe = (onChange: () => void) => {
    state.listeners.add(onChange);
    return () => {
        state.listeners.delete(onChange);
    };
};

const subscribeAvatarURL = (contactID: string, onChange: () => void) => {
    const listeners =
        state.avatarListenersByContactID.get(contactID) ??
        new Set<() => void>();
    listeners.add(onChange);
    state.avatarListenersByContactID.set(contactID, listeners);
    return () => {
        listeners.delete(onChange);
        if (listeners.size === 0) {
            state.avatarListenersByContactID.delete(contactID);
        }
    };
};

const avatarURLSnapshot = (contactID: string | undefined) =>
    contactID ? state.avatarURLByContactID.get(contactID) : undefined;

export const contactsDisplaySnapshot = () => state.snapshot;

const useContactsSnapshot = () =>
    useSyncExternalStore(
        contactsDisplaySubscribe,
        contactsDisplaySnapshot,
        contactsDisplaySnapshot,
    );

const loadLocalSessionState = async (sessionKey: string) => {
    state.sessionGeneration += 1;
    const generation = state.sessionGeneration;
    state.currentSessionKey = sessionKey;
    clearInMemoryState();
    emitSnapshot(false);

    const savedRecords = await savedContactDisplayRecords(sessionKey);
    if (!isCurrentSession(sessionKey, generation)) {
        return;
    }
    for (const record of savedRecords) {
        upsertContact(record);
    }

    emitSnapshot(true);
    return generation;
};

const ensureSessionLoaded = async (sessionKey: string) =>
    state.currentSessionKey === sessionKey
        ? state.sessionGeneration
        : loadLocalSessionState(sessionKey);

const ensureContactsCtxOpen = async ({
    sessionKey,
    baseURL,
    authToken,
    userID,
    masterKeyB64,
    generation,
}: ContactsSessionInput) => {
    if (!isCurrentSession(sessionKey, generation)) {
        return;
    }

    let ctx = state.ctx;

    if (!ctx) {
        const cachedWrappedRootContactKey =
            await savedWrappedRootContactKey(sessionKey);
        if (!isCurrentSession(sessionKey, generation)) {
            return;
        }
        const { contacts_open_ctx } = await loadEnteWasm();
        const openedCtx = (await contacts_open_ctx({
            baseUrl: baseURL,
            authToken,
            userId: userID,
            masterKeyB64,
            cachedWrappedRootContactKey,
            clientPackage: clientPackageName,
            clientVersion: isDesktop ? desktopAppVersion : undefined,
        })) as OpenedContactsCtx;
        if (!isCurrentSession(sessionKey, generation)) {
            return;
        }
        state.ctx = openedCtx.ctx;
        ctx = openedCtx.ctx;
        if (openedCtx.wrappedRootContactKey) {
            await saveWrappedRootContactKey(
                sessionKey,
                openedCtx.wrappedRootContactKey,
            );
            if (!isCurrentSession(sessionKey, generation)) {
                return;
            }
        }
    } else if (state.currentAuthToken !== authToken) {
        ctx.update_auth_token(authToken);
    }

    if (!isCurrentSession(sessionKey, generation)) {
        return;
    }

    state.currentAuthToken = authToken;
    return ctx;
};

const syncContacts = async ({
    sessionKey,
    baseURL,
    authToken,
    userID,
    masterKeyB64,
    generation,
}: ContactsSessionInput) => {
    const ctx = await ensureContactsCtxOpen({
        sessionKey,
        baseURL,
        authToken,
        userID,
        masterKeyB64,
        generation,
    });
    if (!ctx) {
        return;
    }

    let sinceTime = (await savedContactsSinceTime(sessionKey)) ?? 0;
    let didChange = false;

    while (true) {
        const diff = (await ctx.get_diff(
            BigInt(sinceTime),
            CONTACT_DIFF_LIMIT,
        )) as RemoteContactRecord[];
        if (!isCurrentSession(sessionKey, generation)) {
            return;
        }
        if (diff.length === 0) {
            break;
        }

        didChange = true;
        for (const record of diff) {
            if (record.isDeleted) {
                removeContact(record.id);
            } else {
                upsertContact(contactDisplayRecordFromRemote(record));
            }
            sinceTime = Math.max(sinceTime, Number(record.updatedAt));
        }
    }

    if (didChange) {
        if (!isCurrentSession(sessionKey, generation)) {
            return;
        }
        const wrappedRootContactKey =
            (await ctx.current_wrapped_root_contact_key()) as
                | WrappedRootContactKey
                | undefined;
        if (wrappedRootContactKey) {
            await saveWrappedRootContactKey(sessionKey, wrappedRootContactKey);
            if (!isCurrentSession(sessionKey, generation)) {
                return;
            }
        }
        await saveContactDisplayRecords(sessionKey, [
            ...state.contactsByID.values(),
        ]);
        await saveContactsSinceTime(sessionKey, sinceTime);
        emitSnapshot(true);
    }
};

export const ensureContactsReady = async ({
    userID,
    masterKeyB64,
}: ContactsReadyInput) => {
    const authToken = await savedAuthToken();
    if (!authToken) {
        state.sessionGeneration += 1;
        state.currentSessionKey = undefined;
        clearInMemoryState();
        emitSnapshot(false);
        return;
    }

    const baseURL = await apiOrigin();
    const sessionKey = buildSessionKey(baseURL, userID);

    const generation = await ensureSessionLoaded(sessionKey);
    if (generation === undefined) {
        return;
    }

    if (state.readyPromise) {
        return state.readyPromise;
    }

    const readyPromise = retryAsyncOperation(
        () =>
            syncContacts({
                sessionKey,
                baseURL,
                authToken,
                userID,
                masterKeyB64,
                generation,
            }),
        { retryProfile: "background" },
    ).finally(() => {
        if (state.readyPromise === readyPromise) {
            state.readyPromise = undefined;
        }
    });

    state.readyPromise = readyPromise;

    return readyPromise;
};

const ensureCurrentLegacyCtx = async () => {
    const masterKeyB64 = await masterKeyFromSession();
    if (!masterKeyB64) {
        throw new Error("Missing current master key");
    }
    const authToken = await savedAuthToken();
    if (!authToken) {
        throw new Error("Missing auth token");
    }
    const user = ensureLocalUser();
    const baseURL = await apiOrigin();
    const sessionKey = buildSessionKey(baseURL, user.id);
    const generation = await ensureSessionLoaded(sessionKey);
    if (generation === undefined) {
        throw new Error("Contacts context not available");
    }
    const ctx = await ensureContactsCtxOpen({
        sessionKey,
        baseURL,
        authToken,
        userID: user.id,
        masterKeyB64,
        generation,
    });
    if (!ctx) {
        throw new Error("Contacts context not available");
    }
    return ctx;
};

const ensureCurrentLegacyKeyAttributes = () => {
    const keyAttributes = savedKeyAttributes();
    if (!keyAttributes) {
        throw new Error("Missing current key attributes");
    }
    return keyAttributes as unknown as Record<string, unknown>;
};

const normalizeLegacyUser = (user: RemoteLegacyUser) => ({
    id: Number(user.id),
    email: user.email,
});

const normalizeLegacyContactRecord = (record: RemoteLegacyContactRecord) => ({
    user: normalizeLegacyUser(record.user),
    emergencyContact: normalizeLegacyUser(record.emergencyContact),
    state: record.state,
    recoveryNoticeInDays: Number(record.recoveryNoticeInDays),
});

const normalizeLegacyRecoverySession = (
    session: RemoteLegacyRecoverySession,
) => ({
    id: session.id,
    user: normalizeLegacyUser(session.user),
    emergencyContact: normalizeLegacyUser(session.emergencyContact),
    status: session.status,
    waitTill: Number(session.waitTill),
    createdAt: Number(session.createdAt),
});

const normalizeLegacyInfo = (info: RemoteLegacyInfo): LegacyInfo => ({
    contacts: info.contacts.map(normalizeLegacyContactRecord),
    recoverSessions: info.recoverSessions.map(normalizeLegacyRecoverySession),
    othersEmergencyContact: info.othersEmergencyContact.map(
        normalizeLegacyContactRecord,
    ),
    othersRecoverySession: info.othersRecoverySession.map(
        normalizeLegacyRecoverySession,
    ),
});

export const legacyGetInfo = async (): Promise<LegacyInfo> => {
    const ctx = await ensureCurrentLegacyCtx();
    return normalizeLegacyInfo(
        (await ctx.legacy_get_info()) as RemoteLegacyInfo,
    );
};

export const legacyPublicKey = async (email: string) => {
    const ctx = await ensureCurrentLegacyCtx();
    const publicKey = (await ctx.legacy_public_key(email)) as
        | string
        | null
        | undefined;
    return publicKey ?? undefined;
};

export const legacyVerificationID = async (email: string) => {
    const ctx = await ensureCurrentLegacyCtx();
    const publicKey = (await ctx.legacy_public_key(email)) as
        | string
        | null
        | undefined;
    return publicKey ? ctx.legacy_verification_id(publicKey) : undefined;
};

export const legacyAddContact = async (
    email: string,
    recoveryNoticeInDays?: number,
) => {
    await getUserRecoveryKey();
    const ctx = await ensureCurrentLegacyCtx();
    return ctx.legacy_add_contact(
        email,
        ensureCurrentLegacyKeyAttributes(),
        recoveryNoticeInDays,
    );
};

export const legacyUpdateContact = async (
    userID: number,
    emergencyContactID: number,
    state: LegacyContactState,
) => {
    const ctx = await ensureCurrentLegacyCtx();
    return ctx.legacy_update_contact(
        BigInt(userID),
        BigInt(emergencyContactID),
        state,
    );
};

export const legacyUpdateRecoveryNotice = async (
    emergencyContactID: number,
    recoveryNoticeInDays: number,
) => {
    const ctx = await ensureCurrentLegacyCtx();
    return ctx.legacy_update_recovery_notice(
        BigInt(emergencyContactID),
        recoveryNoticeInDays,
    );
};

export const legacyStartRecovery = async (
    userID: number,
    emergencyContactID: number,
) => {
    const ctx = await ensureCurrentLegacyCtx();
    return ctx.legacy_start_recovery(
        BigInt(userID),
        BigInt(emergencyContactID),
    );
};

export const legacyStopRecovery = async (
    recoveryID: string,
    userID: number,
    emergencyContactID: number,
) => {
    const ctx = await ensureCurrentLegacyCtx();
    return ctx.legacy_stop_recovery(
        recoveryID,
        BigInt(userID),
        BigInt(emergencyContactID),
    );
};

export const legacyRejectRecovery = async (
    recoveryID: string,
    userID: number,
    emergencyContactID: number,
) => {
    const ctx = await ensureCurrentLegacyCtx();
    return ctx.legacy_reject_recovery(
        recoveryID,
        BigInt(userID),
        BigInt(emergencyContactID),
    );
};

export const legacyApproveRecovery = async (
    recoveryID: string,
    userID: number,
    emergencyContactID: number,
) => {
    const ctx = await ensureCurrentLegacyCtx();
    return ctx.legacy_approve_recovery(
        recoveryID,
        BigInt(userID),
        BigInt(emergencyContactID),
    );
};

export const legacyRecoveryBundle = async (
    recoveryID: string,
): Promise<LegacyRecoveryBundle> => {
    const ctx = await ensureCurrentLegacyCtx();
    return (await ctx.legacy_recovery_bundle(
        recoveryID,
        ensureCurrentLegacyKeyAttributes(),
    )) as LegacyRecoveryBundle;
};

export const legacyChangePassword = async (
    recoveryID: string,
    newPassword: string,
) => {
    const ctx = await ensureCurrentLegacyCtx();
    return ctx.legacy_change_password(
        recoveryID,
        ensureCurrentLegacyKeyAttributes(),
        newPassword,
    );
};

const inferImageMimeType = (bytes: Uint8Array) => {
    if (
        bytes.length >= 12 &&
        bytes[0] === 0x52 &&
        bytes[1] === 0x49 &&
        bytes[2] === 0x46 &&
        bytes[3] === 0x46 &&
        bytes[8] === 0x57 &&
        bytes[9] === 0x45 &&
        bytes[10] === 0x42 &&
        bytes[11] === 0x50
    ) {
        return "image/webp";
    }
    if (
        bytes.length >= 8 &&
        bytes[0] === 0x89 &&
        bytes[1] === 0x50 &&
        bytes[2] === 0x4e &&
        bytes[3] === 0x47 &&
        bytes[4] === 0x0d &&
        bytes[5] === 0x0a &&
        bytes[6] === 0x1a &&
        bytes[7] === 0x0a
    ) {
        return "image/png";
    }
    if (
        bytes.length >= 3 &&
        bytes[0] === 0xff &&
        bytes[1] === 0xd8 &&
        bytes[2] === 0xff
    ) {
        return "image/jpeg";
    }
    if (
        bytes.length >= 6 &&
        bytes[0] === 0x47 &&
        bytes[1] === 0x49 &&
        bytes[2] === 0x46 &&
        bytes[3] === 0x38
    ) {
        return "image/gif";
    }
    return "application/octet-stream";
};

const ensureProfilePictureLoaded = async (contactID: string) => {
    const contact = state.contactsByID.get(contactID);
    const ctx = state.ctx;
    const sessionKey = state.currentSessionKey;
    const generation = state.sessionGeneration;
    if (!contact?.profilePictureAttachmentID || !ctx || !sessionKey) {
        return;
    }

    if (state.avatarURLByContactID.has(contactID)) {
        return;
    }

    const failureUntil = state.avatarFailureUntilByContactID.get(contactID);
    if (failureUntil && failureUntil > Date.now()) {
        return;
    }

    const existingLoad = state.avatarLoadsByContactID.get(contactID);
    if (existingLoad) {
        await existingLoad;
        return;
    }

    const load = ctx
        .get_profile_picture(contactID)
        .then((bytes: Uint8Array) => {
            if (
                !isCurrentSession(sessionKey, generation) ||
                state.ctx !== ctx
            ) {
                return;
            }
            const blob = new Blob([ensureArrayBufferBacked(bytes)], {
                type: inferImageMimeType(bytes),
            });
            const url = URL.createObjectURL(blob);
            cleanupAvatarURL(contactID);
            state.avatarURLByContactID.set(contactID, url);
            state.avatarFailureUntilByContactID.delete(contactID);
            emitAvatarURL(contactID);
        })
        .catch((error: unknown) => {
            if (
                !isCurrentSession(sessionKey, generation) ||
                state.ctx !== ctx
            ) {
                return;
            }
            state.avatarFailureUntilByContactID.set(
                contactID,
                Date.now() + AVATAR_FAILURE_TTL_MS,
            );
            log.info(
                `[contacts] Failed to load contact profile picture for ${contactID}`,
                error,
            );
        })
        .finally(() => {
            if (state.avatarLoadsByContactID.get(contactID) === load) {
                state.avatarLoadsByContactID.delete(contactID);
            }
        });

    state.avatarLoadsByContactID.set(contactID, load);
    await load;
};

export const __testing = {
    preloadResolvedContactAvatar: async (lookup: ContactLookup) => {
        const display = resolveContactDisplay(lookup);
        if (!display.contactId || !display.profilePictureAttachmentID) {
            return;
        }
        await ensureProfilePictureLoaded(display.contactId);
    },
};

export const useResolvedContactDisplay = (lookup: ContactLookup) => {
    const snapshot = useContactsSnapshot();
    return useMemo(
        () => resolveContactDisplayFromSnapshot(snapshot, lookup),
        [lookup.email, lookup.userID, snapshot],
    );
};

export const useResolvedContactAvatar = (
    lookup: ContactLookup,
): ResolvedContactAvatar => {
    const snapshot = useContactsSnapshot();
    const display = useMemo(
        () => resolveContactDisplayFromSnapshot(snapshot, lookup),
        [lookup.email, lookup.userID, snapshot],
    );
    const avatarURL = useSyncExternalStore(
        useCallback(
            (onChange: () => void) =>
                display.contactId
                    ? subscribeAvatarURL(display.contactId, onChange)
                    : () => undefined,
            [display.contactId],
        ),
        () => avatarURLSnapshot(display.contactId),
        () => avatarURLSnapshot(display.contactId),
    );

    useEffect(() => {
        if (!display.contactId || !display.profilePictureAttachmentID) {
            return;
        }
        void ensureProfilePictureLoaded(display.contactId);
    }, [display.contactId, display.profilePictureAttachmentID]);

    return { ...display, avatarURL };
};
