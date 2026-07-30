/**
 * @file Service for the app lock feature.
 *
 * App lock is a purely client-side feature that prevents unauthorized access to
 * the app after it has been authenticated. It supports PIN, password, and
 * local native device lock (macOS Touch ID), and uses Argon2id for passphrase
 * hashing.
 *
 * See: [Note: Snapshots and useSyncExternalStore].
 */

import { deriveInteractiveKey, deriveKey } from "ente-base/crypto";
import {
    clearMainWindowBlurSuppression,
    shouldSuppressMainWindowBlur,
    suppressMainWindowBlurForTrustedPrompt,
} from "ente-base/electron";
import { getKVN, getKVS, removeKV, setKV } from "ente-base/kv";
import log from "ente-base/log";
import { haveMasterKeyInSession } from "ente-base/session";
import type {
    NativeDeviceLockCapability,
    NativeDeviceLockUnavailableReason,
    PersistedAppLockConfig,
} from "ente-base/types/ipc";

/**
 * In-memory state for the app lock feature.
 *
 * Desktop config is persisted only in Electron safe storage, while passphrase
 * and brute-force state live in IndexedDB via KV DB.
 */
export interface AppLockState {
    /** Whether app lock is supported in the current desktop environment. */
    supported: boolean;
    /** Whether app lock is enabled. */
    enabled: boolean;
    /** Active lock type. */
    lockType: "pin" | "password" | "device" | "none";
    /** Why the lock screen is currently shown. */
    lockScreenMode: "lock" | "reauthenticate";
    /** Whether the app is currently locked. */
    isLocked: boolean;
    /** Consecutive failed attempts in current lockout cycle. */
    invalidAttemptCount: number;
    /** Epoch ms when cooldown expires (0 = no cooldown). */
    cooldownExpiresAt: number;
    /** Auto-lock delay in milliseconds. */
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

/**
 * Internal in-memory state shared by the functions in this module.
 *
 * This entire object will be reset on logout.
 */
class AppLockModuleState {
    constructor() {
        this.snapshot = createDefaultState();
    }

    /**
     * Subscriptions to {@link AppLockState} updates attached using
     * {@link appLockSubscribe}.
     */
    listeners: (() => void)[] = [];

    /**
     * Snapshot of the {@link AppLockState} returned by
     * {@link appLockSnapshot}.
     */
    snapshot: AppLockState;
}

/** State shared by the functions in this module. */
let _state: AppLockModuleState | undefined;
let _bruteForceStateHydration = Promise.resolve();
let _bruteForceStateHydrationGeneration = 0;
let _wasReauthenticationCancelled = false;

const appLockState = () => {
    _state ??= new AppLockModuleState();
    return _state;
};

/**
 * Subscribe to updates to {@link AppLockState}.
 *
 * The callback is invoked whenever {@link setSnapshot} updates
 * {@link _state.snapshot}. Returns an unsubscribe function that removes the
 * callback from the listener list.
 *
 * See: [Note: Snapshots and useSyncExternalStore].
 */
export const appLockSubscribe = (onChange: () => void): (() => void) => {
    const state = appLockState();
    state.listeners.push(onChange);
    return () => {
        state.listeners = state.listeners.filter((l) => l != onChange);
    };
};

/**
 * Return the last known, cached {@link AppLockState}.
 *
 * See also {@link appLockSubscribe}.
 */
export const appLockSnapshot = () => appLockState().snapshot;

/**
 * Update the internal app lock state snapshot and notify all subscribers.
 *
 * This is the single source of truth for state updates. All modifications to
 * _state.snapshot must go through this function to ensure subscribers are
 * properly notified of changes.
 *
 * See: [Note: Snapshots and useSyncExternalStore].
 */
const setSnapshot = (snapshot: AppLockState) => {
    const state = appLockState();
    state.snapshot = snapshot;
    state.listeners.forEach((l) => {
        l();
    });
};

const ssKeySuppressNextSessionRefreshLock =
    "appLock.suppressNextSessionRefreshLock";

// -- KV DB keys (IndexedDB, async) --

const kvKeyHash = "appLock.hash";
const kvKeySalt = "appLock.salt";
const kvKeyOpsLimit = "appLock.opsLimit";
const kvKeyMemLimit = "appLock.memLimit";
const kvKeyInvalidAttempts = "appLock.invalidAttempts";
const kvKeyCooldownExpiresAt = "appLock.cooldownExpiresAt";

// -- Device lock constants --

const deviceLockEnablePromptReason = "enable device lock";
const deviceLockUnlockPromptReason = "unlock";
const maxInvalidUnlockAttempts = 10;
const cooldownStartsAtAttempt = 5;
const cooldownBaseSeconds = 30;
const unlockAttemptLockName = "ente-app-lock-unlock-attempt";
const trustedPromptAutoLockSuppressionMs = 5 * 1e3;

/**
 * Temporarily suppress auto-lock on blur for trusted app-initiated prompts.
 *
 * This is used for native device authentication prompts that can transiently
 * blur the app window even though the user hasn't backgrounded the app.
 */
export const suppressAutoLockOnBlurForTrustedPrompt = () => {
    suppressMainWindowBlurForTrustedPrompt(trustedPromptAutoLockSuppressionMs);
};

/**
 * Return true if blur-triggered auto-lock should currently be suppressed.
 */
export const shouldSuppressAutoLockOnBlur = () =>
    shouldSuppressMainWindowBlur();

/**
 * Clear any pending blur auto-lock suppression.
 */
export const clearAutoLockBlurSuppression = () => {
    clearMainWindowBlurSuppression();
};

/**
 * Suppress one app-lock refresh cycle after a trusted app-initiated reload.
 */
export const suppressAppLockRefreshFromSessionForTrustedReload = () => {
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
        // Ignore storage read errors; fallback to regular app-lock behavior.
        return false;
    }
};

