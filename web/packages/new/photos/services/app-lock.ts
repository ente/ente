import { deriveInteractiveKey, deriveKey } from "ente-base/crypto";
import {
    clearMainWindowBlurSuppression,
    shouldSuppressMainWindowBlur,
    suppressMainWindowBlurForTrustedPrompt,
} from "ente-base/electron";
import { getKVN, getKVS, removeKV, setKV } from "ente-base/kv";
import log from "ente-base/log";
import { haveMasterKeyInSession } from "ente-base/session-storage";
import type {
    NativeDeviceLockCapability,
    NativeDeviceLockUnavailableReason,
    PersistedAppLockConfig,
} from "ente-base/types/ipc";

export interface AppLockState {
    supported: boolean;
    enabled: boolean;
    lockType: "pin" | "password" | "device" | "none";
    lockScreenMode: "lock" | "reauthenticate";
    isLocked: boolean;
    invalidAttemptCount: number;
    cooldownExpiresAt: number;
    autoLockTimeMs: number;
}

const createDefaultState = (): AppLockState => ({
    supported: false,
    enabled: false,
    lockType: "none",
    lockScreenMode: "lock",
    isLocked: false,
    invalidAttemptCount: 0,
    cooldownExpiresAt: 0,
    autoLockTimeMs: 0,
});

// Config lives in Electron safe storage; hashes and lockout state live in KV.
class AppLockModuleState {
    constructor() {
        this.snapshot = createDefaultState();
    }

    listeners: (() => void)[] = [];
    snapshot: AppLockState;
}

let _state: AppLockModuleState | undefined;
let _bruteForceStateHydration = Promise.resolve();
let _bruteForceStateHydrationGeneration = 0;
let _wasReauthenticationCancelled = false;

const appLockState = () => {
    _state ??= new AppLockModuleState();
    return _state;
};

export const appLockSubscribe = (onChange: () => void): (() => void) => {
    const state = appLockState();
    state.listeners.push(onChange);
    return () => {
        state.listeners = state.listeners.filter((l) => l != onChange);
    };
};

export const appLockSnapshot = () => appLockState().snapshot;

const setSnapshot = (snapshot: AppLockState) => {
    const state = appLockState();
    state.snapshot = snapshot;
    state.listeners.forEach((l) => {
        l();
    });
};

const ssKeySuppressNextSessionRefreshLock =
    "appLock.suppressNextSessionRefreshLock";

const kvKeyHash = "appLock.hash";
const kvKeySalt = "appLock.salt";
const kvKeyOpsLimit = "appLock.opsLimit";
const kvKeyMemLimit = "appLock.memLimit";
const kvKeyInvalidAttempts = "appLock.invalidAttempts";
const kvKeyCooldownExpiresAt = "appLock.cooldownExpiresAt";

const deviceLockEnablePromptReason = "enable device lock";
const deviceLockUnlockPromptReason = "unlock";
const maxInvalidUnlockAttempts = 10;
const cooldownStartsAtAttempt = 5;
const cooldownBaseSeconds = 30;
const unlockAttemptLockName = "ente-app-lock-unlock-attempt";
const trustedPromptAutoLockSuppressionMs = 5 * 1e3;

export const suppressAutoLockOnBlurForTrustedPrompt = () => {
    suppressMainWindowBlurForTrustedPrompt(trustedPromptAutoLockSuppressionMs);
};

export const shouldSuppressAutoLockOnBlur = () =>
    shouldSuppressMainWindowBlur();

export const clearAutoLockBlurSuppression = () => {
    clearMainWindowBlurSuppression();
};

export const suppressAppLockRefreshFromSessionForTrustedReload = () => {
    // This session flag is consumed by exactly one refresh.
    try {
        if (!appLockSnapshot().enabled) return;
        sessionStorage.setItem(ssKeySuppressNextSessionRefreshLock, "true");
    } catch {
        // Ignore storage write errors; fallback to regular app-lock behavior.
    }
};

const consumeAppLockRefreshSuppressionFromSession = () => {
    try {
        if (
            sessionStorage.getItem(ssKeySuppressNextSessionRefreshLock) !==
            "true"
        ) {
            return false;
        }

        sessionStorage.removeItem(ssKeySuppressNextSessionRefreshLock);
        return true;
    } catch {
        return false;
    }
};

type DeviceLockMode = "native";

