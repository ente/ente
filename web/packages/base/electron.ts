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

// Electron exposes one callback per event; multiplex local subscribers here.
// `attach`/`detach` get the injected `electron` bridge and are expected to
// guard themselves against a method being absent (an older desktop build's
// preload script might not have it yet).
const createMainWindowEventBridge = <A extends unknown[]>(
    attach: (electron: Electron, emit: (...args: A) => void) => void,
    detach: (electron: Electron) => void,
) => {
    type Listener = (...args: A) => void;

    const listeners = new Set<Listener>();
    let hasAttached = false;

    const emit = (...args: A) => {
        for (const listener of listeners) listener(...args);
    };

    const attachIfNeeded = () => {
        if (hasAttached) return;
        const electron = globalThis.electron;
        if (!electron) return;
        attach(electron, emit);
        hasAttached = true;
    };

    const detachIfNeeded = () => {
        if (!hasAttached || listeners.size > 0) return;
        const electron = globalThis.electron;
        if (electron) detach(electron);
        hasAttached = false;
    };

    return (listener: Listener): (() => void) => {
        listeners.add(listener);
        attachIfNeeded();
        return () => {
            listeners.delete(listener);
            detachIfNeeded();
        };
    };
};

export const subscribeMainWindowFocus = createMainWindowEventBridge<[]>(
    (electron, emit) => electron.onMainWindowFocus(emit),
    (electron) => electron.onMainWindowFocus(undefined),
);

export const subscribeMainWindowBlur = createMainWindowEventBridge<[]>(
    (electron, emit) => {
        if (typeof electron.onMainWindowBlur != "function") return;
        electron.onMainWindowBlur(emit);
    },
    (electron) => {
        if (typeof electron.onMainWindowBlur == "function") {
            electron.onMainWindowBlur(undefined);
        }
    },
);

// Bridges the OS-level fullscreen toggle (green traffic light button, or the
// Cmd+Ctrl+F menu shortcut) back into the renderer. That toggle resizes the
// window directly in the main process without going through the Fullscreen
// API, so `document.fullscreenElement` never reflects it on its own.
export const subscribeMainWindowFullscreenChange = createMainWindowEventBridge<
    [isFullscreen: boolean]
>(
    (electron, emit) => {
        if (typeof electron.onMainWindowFullscreenChange != "function") {
            return;
        }
        electron.onMainWindowFullscreenChange(emit);
    },
    (electron) => {
        if (typeof electron.onMainWindowFullscreenChange == "function") {
            electron.onMainWindowFullscreenChange(undefined);
        }
    },
);
