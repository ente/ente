import dynamic from "next/dynamic";
import type { FileViewerProps } from "../components/FileViewer";
import type { PublicFeedSidebarProps } from "../components/PublicFeedSidebar";

const loadFileViewer = () => import("../components/FileViewer");
const loadPublicFeedSidebar = () => import("../components/PublicFeedSidebar");

export const LazyFileViewer = dynamic<FileViewerProps>(
    () => loadFileViewer().then(({ FileViewer }) => FileViewer),
    { ssr: false },
);

export const LazyPublicFeedSidebar = dynamic<PublicFeedSidebarProps>(
    () =>
        loadPublicFeedSidebar().then(
            ({ PublicFeedSidebar }) => PublicFeedSidebar,
        ),
    { ssr: false },
);

let fileViewerPreload: Promise<void> | undefined;

const preloadFileViewer = () => {
    if (typeof window === "undefined") {
        return Promise.resolve();
    }

    fileViewerPreload ??= loadFileViewer().then(() => undefined);
    return fileViewerPreload;
};

export const scheduleFileViewerPreload = () => {
    if (typeof window === "undefined") {
        return () => undefined;
    }

    let isCancelled = false;
    let idleCallbackID: number | undefined;

    const warmViewer = () => {
        if (isCancelled) return;
        void preloadFileViewer();
    };

    const requestWarmupOnIdle = () => {
        const requestIdleCallback =
            "requestIdleCallback" in window
                ? window.requestIdleCallback.bind(window)
                : undefined;

        if (requestIdleCallback) {
            idleCallbackID = requestIdleCallback(warmViewer, { timeout: 1500 });
        } else {
            idleCallbackID = window.setTimeout(warmViewer, 0);
        }
    };

    requestWarmupOnIdle();

    return () => {
        isCancelled = true;
        if (idleCallbackID !== undefined) {
            const cancelIdleCallback =
                "cancelIdleCallback" in window
                    ? window.cancelIdleCallback.bind(window)
                    : undefined;

            if (cancelIdleCallback) {
                cancelIdleCallback(idleCallbackID);
            } else {
                window.clearTimeout(idleCallbackID);
            }
        }
    };
};