type DeviceLockFailureReason = "native-prompt-failed" | "unknown";

const logDeviceLockEvent = (
    phase: "setup" | "unlock",
    status: "not-supported" | "failed",
    reason: NativeDeviceLockUnavailableReason | DeviceLockFailureReason,
    error?: unknown,
) => {
    const message =
        status === "not-supported"
            ? `Device lock ${phase} is not supported`
            : `Device lock ${phase} failed`;

    if (typeof error != "undefined") {
        log.warn(message, { reason, error });
        return;
    }

    log.warn(message, { reason });
};

const appLockCooldownDurationMs = (attemptCount: number): number => {
    // The lock screen and enforcement must use the same cooldown policy.
    if (attemptCount < cooldownStartsAtAttempt) return 0;
    return (
        Math.pow(2, attemptCount - cooldownStartsAtAttempt) *
        cooldownBaseSeconds *
        1000
    );
};

const setBruteForceSnapshot = (
    invalidAttemptCount: number,
    cooldownExpiresAt: number,
) => {
    const snapshot = appLockState().snapshot;
    if (
        snapshot.invalidAttemptCount !== invalidAttemptCount ||
        snapshot.cooldownExpiresAt !== cooldownExpiresAt
    ) {
        setSnapshot({ ...snapshot, invalidAttemptCount, cooldownExpiresAt });
    }
};

const readBruteForceStateFromKV = async () => {
    const [invalidAttempts, cooldownExpiry] = await Promise.all([
        getKVN(kvKeyInvalidAttempts),
        getKVN(kvKeyCooldownExpiresAt),
    ]);

    return {
        invalidAttemptCount: clampNonNegativeInt(invalidAttempts ?? 0),
        cooldownExpiresAt: clampNonNegativeInt(cooldownExpiry ?? 0),
    };
};

const clampNonNegativeInt = (value: number) =>
    Number.isFinite(value) ? Math.max(0, Math.floor(value)) : 0;

const defaultPersistedAppLockConfig = (): PersistedAppLockConfig => ({
    enabled: false,
    lockType: "none",
    autoLockTimeMs: 0,
});

const appLockElectron = () => {
    const electron = globalThis.electron;
    if (
        !electron ||
        typeof electron.isSafeStorageAvailable != "function" ||
        typeof electron.appLockConfigFromSafeStorage != "function" ||
        typeof electron.saveAppLockConfigInSafeStorage != "function" ||
        typeof electron.clearAppLockConfigFromSafeStorage != "function"
    ) {
        return undefined;
    }

    return electron;
};

const isAppLockSupported = async () => {
    const electron = appLockElectron();
    if (!electron) return false;

    try {
        return await electron.isSafeStorageAvailable();
    } catch (e) {
        log.warn("Failed to query safe storage support for app lock", e);
        return false;
    }
};

const readPersistedAppLockConfig = async (): Promise<
    PersistedAppLockConfig | undefined
> => {
    const electron = appLockElectron();
    if (!electron) {
        throw new Error("App lock is not supported");
    }

    const persistedConfig = await electron.appLockConfigFromSafeStorage();
    if (!persistedConfig) return undefined;

    return {
        enabled: persistedConfig.enabled,
        lockType: persistedConfig.lockType,
        autoLockTimeMs: clampNonNegativeInt(persistedConfig.autoLockTimeMs),
    };
};

const savePersistedAppLockConfig = async (config: PersistedAppLockConfig) => {
    const electron = appLockElectron();
    if (!electron || !(await isAppLockSupported())) {
        throw new Error("App lock is not supported");
    }

    await electron.saveAppLockConfigInSafeStorage({
        enabled: config.enabled,
        lockType: config.lockType,
        autoLockTimeMs: clampNonNegativeInt(config.autoLockTimeMs),
    });
};

const clearPersistedAppLockConfig = async () => {
    const electron = appLockElectron();
    if (!electron) {
        throw new Error("App lock is not supported");
    }

    await electron.clearAppLockConfigFromSafeStorage();
};

const setSnapshotFromPersistedConfig = (
    config: PersistedAppLockConfig,
    isLocked: boolean,
    supported = true,
) => {
    const snapshot = appLockState().snapshot;
    setSnapshot({
        ...snapshot,
        supported,
        enabled: config.enabled,
        lockType: config.lockType,
        lockScreenMode: "lock",
        isLocked,
        autoLockTimeMs: config.autoLockTimeMs,
    });
    hydrateBruteForceStateIfNeeded();
};