export type DeviceLockMode = "native";

export type DeviceLockFailureReason = "native-prompt-failed" | "unknown";

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

/**
 * Return the cooldown duration for a failed-attempt count.
 *
 * This policy is shared by lockout enforcement and cooldown UI (used by the
 * app lock screen to render countdown progress).
 */
export const appLockCooldownDurationMs = (attemptCount: number): number => {
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

/**
 *
 * @param value the autoLockTimeMS
 * @returns clampedNonNegativeFinite integer value
 *
 * So this function is bascially a normalization function, to update the
 * value of the autoLockTimeMs in case it becomes any non-negative/non-finite
 * number like -4 or NaN in-case of some corruption or unexpected case.
 */
const clampNonNegativeInt = (value: number) =>
    Number.isFinite(value) ? Math.max(0, Math.floor(value)) : 0;

const defaultPersistedAppLockConfig = (): PersistedAppLockConfig => ({
    enabled: false,
    lockType: "none",
    autoLockTimeMs: 0,
});

/**
 * Validates and retrieves the Electron app lock API from the global scope.
 *
 * Checks if the Electron API is available and has all required app lock
 * related functions before returning it. This ensures safe access to
 * Electron's secure storage capabilities for app lock configuration.
 *
 * @returns {Object | undefined} The Electron API object with app lock methods
 *                                if all required functions are available,
 *                                otherwise undefined.
 */
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

/**
 * Update in-memory app-lock state from persisted config.
 *
 * Used during `initAppLock` (cold start) and
 * `refreshAppLockStateFromSession` (after session restore).
 */
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

/**
 * Serialize unlock attempts within the current tab.
 *
 * This fallback mutex is used when the Web Locks API is unavailable.
 */
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

/**
 * Serialize unlock attempts across tabs when possible.
 *
 * Uses the Web Locks API for cross-tab mutual exclusion, and falls back to
 * {@link withLocalUnlockAttemptLock} when unavailable.
 */
const withUnlockAttemptLock = async <T>(fn: () => Promise<T>) => {
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

// -- Public API --

/**
 * Initialize app lock state from persistent storage on cold start.
 *
 * On desktop, this restores the config from Electron safe storage before
 * gating rendering, then locks pessimistically while session hydration is in
 * flight.
 *
 * After the initial snapshot, asynchronously restores the brute-force
 * attempt count and cooldown expiry from KV DB so that a page refresh cannot
 * bypass the cooldown.
 */
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

    setSnapshotFromPersistedConfig(config, config.enabled, true);
};

/**
 * Restore the brute-force attempt count and cooldown expiry from KV DB into
 * the in-memory snapshot.
 *
 * Called during {@link initAppLock} to ensure that cooldown timers persist
 * across page refreshes.
 */
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
        // Native device lock is available only in the desktop (Electron) app.
        // On web, we always treat it as unsupported.
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
        // Keep unlock/setup retryable on macOS even when capability checks are
        // briefly inconclusive.
        return { usable: true, mode: "native" };
    }

    return { usable: false, reason };
};

