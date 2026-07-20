import React from "react";

type SpacePWAInstallMode =
    | "android-fallback"
    | "ios-chrome"
    | "ios-fallback"
    | "ios-safari";

interface SpacePWAInstallPromptState {
    dismiss: () => void;
    mode: SpacePWAInstallMode | null;
    shouldShow: boolean;
}

const dismissedUntilKey = "space.pwaInstall.dismissedUntil";
const dismissalDurationMs = 14 * 24 * 60 * 60 * 1000;

const hasWindow = () => typeof window != "undefined";

const isIOS = () => {
    if (!hasWindow()) return false;

    const { maxTouchPoints, userAgent } = navigator;
    return (
        /iPad|iPhone|iPod/.test(userAgent) ||
        (userAgent.includes("Macintosh") && maxTouchPoints > 1)
    );
};

const isAndroid = () => hasWindow() && /Android/i.test(navigator.userAgent);

const isIOSSafari = () => {
    if (!isIOS()) return false;

    const { userAgent } = navigator;
    return (
        /Safari/i.test(userAgent) &&
        !/CriOS|FxiOS|EdgiOS|OPiOS|DuckDuckGo/i.test(userAgent)
    );
};

const isIOSChrome = () => isIOS() && /CriOS/i.test(navigator.userAgent);

const isAndroidNativePromptBrowser = () => {
    if (!isAndroid()) return false;

    const { userAgent } = navigator;
    if (/Firefox|OPR\/|Opera/i.test(userAgent)) return false;
    return /Chrome|Chromium|EdgA|SamsungBrowser/i.test(userAgent);
};

const shouldShowAndroidInstructions = () =>
    isAndroid() && !isAndroidNativePromptBrowser();

const isStandalone = () =>
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

export const useSpacePWAInstallPrompt = (): SpacePWAInstallPromptState => {
    const [mode, setMode] = React.useState<SpacePWAInstallMode | null>(null);
    const [dismissed, setDismissed] = React.useState(true);
    const [installed, setInstalled] = React.useState(true);

    React.useEffect(() => {
        if (!hasWindow()) return;

        setDismissed(isDismissed());
        setInstalled(isStandalone());

        if (isIOSChrome()) {
            setMode("ios-chrome");
        } else if (isIOSSafari()) {
            setMode("ios-safari");
        } else if (isIOS()) {
            setMode("ios-fallback");
        } else if (shouldShowAndroidInstructions()) {
            setMode("android-fallback");
        }

        const appInstalled = () => {
            setInstalled(true);
            setMode(null);
        };
        const standaloneChange = () => setInstalled(isStandalone());
        const standaloneQuery = window.matchMedia("(display-mode: standalone)");
        const supportsEventListener =
            typeof standaloneQuery.addEventListener == "function";

        window.addEventListener("appinstalled", appInstalled);
        if (supportsEventListener) {
            standaloneQuery.addEventListener("change", standaloneChange);
        } else {
            // eslint-disable-next-line @typescript-eslint/no-deprecated
            standaloneQuery.addListener(standaloneChange);
        }

        return () => {
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

    return {
        dismiss,
        mode,
        shouldShow: Boolean(mode) && !dismissed && !installed,
    };
};
