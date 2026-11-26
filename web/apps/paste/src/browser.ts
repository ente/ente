export const waitUntilVisible = () =>
    new Promise<void>((resolve) => {
        if (document.visibilityState === "visible") {
            resolve();
            return;
        }

        const onVisible = () => {
            if (document.visibilityState !== "visible") return;
            document.removeEventListener("visibilitychange", onVisible);
            resolve();
        };

        document.addEventListener("visibilitychange", onVisible);
    });

export const copyTextToClipboard = async (value: string) => {
    await navigator.clipboard.writeText(value);
};

export const shareUrlOrCopy = async (url: string) => {
    const nav = navigator as Navigator & {
        share?: (data?: ShareData) => Promise<void>;
    };

    if (typeof nav.share !== "function") {
        await copyTextToClipboard(url);
        return;
    }

    try {
        await nav.share({ url });
    } catch (error) {
        if (error instanceof DOMException && error.name === "AbortError") {
            return;
        }
        await copyTextToClipboard(url);
    }
};