/**
 * Return true if the current environment should show "Device lock" in the
 * lock-type picker.
 *
 * We show it when native auth is currently available, or when the platform
 * supports it but setup/auth is temporarily unavailable (for example, Touch ID
 * not enrolled).
 */
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

/**
 * Reset brute-force protection state.
 *
 * Clears persisted invalid-attempt and cooldown values in KV and updates the
 * in-memory snapshot to zero.
 */
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

/**
 * Cancel an in-progress explicit reauthentication prompt.
 *
 * This only dismisses the reauthentication lock screen, allowing callers of
 * {@link reauthenticateWithAppLock} to fall back to alternate auth flows.
 */
export const cancelReauthentication = () => {
    const snapshot = appLockState().snapshot;
    if (!snapshot.isLocked || snapshot.lockScreenMode !== "reauthenticate") {
        return;
    }

    _wasReauthenticationCancelled = true;
    setSnapshot({ ...snapshot, lockScreenMode: "lock", isLocked: false });
    stopBruteForceStateHydration();
};

/**
 * Recompute and refresh whether the app should currently be locked based on
 * session availability.
 *
 * Call this after desktop safe-storage restore to prevent auto-login bypass.
 */
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

/**
 * The result of a device lock setup attempt.
 *
 * - `success` - Device lock setup completed and app lock configured.
 * - `not-supported` - Platform authenticator is unavailable in this context.
 * - `failed` - Setup failed or was cancelled by the user.
 */
export type SetupDeviceLockResult =
    | { status: "success"; mode: DeviceLockMode }
    | { status: "not-supported"; reason: NativeDeviceLockUnavailableReason }
    | { status: "failed"; reason: DeviceLockFailureReason };

/**
 * Set up a PIN for app lock.
 *
 * Derives a key from the PIN using Argon2id with interactive limits, stores
 * the hash and derivation parameters in KV DB, and enables the lock.
 */
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

/**
 * Set up a password for app lock.
 *
 * Same as {@link setupPin} but sets the lock type to "password".
 */
export const setupPassword = async (password: string) =>
    setupPassphraseLock("password", password);

/**
 * Set up native device lock authentication for app lock (macOS only).
 */
export const setupDeviceLock = async (): Promise<SetupDeviceLockResult> => {
    if (!(await isAppLockSupported())) {
        return { status: "failed", reason: "unknown" };
    }

    // Resolve whether native device lock is currently usable in this environment.
    // Flow: resolveDeviceLockCapability() -> nativeDeviceLockCapability() ->
    // globalThis.electron.getNativeDeviceLockCapability().
    const capability = await resolveDeviceLockCapability();

    // Surface unsupported reasons to callers/UI.
    if (!capability.usable) {
        logDeviceLockEvent("setup", "not-supported", capability.reason);
        return { status: "not-supported", reason: capability.reason };
    }

    try {
        // Ignore blur auto-lock caused by this trusted, app-initiated native
        // prompt.
        suppressAutoLockOnBlurForTrustedPrompt();

        // Trigger the OS-native authentication prompt (for example, Touch ID).
        const unlocked = await globalThis.electron?.promptDeviceLock(
            deviceLockEnablePromptReason,
        );
        if (!unlocked) {
            logDeviceLockEvent("setup", "failed", "native-prompt-failed");
            return { status: "failed", reason: "native-prompt-failed" };
        }

        // Reset brute-force lockout/cooldown state in KV and in memory.
        await resetBruteForceState();

        // Update the in-memory app-lock snapshot.
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

        // Stop ongoing brute-force hydration.
        stopBruteForceStateHydration();

        return { status: "success", mode: "native" };
    } catch (e) {
        log.error("Failed to set up device lock app lock", e);
        return { status: "failed", reason: "unknown" };
    }
};

/**
 * The result of an unlock attempt.
 *
 * - `"success"` - The input was correct; the app is now unlocked.
 * - `"failed"` - The input was incorrect.
 * - `"cooldown"` - Too many recent attempts; currently in cooldown.
 * - `"logout"` - Too many total attempts (>= 10); caller should force logout.
 */
export type UnlockResult = "success" | "failed" | "cooldown" | "logout";

/**
 * The result of a device lock unlock attempt.
 */
export type DeviceLockUnlockResult =
    | { status: "success"; mode: DeviceLockMode }
    | { status: "not-supported"; reason: NativeDeviceLockUnavailableReason }
    | { status: "failed"; reason: DeviceLockFailureReason };

/**
 * Attempt to unlock the app using native device lock (macOS only).
 */
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

