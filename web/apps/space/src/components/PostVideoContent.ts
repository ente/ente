import type { SpaceViewerPhoto } from "components/FileViewer";
import { logToDisk } from "ente-base/log-web";
import { SpaceMediaRateLimitError } from "services/media-load";
import type { SpacePostAssetURLLoader } from "services/space";

export const createSpaceVideoContent = (
    item: Pick<SpaceViewerPhoto, "video"> & { imageUrl?: string },
    load?: SpacePostAssetURLLoader,
    {
        inline = false,
        onPlay,
        onPause,
        onTogglePlayback,
    }: {
        inline?: boolean;
        onPlay?: () => Promise<void> | void;
        onPause?: () => void;
        onTogglePlayback?: (play: boolean) => void;
    } = {},
) => {
    const media = item.video!;
    const element = document.createElement("div");
    element.className = inline
        ? "space-video-content"
        : "pswp__content space-video-content";
    Object.assign(element.style, {
        position: "relative",
        width: "100%",
        height: "100%",
    });
    const video = document.createElement("video");
    video.playsInline = true;
    video.preload = "none";
    if (item.imageUrl) video.poster = item.imageUrl;
    video.muted = inline || (media.muted ?? false);
    video.loop = inline;
    video.tabIndex = 0;
    video.setAttribute("role", "button");
    video.setAttribute("aria-label", "Play video");
    Object.assign(video.style, {
        width: "100%",
        height: "100%",
        objectFit: inline ? "cover" : "contain",
        cursor: "pointer",
    });
    const button = document.createElement("button");
    button.type = "button";
    button.className = "space-video-control";
    button.innerHTML =
        '<svg width="24" height="24" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true" style="display: block"><path d="M6 3v18l15-9z"/></svg>';
    button.setAttribute("aria-label", "Play video");
    button.setAttribute("aria-hidden", "true");
    const controlStyle = {
        position: "absolute",
        top: "50%",
        left: "50%",
        transform: "translate(-50%, -50%)",
        border: "0",
        borderRadius: "50%",
        background: "rgba(0, 0, 0, 0.45)",
        color: "#FFFFFF",
        width: "44px",
        height: "44px",
        padding: "10px",
        boxSizing: "border-box",
    };
    Object.assign(button.style, { ...controlStyle, cursor: "pointer" });
    const loading = document.createElement("span");
    loading.className = "space-video-control";
    loading.setAttribute("aria-hidden", "true");
    loading.setAttribute("role", "status");
    loading.setAttribute("aria-label", "Loading video");
    loading.innerHTML = '<span class="space-video-spinner"></span>';
    Object.assign(loading.style, { ...controlStyle, pointerEvents: "none" });
    const errorMessage = document.createElement("div");
    errorMessage.hidden = true;
    errorMessage.setAttribute("role", "status");
    Object.assign(errorMessage.style, {
        position: "absolute",
        top: "50%",
        left: "50%",
        transform: "translate(-50%, -50%)",
        width: "max-content",
        maxWidth: "calc(100% - 32px)",
        color: "#D0D0D0",
        fontSize: "13px",
        fontWeight: "500",
        fontFamily: '"Inter Variable", Inter, sans-serif',
        lineHeight: "18px",
        textAlign: "center",
        textWrap: "balance",
        pointerEvents: "none",
    });
    const errorTitle = document.createElement("div");
    const supportMessage = document.createElement("div");
    supportMessage.textContent = "Please contact support.";
    for (const pill of [errorTitle, supportMessage]) {
        Object.assign(pill.style, {
            background: "rgba(28, 28, 30, 0.88)",
            borderRadius: "999px",
            boxSizing: "border-box",
            marginInline: "auto",
            maxWidth: "100%",
            padding: "6px 16px",
            width: "fit-content",
        });
    }
    supportMessage.style.marginTop = "2px";
    errorMessage.append(errorTitle, supportMessage);
    element.append(video, button, loading, errorMessage);
    let generation = 0;
    let sourceGeneration = 0;
    let pendingLoad: Promise<void> | undefined;
    let ownedURL: string | undefined;
    let disposed = false;
    let active = false;
    let autoplayBlocked = false;
    let failure: "error" | "rate-limit" | undefined;
    let retryTimer: ReturnType<typeof setTimeout> | undefined;
    let loadingTimer: ReturnType<typeof setTimeout> | undefined;
    let playbackTimeout: ReturnType<typeof setTimeout> | undefined;
    const hideLoading = () => {
        clearTimeout(loadingTimer);
        loadingTimer = undefined;
        clearTimeout(playbackTimeout);
        playbackTimeout = undefined;
        loading.setAttribute("aria-hidden", "true");
        element.removeAttribute("aria-busy");
    };
    const showLoading = (startTimeout = true) => {
        if (startTimeout)
            playbackTimeout ??= setTimeout(
                () => failPlayback("timeout"),
                30_000,
            );
        if (document.activeElement == button)
            video.focus({ preventScroll: true });
        button.setAttribute("aria-hidden", "true");
        element.setAttribute("aria-busy", "true");
        if (
            loadingTimer == undefined &&
            loading.getAttribute("aria-hidden") == "true"
        )
            loadingTimer = setTimeout(() => {
                loadingTimer = undefined;
                loading.setAttribute("aria-hidden", "false");
                button.setAttribute("aria-hidden", "true");
            }, 180);
    };
    const showPlayButton = () => {
        hideLoading();
        const blocked = Boolean(failure);
        const label = blocked ? "Video unavailable" : "Play video";
        button.setAttribute("aria-hidden", String(!active || blocked));
        button.disabled = blocked;
        button.setAttribute("aria-label", label);
        video.setAttribute("aria-label", label);
        video.setAttribute("aria-disabled", String(blocked));
        video.style.cursor = blocked ? "default" : "pointer";
        errorMessage.hidden = !active || !failure;
    };
    const showPlaying = () => {
        hideLoading();
        failure = undefined;
        errorMessage.hidden = true;
        button.disabled = false;
        button.setAttribute("aria-hidden", "true");
        video.setAttribute("aria-label", "Pause video");
    };
    const pause = () => {
        generation++;
        onPause?.();
        video.pause();
        showPlayButton();
    };
    const reset = () => {
        sourceGeneration++;
        pendingLoad = undefined;
        pause();
        video.removeAttribute("src");
        video.load();
    };
    const failPlayback = (
        reason: "timeout" | "media" | "play",
        error?: unknown,
    ) => {
        logToDisk(
            `[error] Space video playback failed reason=${reason} errorName=${error instanceof Error ? error.name : "none"} rateLimited=${error instanceof SpaceMediaRateLimitError} code=${video.error?.code ?? 0} readyState=${video.readyState} networkState=${video.networkState}`,
        );
        failure =
            error instanceof SpaceMediaRateLimitError ? "rate-limit" : "error";
        errorTitle.textContent =
            failure == "rate-limit"
                ? "Couldn't load video. Please try again later."
                : "Couldn't play video.";
        supportMessage.hidden = failure == "rate-limit";
        clearTimeout(retryTimer);
        if (error instanceof SpaceMediaRateLimitError)
            retryTimer = setTimeout(
                () => {
                    failure = undefined;
                    showPlayButton();
                },
                Math.max(0, error.retryAt - Date.now()),
            );
        reset();
    };
    const clear = () => {
        active = false;
        errorMessage.hidden = true;
        reset();
        if (ownedURL) URL.revokeObjectURL(ownedURL);
        ownedURL = undefined;
    };
    const visibility = () => {
        if (document.hidden) pause();
    };
    document.addEventListener("visibilitychange", visibility);
    const preload = () => {
        if (disposed || failure || video.getAttribute("src"))
            return Promise.resolve();
        if (pendingLoad) return pendingLoad;
        const current = sourceGeneration;
        pendingLoad = (async () => {
            let url = media.url ?? ownedURL;
            if (!url) {
                if (!media.asset || !load) throw new Error("Video unavailable");
                url = await load(media.asset);
                if (sourceGeneration != current) {
                    URL.revokeObjectURL(url);
                    return;
                }
                ownedURL = url;
            }
            video.preload = "auto";
            video.src = url;
        })().finally(() => {
            if (sourceGeneration == current) pendingLoad = undefined;
        });
        return pendingLoad;
    };
    const play = (userInitiated = false) => {
        if (disposed || !video.paused) return;
        active = true;
        if (failure || (!userInitiated && autoplayBlocked)) {
            showPlayButton();
            return;
        }
        if (button.disabled) return;
        autoplayBlocked = false;
        errorMessage.hidden = true;
        const current = ++generation;
        showLoading(false);
        button.disabled = true;
        void (async () => {
            await Promise.all([
                preload(),
                Promise.resolve(onPlay?.()).then(() => {
                    if (generation == current) showLoading();
                }),
            ]);
            if (generation != current) return;
            if (
                video.ended ||
                (media.end != undefined && video.currentTime >= media.end)
            ) {
                video.currentTime = media.start ?? 0;
            }
            await video.play();
            if (generation == current) showPlaying();
        })().catch((error: unknown) => {
            if (disposed || generation != current) return;
            if (
                error instanceof DOMException &&
                error.name == "NotAllowedError"
            ) {
                autoplayBlocked = true;
                showPlayButton();
            } else {
                failPlayback("play", error);
            }
        });
    };
    const togglePlayback = () => {
        if (button.disabled) return;
        if (onTogglePlayback) onTogglePlayback(video.paused);
        else if (video.paused) play(true);
        else pause();
    };
    button.onclick = togglePlayback;
    let pointerStart = { x: 0, y: 0 };
    video.onpointerdown = (event) => {
        pointerStart = { x: event.clientX, y: event.clientY };
    };
    video.onclick = (event) => {
        if (
            event.detail == 0 ||
            Math.hypot(
                event.clientX - pointerStart.x,
                event.clientY - pointerStart.y,
            ) < 8
        )
            togglePlayback();
    };
    video.onkeydown = (event) => {
        if (event.key == " " || event.key == "Enter") {
            event.preventDefault();
            event.stopPropagation();
            togglePlayback();
        }
    };
    video.onpause = showPlayButton;
    video.onended = reset;
    video.onwaiting = () => {
        if (!video.paused) showLoading();
    };
    video.onplaying = showPlaying;
    video.onerror = () => {
        if (active) failPlayback("media");
        else reset();
    };
    video.onloadedmetadata = () => {
        if (media.start) video.currentTime = media.start;
    };
    video.ontimeupdate = () => {
        if (media.end != undefined && video.currentTime >= media.end) {
            if (inline) video.currentTime = media.start ?? 0;
            else reset();
        }
    };
    element.addEventListener("pointerdown", (event) => {
        if (!inline && button.contains(event.target as Node))
            event.stopPropagation();
    });
    return {
        element,
        video,
        preload,
        play,
        pause,
        deactivate: () => {
            if (inline) {
                active = false;
                pause();
            } else clear();
        },
        destroy: () => {
            disposed = true;
            clearTimeout(retryTimer);
            clear();
            document.removeEventListener("visibilitychange", visibility);
        },
    };
};
