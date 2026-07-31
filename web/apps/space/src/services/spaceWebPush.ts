import { ensureOk, publicRequestHeaders } from "ente-base/http";
import { apiURL } from "ente-base/origins";
import type { PublicSpaceLinkSession } from "services/space";
import {
    savedSpaceSessionToken,
    spaceSessionTokenHeader,
} from "services/spacePersistentSession";
import { z } from "zod";

const SpaceWebPushVAPIDKeyResponse = z.object({ publicKey: z.string() });
const SpaceWebPushTargetResponse = z.object({ targetId: z.string() });

const pushDatabaseName = "ente-space-web-push";
const pushDatabaseVersion = 1;
const pushTargetStoreName = "targets";
const accountTargetKey = "account";
const vapidPublicKeyStorageKey = "ente-space-web-push-vapid-key";
const publicTargetSyncInterval = 24 * 60 * 60 * 1000;

interface StoredPushTarget {
    endpoint: string;
    key: string;
    kind: "account" | "public";
    lastSyncedAt?: number;
    route: string;
    targetId: string;
}

interface PreparedSpaceWebPush {
    publicKey: string;
    registration: ServiceWorkerRegistration;
}

interface SubscriptionDetails {
    auth: string;
    endpoint: string;
    p256dh: string;
}

export type SpaceWebPushState =
    | "denied"
    | "recovery"
    | "subscribed"
    | "unavailable"
    | "unsubscribed";

let pendingPreparation: Promise<PreparedSpaceWebPush | undefined> | undefined;
let pendingDatabase: Promise<IDBDatabase> | undefined;

export const isSpaceWebPushSupported = () =>
    typeof window != "undefined" &&
    "Notification" in window &&
    "serviceWorker" in navigator &&
    "PushManager" in window &&
    "indexedDB" in window;

interface BraveNavigator extends Navigator {
    brave?: { isBrave: () => Promise<boolean> };
}

export const isBravePushServiceError = async (error: unknown) => {
    if (
        !(error instanceof DOMException) ||
        error.name != "AbortError" ||
        !error.message.includes("push service error")
    ) {
        return false;
    }
    const brave = (navigator as BraveNavigator).brave;
    return brave ? brave.isBrave() : false;
};

export const registerSpaceServiceWorker = async () => {
    if (typeof navigator == "undefined" || !("serviceWorker" in navigator)) {
        return undefined;
    }
    await navigator.serviceWorker.register("/sw.js", { scope: "/" });
    return navigator.serviceWorker.ready;
};

const openPushDatabase = () =>
    (pendingDatabase ??= new Promise<IDBDatabase>((resolve, reject) => {
        const request = indexedDB.open(pushDatabaseName, pushDatabaseVersion);
        request.onupgradeneeded = () => {
            const database = request.result;
            if (!database.objectStoreNames.contains(pushTargetStoreName)) {
                const store = database.createObjectStore(pushTargetStoreName, {
                    keyPath: "key",
                });
                store.createIndex("targetId", "targetId");
            }
        };
        request.onerror = () =>
            reject(request.error ?? new Error("Failed to open push storage."));
        request.onsuccess = () => {
            request.result.onversionchange = () => request.result.close();
            resolve(request.result);
        };
    }).catch((error: unknown) => {
        pendingDatabase = undefined;
        throw error;
    }));

const targetRequest = async <T>(
    mode: IDBTransactionMode,
    action: (store: IDBObjectStore) => IDBRequest<T>,
) => {
    const database = await openPushDatabase();
    return new Promise<T>((resolve, reject) => {
        const transaction = database.transaction(pushTargetStoreName, mode);
        const request = action(transaction.objectStore(pushTargetStoreName));
        request.onerror = () =>
            reject(request.error ?? new Error("Push storage request failed."));
        request.onsuccess = () => resolve(request.result);
        transaction.onerror = () =>
            reject(
                transaction.error ??
                    new Error("Push storage transaction failed."),
            );
    });
};

const getTarget = (key: string) =>
    targetRequest<StoredPushTarget | undefined>(
        "readonly",
        (store) => store.get(key) as IDBRequest<StoredPushTarget | undefined>,
    );

