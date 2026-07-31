import React from "react";

export type SpacePWAInstallMode =
    | "android-fallback"
    | "ios-chrome"
    | "ios-fallback"
    | "ios-safari"
    | "native";

interface BeforeInstallPromptEvent extends Event {
    prompt: () => Promise<void>;
    userChoice: Promise<{ outcome: "accepted" | "dismissed" }>;
}

interface SpacePWAInstallPromptState {
    canInstall: boolean;
    dismiss: () => void;
    install: () => Promise<void>;
    mode: SpacePWAInstallMode | null;
    shouldShow: boolean;
}

const dismissedUntilKey = "space.pwaInstall.dismissedUntil";
const dismissalDurationMs = 14 * 24 * 60 * 60 * 1000;
const promptListeners = new Set<() => void>();
let deferredInstallPrompt: BeforeInstallPromptEvent | undefined;

const hasWindow = () => typeof window != "undefined";

export const captureSpacePWAInstallPrompt = () => {
    if (!hasWindow()) return;
    const beforeInstallPrompt = (event: Event) => {
        event.preventDefault();
        deferredInstallPrompt = event as BeforeInstallPromptEvent;
        promptListeners.forEach((listener) => listener());
    };
    const appInstalled = () => {
        deferredInstallPrompt = undefined;
        promptListeners.forEach((listener) => listener());
    };
    window.addEventListener("beforeinstallprompt", beforeInstallPrompt);
    window.addEventListener("appinstalled", appInstalled);
    return () => {
        window.removeEventListener("beforeinstallprompt", beforeInstallPrompt);
        window.removeEventListener("appinstalled", appInstalled);
    };
};

export const isSpaceIOS = () => {
    if (!hasWindow()) return false;
    const { maxTouchPoints, userAgent } = navigator;
    return (
        /iPad|iPhone|iPod/.test(userAgent) ||
        (userAgent.includes("Macintosh") && maxTouchPoints > 1)
    );
};

const isAndroid = () => hasWindow() && /Android/i.test(navigator.userAgent);

const isIOSSafari = () => {
    if (!isSpaceIOS()) return false;
    const { userAgent } = navigator;
    return (
        /Safari/i.test(userAgent) &&
        !/CriOS|FxiOS|EdgiOS|OPiOS|DuckDuckGo/i.test(userAgent)
    );
};

const isIOSChrome = () => isSpaceIOS() && /CriOS/i.test(navigator.userAgent);

export const isSpaceStandalone = () =>
    hasWindow() &&
    (window.matchMedia("(display-mode: standalone)").matches ||
        ("standalone" in navigator &&
            Boolean((navigator as { standalone?: boolean }).standalone)));

const storageGet = (key: string) => {
    try {
        return window.localStorage.getItem(key);
    } catch {
        return null;
    }
};

const storageSet = (key: string, value: string) => {
    try {
        window.localStorage.setItem(key, value);
    } catch {
        return;
    }
};

const storageRemove = (key: string) => {
    try {
        window.localStorage.removeItem(key);
    } catch {
        return;
    }
};

const isDismissed = () => {
    if (!hasWindow()) return true;
    const dismissedUntil = Number(storageGet(dismissedUntilKey));
    if (!Number.isFinite(dismissedUntil) || dismissedUntil <= 0) return false;
    if (dismissedUntil > Date.now()) return true;
    storageRemove(dismissedUntilKey);
    return false;
};

const currentMode = (): SpacePWAInstallMode | null => {
    if (isIOSChrome()) return "ios-chrome";
    if (isIOSSafari()) return "ios-safari";
    if (isSpaceIOS()) return "ios-fallback";
    if (!isAndroid()) return null;
    if (deferredInstallPrompt) return "native";
    return "android-fallback";
};

export const useSpacePWAInstallPrompt = (): SpacePWAInstallPromptState => {
    const [mode, setMode] = React.useState<SpacePWAInstallMode | null>(null);
    const [dismissed, setDismissed] = React.useState(true);
    const [installed, setInstalled] = React.useState(true);

    React.useEffect(() => {
        if (!hasWindow()) return;
        setDismissed(isDismissed());
        setInstalled(isSpaceStandalone());
        setMode(currentMode());

        const promptChanged = () => setMode(currentMode());
        const appInstalled = () => {
            setInstalled(true);
            setMode(null);
        };
        const standaloneChange = () => setInstalled(isSpaceStandalone());
        const standaloneQuery = window.matchMedia("(display-mode: standalone)");
        const supportsEventListener =
            typeof standaloneQuery.addEventListener == "function";

        promptListeners.add(promptChanged);
        window.addEventListener("appinstalled", appInstalled);
        if (supportsEventListener) {
            standaloneQuery.addEventListener("change", standaloneChange);
        } else {
            // eslint-disable-next-line @typescript-eslint/no-deprecated
            standaloneQuery.addListener(standaloneChange);
        }

        return () => {
            promptListeners.delete(promptChanged);
            window.removeEventListener("appinstalled", appInstalled);
            if (supportsEventListener) {
                standaloneQuery.removeEventListener("change", standaloneChange);
            } else {
                // eslint-disable-next-line @typescript-eslint/no-deprecated
                standaloneQuery.removeListener(standaloneChange);
            }
        };
    }, []);

    const dismiss = React.useCallback(() => {
        storageSet(dismissedUntilKey, String(Date.now() + dismissalDurationMs));
        setDismissed(true);
    }, []);

    const install = React.useCallback(async () => {
        const prompt = deferredInstallPrompt;
        if (!prompt) return;
        await prompt.prompt();
        const choice = await prompt.userChoice;
        deferredInstallPrompt = undefined;
        promptListeners.forEach((listener) => listener());
        if (choice.outcome == "accepted") {
            setInstalled(true);
        } else {
            dismiss();
        }
    }, [dismiss]);

    const canInstall = Boolean(mode) && !installed;
    return {
        canInstall,
        dismiss,
        install,
        mode,
        shouldShow: canInstall && !dismissed,
    };
};