let _localUnlockAttemptQueue = Promise.resolve();

const withLocalUnlockAttemptLock = async <T>(fn: () => Promise<T>) => {
    const previous = _localUnlockAttemptQueue;
    let releaseCurrent: (() => void) | undefined;

    _localUnlockAttemptQueue = new Promise<void>((resolve) => {
        releaseCurrent = resolve;
    });

    await previous;
    try {
        return await fn();
    } finally {
        releaseCurrent?.();
    }
};

const withUnlockAttemptLock = async <T>(fn: () => Promise<T>) => {
    // Web Locks serialize counters across tabs; the fallback covers this tab.
    const locks =
        typeof navigator == "undefined"
            ? undefined
            : (navigator as Navigator & { locks?: LockManager }).locks;

    if (locks && typeof locks.request == "function") {
        const result: unknown = await locks.request(
            unlockAttemptLockName,
            { mode: "exclusive" },
            fn,
        );
        return result as T;
    }

    return withLocalUnlockAttemptLock(fn);
};

export const initAppLock = async () => {
    if (!appLockElectron()) {
        setSnapshot(createDefaultState());
        stopBruteForceStateHydration();
        return;
    }

    const persistedConfig = await readPersistedAppLockConfig();
    const config = persistedConfig ?? defaultPersistedAppLockConfig();

    if (persistedConfig && !persistedConfig.enabled) {
        try {
            await clearPersistedAppLockConfig();
        } catch (e) {
            log.warn("Failed to remove disabled app lock config", e);
        }
    }

    if (!(await isAppLockSupported())) {
        if (config.enabled) {
            throw new Error("Safe storage unavailable for enabled app lock");
        }
        setSnapshot(createDefaultState());
        stopBruteForceStateHydration();
        return;
    }

    // Lock before session hydration, then restore persisted brute-force state.
    setSnapshotFromPersistedConfig(config, config.enabled, true);
};

const restoreBruteForceState = async (generation: number) => {
    try {
        const { invalidAttemptCount, cooldownExpiresAt } =
            await readBruteForceStateFromKV();

        if (generation !== _bruteForceStateHydrationGeneration) {
            return;
        }

        setBruteForceSnapshot(invalidAttemptCount, cooldownExpiresAt);
    } catch (e) {
        log.error("Failed to restore brute-force state from KV DB", e);
    }
};

const stopBruteForceStateHydration = () => {
    _bruteForceStateHydrationGeneration += 1;
    _bruteForceStateHydration = Promise.resolve();
};

const hydrateBruteForceStateIfNeeded = () => {
    const snapshot = appLockState().snapshot;
    const isPassphraseLock =
        snapshot.lockType === "pin" || snapshot.lockType === "password";
    if (!snapshot.isLocked || !isPassphraseLock) {
        stopBruteForceStateHydration();
        return;
    }

    const generation = ++_bruteForceStateHydrationGeneration;
    _bruteForceStateHydration = restoreBruteForceState(generation);
};

const ensureBruteForceStateHydrated = async () => {
    await _bruteForceStateHydration;
};

const unsupportedNativeDeviceLockCapability: NativeDeviceLockCapability = {
    available: false,
    provider: "none",
    reason: "unsupported-platform",
};

const nativeDeviceLockCapability =
    async (): Promise<NativeDeviceLockCapability> => {
        if (!globalThis.electron) return unsupportedNativeDeviceLockCapability;

        try {
            if (
                typeof globalThis.electron.getNativeDeviceLockCapability ==
                "function"
            ) {
                return await globalThis.electron.getNativeDeviceLockCapability();
            }

            return unsupportedNativeDeviceLockCapability;
        } catch (e) {
            log.warn("Failed to query native device lock support", e);
            return unsupportedNativeDeviceLockCapability;
        }
    };

type DeviceLockCapability =
    | { usable: true; mode: DeviceLockMode }
    | { usable: false; reason: NativeDeviceLockUnavailableReason };

const nativeCapabilityUnavailableReason = (
    capability: NativeDeviceLockCapability,
): NativeDeviceLockUnavailableReason => {
    switch (capability.reason) {
        case "touchid-not-enrolled":
        case "touchid-temporarily-unavailable":
        case "touchid-api-error":
            return capability.reason;
        default:
            return "unsupported-platform";
    }
};