const putTarget = (target: StoredPushTarget) =>
    targetRequest<IDBValidKey>("readwrite", (store) => store.put(target));

const deleteTarget = (key: string) =>
    targetRequest<undefined>("readwrite", (store) => store.delete(key));

const listTargets = () =>
    targetRequest<StoredPushTarget[]>(
        "readonly",
        (store) => store.getAll() as IDBRequest<StoredPushTarget[]>,
    );

const invalidateTargetDeliveries = async () => {
    const targets = await listTargets();
    await Promise.all(
        targets.map((target) =>
            putTarget({ ...target, endpoint: "", targetId: "" }),
        ),
    );
};

const publicTargetKey = (route: string) => `public:${route}`;

const cachedVAPIDPublicKey = () => {
    try {
        return localStorage.getItem(vapidPublicKeyStorageKey)?.trim();
    } catch {
        return undefined;
    }
};

const cacheVAPIDPublicKey = (publicKey: string) => {
    try {
        localStorage.setItem(vapidPublicKeyStorageKey, publicKey);
    } catch {
        // Push still works when persistent browser storage is unavailable.
    }
};

const spaceSessionHeaders = () => {
    const sessionToken = savedSpaceSessionToken();
    if (!sessionToken) throw new Error("Space session is missing.");
    return {
        ...publicRequestHeaders(),
        [spaceSessionTokenHeader]: sessionToken,
    };
};

const prepareSpaceWebPush = async () => {
    if (!isSpaceWebPushSupported()) return undefined;
    try {
        await openPushDatabase();
    } catch {
        return undefined;
    }
    const registration = await registerSpaceServiceWorker();
    if (!registration) return undefined;
    const cachedPublicKey = cachedVAPIDPublicKey();
    if (cachedPublicKey) {
        return { publicKey: cachedPublicKey, registration };
    }
    const response = await fetch(await apiURL("/space/push/vapid-key"), {
        headers: publicRequestHeaders(),
    });
    if (response.status == 503) return undefined;
    ensureOk(response);
    const { publicKey } = SpaceWebPushVAPIDKeyResponse.parse(
        await response.json(),
    );
    if (!publicKey.trim()) return undefined;
    cacheVAPIDPublicKey(publicKey);
    return { publicKey, registration };
};

const preparedSpaceWebPush = async () => {
    const preparation = (pendingPreparation ??= prepareSpaceWebPush());
    try {
        return await preparation;
    } finally {
        if (pendingPreparation == preparation) pendingPreparation = undefined;
    }
};

const subscriptionDetails = (
    subscription: PushSubscription,
): SubscriptionDetails => {
    const serialized = subscription.toJSON();
    const p256dh = serialized.keys?.p256dh;
    const auth = serialized.keys?.auth;
    if (!serialized.endpoint || !p256dh || !auth) {
        throw new Error("Web push subscription is incomplete.");
    }
    return { endpoint: serialized.endpoint, p256dh, auth };
};

const sameBytes = (left: ArrayBuffer, right: ArrayBuffer) => {
    if (left.byteLength != right.byteLength) return false;
    const leftBytes = new Uint8Array(left);
    const rightBytes = new Uint8Array(right);
    return leftBytes.every((value, index) => value == rightBytes[index]);
};

const currentSubscription = async (prepared: PreparedSpaceWebPush) => {
    const subscription =
        await prepared.registration.pushManager.getSubscription();
    // Firefox Android omits this key when restoring a valid subscription.
    const applicationServerKey =
        subscription?.options.applicationServerKey ?? null;
    if (
        !subscription ||
        !applicationServerKey ||
        sameBytes(applicationServerKey, base64URLKey(prepared.publicKey))
    ) {
        return subscription;
    }
    if (!(await subscription.unsubscribe())) {
        throw new Error("Failed to replace the old web push subscription.");
    }
    await invalidateTargetDeliveries();
    return null;
};

const ensureSubscription = async (prepared: PreparedSpaceWebPush) => {
    const existing = await currentSubscription(prepared);
    if (existing) return existing;
    return prepared.registration.pushManager.subscribe({
        applicationServerKey: base64URLKey(prepared.publicKey),
        userVisibleOnly: true,
    });
};

