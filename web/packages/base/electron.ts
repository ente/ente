import type { Electron } from "./types/ipc";

export const ensureElectron = (): Electron => {
    const et = globalThis.electron;
    if (et) return et;
    throw new Error(
        "Attempting to assert globalThis.electron in a non-electron context",
    );
};

const defaultTrustedWindowBlurSuppressionMs = 5 * 1e3;
let suppressMainWindowBlurUntil = 0;

// Native prompts blur the window without meaning the app was backgrounded.
export const suppressMainWindowBlurForTrustedPrompt = (
    durationMs = defaultTrustedWindowBlurSuppressionMs,
) => {
    if (durationMs <= 0) return;
    suppressMainWindowBlurUntil = Math.max(
        suppressMainWindowBlurUntil,
        Date.now() + durationMs,
    );
};

export const shouldSuppressMainWindowBlur = () =>
    Date.now() < suppressMainWindowBlurUntil;

export const clearMainWindowBlurSuppression = () => {
    suppressMainWindowBlurUntil = 0;
};

type MainWindowFocusListener = () => void;
type MainWindowBlurListener = () => void;

// Electron exposes one callback per event; multiplex local subscribers here.
const mainWindowFocusListeners = new Set<MainWindowFocusListener>();
let hasAttachedMainWindowFocusBridge = false;
const mainWindowBlurListeners = new Set<MainWindowBlurListener>();
let hasAttachedMainWindowBlurBridge = false;

const emitMainWindowFocus = () => {
    for (const listener of mainWindowFocusListeners) {
        listener();
    }
};

const attachMainWindowFocusBridgeIfNeeded = () => {
    if (hasAttachedMainWindowFocusBridge) return;
    const electron = globalThis.electron;
    if (!electron) return;
    electron.onMainWindowFocus(emitMainWindowFocus);
    hasAttachedMainWindowFocusBridge = true;
};

const detachMainWindowFocusBridgeIfNeeded = () => {
    if (
        !hasAttachedMainWindowFocusBridge ||
        mainWindowFocusListeners.size > 0
    ) {
        return;
    }

    const electron = globalThis.electron;
    if (electron) {
        electron.onMainWindowFocus(undefined);
    }
    hasAttachedMainWindowFocusBridge = false;
};

export const subscribeMainWindowFocus = (
    listener: MainWindowFocusListener,
): (() => void) => {
    mainWindowFocusListeners.add(listener);
    attachMainWindowFocusBridgeIfNeeded();
    return () => {
        mainWindowFocusListeners.delete(listener);
        detachMainWindowFocusBridgeIfNeeded();
    };
};

const emitMainWindowBlur = () => {
    for (const listener of mainWindowBlurListeners) {
        listener();
    }
};

const attachMainWindowBlurBridgeIfNeeded = () => {
    if (hasAttachedMainWindowBlurBridge) return;
    const electron = globalThis.electron;
    if (!electron) return;
    if (typeof electron.onMainWindowBlur != "function") return;
    electron.onMainWindowBlur(emitMainWindowBlur);
    hasAttachedMainWindowBlurBridge = true;
};

const detachMainWindowBlurBridgeIfNeeded = () => {
    if (!hasAttachedMainWindowBlurBridge || mainWindowBlurListeners.size > 0) {
        return;
    }

    const electron = globalThis.electron;
    if (electron && typeof electron.onMainWindowBlur == "function") {
        electron.onMainWindowBlur(undefined);
    }
    hasAttachedMainWindowBlurBridge = false;
};

export const subscribeMainWindowBlur = (
    listener: MainWindowBlurListener,
): (() => void) => {
    mainWindowBlurListeners.add(listener);
    attachMainWindowBlurBridgeIfNeeded();
    return () => {
        mainWindowBlurListeners.delete(listener);
        detachMainWindowBlurBridgeIfNeeded();
    };
};