const resolveDeviceLockCapability = async (): Promise<DeviceLockCapability> => {
    const nativeCapability = await nativeDeviceLockCapability();
    if (nativeCapability.available) return { usable: true, mode: "native" };

    const reason = nativeCapabilityUnavailableReason(nativeCapability);
    if (reason === "touchid-temporarily-unavailable") {
        // Keep setup retryable while macOS reports a transient failure.
        return { usable: true, mode: "native" };
    }

    return { usable: false, reason };
};

export const shouldShowDeviceLockOption = async () => {
    if (!appLockSnapshot().supported) return false;

    const capability = await nativeDeviceLockCapability();
    if (capability.available) return true;

    return (
        nativeCapabilityUnavailableReason(capability) !== "unsupported-platform"
    );
};

const clearPassphraseMaterial = async () =>
    Promise.all([
        removeKV(kvKeyHash),
        removeKV(kvKeySalt),
        removeKV(kvKeyOpsLimit),
        removeKV(kvKeyMemLimit),
    ]);

const resetBruteForceState = async () => {
    await Promise.all([
        setKV(kvKeyInvalidAttempts, 0),
        setKV(kvKeyCooldownExpiresAt, 0),
    ]);
    setBruteForceSnapshot(0, 0);
};

const unlockLocally = () => {
    const snapshot = appLockState().snapshot;
    const wasReauthentication = snapshot.lockScreenMode === "reauthenticate";
    setSnapshot({
        ...snapshot,
        lockScreenMode: "lock",
        isLocked: false,
        invalidAttemptCount: 0,
        cooldownExpiresAt: 0,
    });
    if (wasReauthentication) {
        _wasReauthenticationCancelled = false;
    }
    stopBruteForceStateHydration();
};

export const cancelReauthentication = () => {
    const snapshot = appLockState().snapshot;
    if (!snapshot.isLocked || snapshot.lockScreenMode !== "reauthenticate") {
        return;
    }

    _wasReauthenticationCancelled = true;
    setSnapshot({ ...snapshot, lockScreenMode: "lock", isLocked: false });
    stopBruteForceStateHydration();
};

export const refreshAppLockStateFromSession = async () => {
    if (!(await isAppLockSupported())) {
        if (appLockSnapshot().enabled) {
            throw new Error("Safe storage unavailable for enabled app lock");
        }
        setSnapshot(createDefaultState());
        stopBruteForceStateHydration();
        return;
    }

    const persistedConfig = await readPersistedAppLockConfig();
    if (!persistedConfig && appLockSnapshot().enabled) {
        throw new Error("Persisted app lock config is unavailable");
    }
    const config = persistedConfig ?? defaultPersistedAppLockConfig();
    const shouldSuppressLockForTrustedReload =
        consumeAppLockRefreshSuppressionFromSession();
    const isLocked =
        config.enabled &&
        haveMasterKeyInSession() &&
        !shouldSuppressLockForTrustedReload;
    setSnapshotFromPersistedConfig(config, isLocked, true);
};

export type SetupDeviceLockResult =
    | { status: "success"; mode: DeviceLockMode }
    | { status: "not-supported"; reason: NativeDeviceLockUnavailableReason }
    | { status: "failed"; reason: DeviceLockFailureReason };

const setupPassphraseLock = async (
    lockType: Extract<AppLockState["lockType"], "pin" | "password">,
    input: string,
) => {
    if (!(await isAppLockSupported())) {
        throw new Error("App lock is not supported");
    }

    const derived = await deriveInteractiveKey(input);
    await Promise.all([
        setKV(kvKeyHash, derived.key),
        setKV(kvKeySalt, derived.salt),
        setKV(kvKeyOpsLimit, derived.opsLimit),
        setKV(kvKeyMemLimit, derived.memLimit),
        resetBruteForceState(),
    ]);

    const snapshot = appLockState().snapshot;
    await savePersistedAppLockConfig({
        enabled: true,
        lockType,
        autoLockTimeMs: snapshot.autoLockTimeMs,
    });
    setSnapshot({
        ...snapshot,
        enabled: true,
        lockType,
        invalidAttemptCount: 0,
        cooldownExpiresAt: 0,
    });
    stopBruteForceStateHydration();
};

export const setupPin = async (pin: string) => setupPassphraseLock("pin", pin);