const uploadAccountTarget = async (subscription: PushSubscription) => {
    const details = subscriptionDetails(subscription);
    const response = await fetch(
        await apiURL("/account/space/push/subscription"),
        {
            method: "PUT",
            headers: {
                ...spaceSessionHeaders(),
                "Content-Type": "application/json",
            },
            body: JSON.stringify({
                endpoint: details.endpoint,
                keys: { auth: details.auth, p256dh: details.p256dh },
            }),
        },
    );
    ensureOk(response);
    const { targetId } = SpaceWebPushTargetResponse.parse(
        await response.json(),
    );
    await putTarget({
        endpoint: details.endpoint,
        key: accountTargetKey,
        kind: "account",
        route: "/app",
        targetId,
    });
};

export const reconcileSpaceWebPush = async (): Promise<SpaceWebPushState> => {
    if (!isSpaceWebPushSupported()) return "unavailable";
    let target: StoredPushTarget | undefined;
    try {
        target = await getTarget(accountTargetKey);
    } catch {
        return "unavailable";
    }
    if (Notification.permission == "denied") return "denied";
    const prepared = await preparedSpaceWebPush();
    if (!prepared) return "unavailable";
    const subscription = await currentSubscription(prepared);
    if (!target) {
        if (subscription) {
            if ((await listTargets()).length == 0) {
                if (!(await subscription.unsubscribe())) {
                    throw new Error(
                        "Failed to clear an untracked web push subscription.",
                    );
                }
            }
            await deleteAccountTarget(subscription.endpoint);
        }
        return "unsubscribed";
    }
    if (!subscription) return "recovery";
    await uploadAccountTarget(subscription);
    return "subscribed";
};

export const subscribeToSpaceWebPush = async () => {
    if (!isSpaceWebPushSupported()) {
        throw new Error("Web push is unavailable.");
    }
    const permission =
        Notification.permission == "granted"
            ? "granted"
            : await Notification.requestPermission();
    if (permission != "granted") return permission;
    const prepared = await preparedSpaceWebPush();
    if (!prepared) throw new Error("Web push is unavailable.");
    const subscription = await ensureSubscription(prepared);
    const details = subscriptionDetails(subscription);
    await putTarget({
        endpoint: details.endpoint,
        key: accountTargetKey,
        kind: "account",
        route: "/app",
        targetId: "",
    });
    await uploadAccountTarget(subscription);
    return permission;
};

const deleteAccountTarget = async (endpoint: string) => {
    const response = await fetch(
        await apiURL("/account/space/push/subscription"),
        {
            method: "DELETE",
            headers: {
                ...spaceSessionHeaders(),
                "Content-Type": "application/json",
            },
            body: JSON.stringify({ endpoint }),
        },
    );
    ensureOk(response);
};

const removingLastTarget = async (targetKey: string) => {
    const targets = await listTargets();
    return targets.every((target) => target.key == targetKey);
};

export const unsubscribeFromSpaceWebPush = async () => {
    const prepared = await preparedSpaceWebPush();
    if (!prepared) throw new Error("Web push is unavailable.");
    const target = await getTarget(accountTargetKey);
    if (!target) return;
    const subscription =
        await prepared.registration.pushManager.getSubscription();
    const endpoint = subscription?.endpoint || target.endpoint;
    if (!endpoint) {
        await deleteTarget(accountTargetKey);
        return;
    }
    if (subscription && (await removingLastTarget(accountTargetKey))) {
        if (!(await subscription.unsubscribe())) {
            throw new Error("Failed to unsubscribe from web push.");
        }
        await deleteTarget(accountTargetKey);
        await deleteAccountTarget(endpoint);
        return;
    }
    await deleteAccountTarget(endpoint);
    await deleteTarget(accountTargetKey);
};

export const forgetSpaceWebPushAccountTarget = async () => {
    const target = await getTarget(accountTargetKey);
    if (!target) return;
    await deleteTarget(accountTargetKey);
    if (!isSpaceWebPushSupported() || (await listTargets()).length > 0) return;
    const registration = await navigator.serviceWorker.ready;
    const subscription = await registration.pushManager.getSubscription();
    if (subscription) await subscription.unsubscribe();
};