/**
 * Attempt to unlock the app with the given PIN or password.
 *
 * Implements brute-force protection: after 5 failed attempts, a cooldown
 * period is enforced (exponential backoff starting at 30s). After 10 failed
 * attempts, signals that the caller should force-logout the user.
 */
export const attemptUnlock = async (input: string): Promise<UnlockResult> => {
    /**
     * This flow applies only to PIN and password locks.
     * Guard against being called for any other lock type.
     */
    const snapshot = appLockState().snapshot;
    const isPassphraseLock =
        snapshot.lockType === "pin" || snapshot.lockType === "password";
    if (!isPassphraseLock) {
        return "failed";
    }

    return withUnlockAttemptLock<UnlockResult>(async () => {
        // Ensure persisted lockout state has been rehydrated before enforcing.
        await ensureBruteForceStateHydrated();

        /**
         * Refresh lockout state from KV so stale tabs cannot reset counters.
         *
         * If multiple tabs attempt to unlock at the same time, sync from KV DB
         * before validation so all tabs use the latest attempt/cooldown state.
         */
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

        // Update the snapshot with the latest values.
        setBruteForceSnapshot(invalidAttemptCount, cooldownExpiresAt);

        if (invalidAttemptCount >= maxInvalidUnlockAttempts) {
            await setKV(kvKeyCooldownExpiresAt, 0);
            setBruteForceSnapshot(invalidAttemptCount, 0);
            return "logout";
        }

        // Check cooldown from in-memory state.
        const snapshotWithCooldown = appLockState().snapshot;
        if (
            snapshotWithCooldown.cooldownExpiresAt > 0 &&
            Date.now() < snapshotWithCooldown.cooldownExpiresAt
        ) {
            return "cooldown";
        }

        // Read stored derivation parameters and hash from KV DB.
        const salt = await getKVS(kvKeySalt);
        const storedHash = await getKVS(kvKeyHash);
        const opsLimit = await getKVN(kvKeyOpsLimit);
        const memLimit = await getKVN(kvKeyMemLimit);

        if (!salt || !storedHash || !opsLimit || !memLimit) {
            log.error("App lock credentials missing from KV DB");
            return "failed";
        }

        // Derive key from input using the stored parameters.
        const derivedKey = await deriveKey(input, salt, opsLimit, memLimit);

        if (derivedKey === storedHash) {
            // Correct input: reset attempts, unlock.
            await resetBruteForceState();
            unlockLocally();
            return "success";
        }

        // Incorrect input: increment attempts.
        const count = invalidAttemptCount + 1;
        await setKV(kvKeyInvalidAttempts, count);

        if (count >= maxInvalidUnlockAttempts) {
            // Too many attempts: signal logout.
            await setKV(kvKeyCooldownExpiresAt, 0);
            setBruteForceSnapshot(count, 0);
            return "logout";
        }

        if (count >= cooldownStartsAtAttempt) {
            // Enforce cooldown with exponential backoff.
            const expiresAt = Date.now() + appLockCooldownDurationMs(count);
            await setKV(kvKeyCooldownExpiresAt, expiresAt);
            setBruteForceSnapshot(count, expiresAt);

            // The current failed attempt has triggered cooldown, so surface the
            // cooldown state immediately to callers/UI.
            return "cooldown";
        } else {
            setBruteForceSnapshot(count, 0);
        }

        return "failed";
    });
};

/**
 * Perform an explicit reauthentication using app lock.
 *
 * - `"authenticated"` when app lock reauthentication succeeds.
 * - `"cancelled"` when the user dismisses the reauthentication prompt.
 * - `"fallback"` when app lock is unavailable or cannot be started, so callers
 *   can use an alternate auth flow (for example, master password prompt).
 */
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
                // For device lock, ensure native auth is actually usable right now.
                // If unavailable (e.g. Touch ID disabled), fall back to password flow.
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

/**
 * Lock the app.
 */
export const lock = (
    lockScreenMode: AppLockState["lockScreenMode"] = "lock",
) => {
    const snapshot = appLockState().snapshot;
    setSnapshot({ ...snapshot, lockScreenMode, isLocked: true });
    hydrateBruteForceStateIfNeeded();
};

/**
 * Clear all app lock data on logout.
 *
 * Removes all persisted config and KV DB keys, and resets in-memory state to
 * defaults.
 */
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

/**
 * Update the auto-lock delay.
 */
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

/**
 * Disable app lock entirely.
 *
 * Clears all stored credentials from KV DB, resets attempts and cooldown, and
 * updates persisted config and in-memory state.
 */
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