export const setupPassword = async (password: string) =>
    setupPassphraseLock("password", password);

export const setupDeviceLock = async (): Promise<SetupDeviceLockResult> => {
    if (!(await isAppLockSupported())) {
        return { status: "failed", reason: "unknown" };
    }

    const capability = await resolveDeviceLockCapability();

    if (!capability.usable) {
        logDeviceLockEvent("setup", "not-supported", capability.reason);
        return { status: "not-supported", reason: capability.reason };
    }

    try {
        // The native prompt blurs the window but must not auto-lock it.
        suppressAutoLockOnBlurForTrustedPrompt();

        const unlocked = await globalThis.electron?.promptDeviceLock(
            deviceLockEnablePromptReason,
        );
        if (!unlocked) {
            logDeviceLockEvent("setup", "failed", "native-prompt-failed");
            return { status: "failed", reason: "native-prompt-failed" };
        }

        await resetBruteForceState();

        const snapshot = appLockState().snapshot;
        await savePersistedAppLockConfig({
            enabled: true,
            lockType: "device",
            autoLockTimeMs: snapshot.autoLockTimeMs,
        });
        setSnapshot({
            ...snapshot,
            enabled: true,
            lockType: "device",
            invalidAttemptCount: 0,
            cooldownExpiresAt: 0,
        });

        stopBruteForceStateHydration();

        return { status: "success", mode: "native" };
    } catch (e) {
        log.error("Failed to set up device lock app lock", e);
        return { status: "failed", reason: "unknown" };
    }
};

export type UnlockResult = "success" | "failed" | "cooldown" | "logout";

export type DeviceLockUnlockResult =
    | { status: "success"; mode: DeviceLockMode }
    | { status: "not-supported"; reason: NativeDeviceLockUnavailableReason }
    | { status: "failed"; reason: DeviceLockFailureReason };

export const attemptDeviceLockUnlock =
    async (): Promise<DeviceLockUnlockResult> => {
        const capability = await resolveDeviceLockCapability();
        if (!capability.usable) {
            logDeviceLockEvent("unlock", "not-supported", capability.reason);
            return { status: "not-supported", reason: capability.reason };
        }

        try {
            const unlocked = await globalThis.electron?.promptDeviceLock(
                deviceLockUnlockPromptReason,
            );
            if (!unlocked) {
                logDeviceLockEvent("unlock", "failed", "native-prompt-failed");
                return { status: "failed", reason: "native-prompt-failed" };
            }

            await resetBruteForceState();
            unlockLocally();
            return { status: "success", mode: "native" };
        } catch (e) {
            log.error("Failed device lock unlock attempt", e);
            return { status: "failed", reason: "unknown" };
        }
    };

export const attemptUnlock = async (input: string): Promise<UnlockResult> => {
    const snapshot = appLockState().snapshot;
    const isPassphraseLock =
        snapshot.lockType === "pin" || snapshot.lockType === "password";
    if (!isPassphraseLock) {
        return "failed";
    }

    return withUnlockAttemptLock<UnlockResult>(async () => {
        await ensureBruteForceStateHydrated();

        // Merge with KV so a stale tab cannot lower another tab's counters.
        const persistedState = await readBruteForceStateFromKV();
        const latestSnapshot = appLockState().snapshot;
        const invalidAttemptCount = Math.max(
            latestSnapshot.invalidAttemptCount,
            persistedState.invalidAttemptCount,
        );
        const cooldownExpiresAt = Math.max(
            latestSnapshot.cooldownExpiresAt,
            persistedState.cooldownExpiresAt,
        );

        setBruteForceSnapshot(invalidAttemptCount, cooldownExpiresAt);

        if (invalidAttemptCount >= maxInvalidUnlockAttempts) {
            await setKV(kvKeyCooldownExpiresAt, 0);
            setBruteForceSnapshot(invalidAttemptCount, 0);
            return "logout";
        }

        const snapshotWithCooldown = appLockState().snapshot;
        if (
            snapshotWithCooldown.cooldownExpiresAt > 0 &&
            Date.now() < snapshotWithCooldown.cooldownExpiresAt
        ) {
            return "cooldown";
        }

        const salt = await getKVS(kvKeySalt);
        const storedHash = await getKVS(kvKeyHash);
        const opsLimit = await getKVN(kvKeyOpsLimit);
        const memLimit = await getKVN(kvKeyMemLimit);

        if (!salt || !storedHash || !opsLimit || !memLimit) {
            log.error("App lock credentials missing from KV DB");
            return "failed";
        }

        const derivedKey = await deriveKey(input, salt, opsLimit, memLimit);

        if (derivedKey === storedHash) {
            await resetBruteForceState();
            unlockLocally();
            return "success";
        }

        const count = invalidAttemptCount + 1;
        await setKV(kvKeyInvalidAttempts, count);

        if (count >= maxInvalidUnlockAttempts) {
            await setKV(kvKeyCooldownExpiresAt, 0);
            setBruteForceSnapshot(count, 0);
            return "logout";
        }

        if (count >= cooldownStartsAtAttempt) {
            const expiresAt = Date.now() + appLockCooldownDurationMs(count);
            await setKV(kvKeyCooldownExpiresAt, expiresAt);
            setBruteForceSnapshot(count, expiresAt);

            return "cooldown";
        } else {
            setBruteForceSnapshot(count, 0);
        }

        return "failed";
    });
};