export const reconcilePublicSpaceWebPush = async (
    session: PublicSpaceLinkSession,
    route: string,
): Promise<SpaceWebPushState> => {
    if (!isSpaceWebPushSupported()) return "unavailable";
    const key = publicTargetKey(route);
    let target: StoredPushTarget | undefined;
    try {
        target = await getTarget(key);
    } catch {
        return "unavailable";
    }
    if (Notification.permission == "denied") return "denied";
    const prepared = await preparedSpaceWebPush();
    if (!prepared) return "unavailable";
    const subscription = await currentSubscription(prepared);
    if (!target) {
        if (subscription) {
            if ((await listTargets()).length == 0) {
                if (!(await subscription.unsubscribe())) {
                    throw new Error(
                        "Failed to clear an untracked web push subscription.",
                    );
                }
            }
            await session.unsubscribeWebPush(subscription.endpoint);
        }
        return "unsubscribed";
    }
    if (!subscription) return "recovery";
    const details = subscriptionDetails(subscription);
    if (
        target.endpoint == details.endpoint &&
        target.targetId &&
        (target.lastSyncedAt ?? 0) > Date.now() - publicTargetSyncInterval
    ) {
        return "subscribed";
    }
    const targetId = await session.subscribeWebPush(
        details.endpoint,
        details.p256dh,
        details.auth,
    );
    await putTarget({
        endpoint: details.endpoint,
        key,
        kind: "public",
        lastSyncedAt: Date.now(),
        route,
        targetId,
    });
    return "subscribed";
};

export const subscribeToPublicSpaceWebPush = async (
    session: PublicSpaceLinkSession,
    route: string,
) => {
    if (!isSpaceWebPushSupported()) {
        throw new Error("Web push is unavailable.");
    }
    const permission =
        Notification.permission == "granted"
            ? "granted"
            : await Notification.requestPermission();
    if (permission != "granted") return permission;
    const prepared = await preparedSpaceWebPush();
    if (!prepared) throw new Error("Web push is unavailable.");
    const key = publicTargetKey(route);
    const previousTarget = await getTarget(key);
    const subscription = await ensureSubscription(prepared);
    const details = subscriptionDetails(subscription);
    if (
        previousTarget?.endpoint &&
        previousTarget.endpoint != details.endpoint
    ) {
        await session.unsubscribeWebPush(previousTarget.endpoint);
    }
    await putTarget({
        endpoint: details.endpoint,
        key,
        kind: "public",
        route,
        targetId: "",
    });
    const targetId = await session.subscribeWebPush(
        details.endpoint,
        details.p256dh,
        details.auth,
    );
    await putTarget({
        endpoint: details.endpoint,
        key,
        kind: "public",
        lastSyncedAt: Date.now(),
        route,
        targetId,
    });
    return permission;
};

export const unsubscribeFromPublicSpaceWebPush = async (
    session: PublicSpaceLinkSession,
    route: string,
) => {
    const prepared = await preparedSpaceWebPush();
    if (!prepared) throw new Error("Web push is unavailable.");
    const key = publicTargetKey(route);
    const target = await getTarget(key);
    if (!target) return;
    const subscription =
        await prepared.registration.pushManager.getSubscription();
    const endpoint = subscription?.endpoint || target.endpoint;
    if (!endpoint) {
        await deleteTarget(key);
        return;
    }
    if (subscription && (await removingLastTarget(key))) {
        if (!(await subscription.unsubscribe())) {
            throw new Error("Failed to unsubscribe from web push.");
        }
        await deleteTarget(key);
        await session.unsubscribeWebPush(endpoint);
        return;
    }
    await session.unsubscribeWebPush(endpoint);
    await deleteTarget(key);
};

const base64URLKey = (value: string): ArrayBuffer => {
    const padding = "=".repeat((4 - (value.length % 4)) % 4);
    const bytes = Uint8Array.from(
        atob((value + padding).replaceAll("-", "+").replaceAll("_", "/")),
        (character) => character.charCodeAt(0),
    );
    return bytes.buffer;
};