export type ReauthenticateWithAppLockResult =
    | "authenticated"
    | "cancelled"
    | "fallback";

export const reauthenticateWithAppLock =
    async (): Promise<ReauthenticateWithAppLockResult> => {
        try {
            _wasReauthenticationCancelled = false;
            const snapshot = appLockSnapshot();
            let canUseAppLock =
                snapshot.enabled && snapshot.lockType !== "none";
            if (canUseAppLock && snapshot.lockType === "device") {
                // Let callers fall back to password if native auth is unavailable.
                const capability = await resolveDeviceLockCapability();
                canUseAppLock = capability.usable;
            }
            if (!canUseAppLock) return "fallback";

            return await new Promise<ReauthenticateWithAppLockResult>(
                (resolve) => {
                    const unsubscribe = appLockSubscribe(() => {
                        if (!appLockSnapshot().isLocked) {
                            unsubscribe();
                            const wasAuthenticated =
                                !_wasReauthenticationCancelled;
                            _wasReauthenticationCancelled = false;
                            resolve(
                                wasAuthenticated
                                    ? "authenticated"
                                    : "cancelled",
                            );
                        }
                    });

                    lock("reauthenticate");
                    if (!appLockSnapshot().isLocked) {
                        unsubscribe();
                        resolve("fallback");
                    }
                },
            );
        } catch (e) {
            log.error("Failed to start app lock reauthentication", e);
            return "fallback";
        }
    };

export const lock = (
    lockScreenMode: AppLockState["lockScreenMode"] = "lock",
) => {
    const snapshot = appLockState().snapshot;
    setSnapshot({ ...snapshot, lockScreenMode, isLocked: true });
    hydrateBruteForceStateIfNeeded();
};

export const logoutAppLock = async () => {
    if (appLockElectron()) {
        await clearPersistedAppLockConfig();
    }

    await Promise.all([
        clearPassphraseMaterial(),
        removeKV(kvKeyInvalidAttempts),
        removeKV(kvKeyCooldownExpiresAt),
    ]);

    stopBruteForceStateHydration();
    _wasReauthenticationCancelled = false;
    _state = undefined;
};

export const setAutoLockTime = async (ms: number) => {
    if (!(await isAppLockSupported())) {
        throw new Error("App lock is not supported");
    }

    const autoLockTimeMs = clampNonNegativeInt(ms);
    const snapshot = appLockState().snapshot;
    await savePersistedAppLockConfig({
        enabled: snapshot.enabled,
        lockType: snapshot.lockType,
        autoLockTimeMs,
    });
    setSnapshot({ ...snapshot, autoLockTimeMs });
};

export const disableAppLock = async () => {
    if (!(await isAppLockSupported())) {
        throw new Error("App lock is not supported");
    }

    const snapshot = appLockState().snapshot;
    await clearPersistedAppLockConfig();
    setSnapshot({
        ...snapshot,
        enabled: false,
        lockType: "none",
        lockScreenMode: "lock",
        isLocked: false,
        invalidAttemptCount: 0,
        cooldownExpiresAt: 0,
    });
    stopBruteForceStateHydration();

    await Promise.all([
        clearPassphraseMaterial(),
        removeKV(kvKeyInvalidAttempts),
        removeKV(kvKeyCooldownExpiresAt),
    ]);
};
