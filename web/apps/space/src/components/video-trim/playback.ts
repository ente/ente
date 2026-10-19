import { logToDisk } from "ente-base/log-web";

export const createVideoTrimPlayback = (
    video: HTMLVideoElement,
    getRange: () => { start: number; end: number },
    onError: () => void,
) => {
    let pendingSeek: number | undefined;
    let frame: number | undefined;
    let restartOnPlay = true;
    let playRequested = false;
    let generation = 0;
    let loadingTimer: ReturnType<typeof setTimeout> | undefined;

    const clearLoadingTimer = () => {
        clearTimeout(loadingTimer);
        loadingTimer = undefined;
    };

    const cancelFrame = () => {
        if (frame != undefined) cancelAnimationFrame(frame);
        frame = undefined;
    };

    const pause = () => {
        generation++;
        playRequested = false;
        clearLoadingTimer();
        video.pause();
        cancelFrame();
    };

    const applySeek = () => {
        if (pendingSeek == undefined || video.seeking || video.readyState < 1)
            return;
        const time = pendingSeek;
        pendingSeek = undefined;
        if (Math.abs(video.currentTime - time) >= 0.002)
            video.currentTime = time;
    };

    const seek = (time: number) => {
        pause();
        restartOnPlay = true;
        pendingSeek = time;
        applySeek();
    };

    const checkRange = () => {
        if (video.paused || video.seeking) return;
        const { start, end } = getRange();
        if (video.currentTime >= end) seek(start);
        else if (video.currentTime < start) video.currentTime = start;
    };

    const checkFrame = () => {
        frame = undefined;
        checkRange();
        if (!video.paused) frame = requestAnimationFrame(checkFrame);
    };

    const onPlay = () => {
        if (!playRequested) {
            video.pause();
            return;
        }
        cancelFrame();
        checkFrame();
    };

    const onPause = () => {
        if (!video.paused) return;
        generation++;
        playRequested = false;
        clearLoadingTimer();
        cancelFrame();
    };

    const onEnded = () => seek(getRange().start);

    const failed = () => {
        logToDisk(
            `[error] Space video editor playback failed code=${video.error?.code ?? 0} readyState=${video.readyState} networkState=${video.networkState}`,
        );
        pause();
        onError();
    };
    const waiting = () => {
        if (playRequested) loadingTimer ??= setTimeout(failed, 30_000);
    };

    const toggle = () => {
        if (playRequested || !video.paused) {
            pause();
            return;
        }
        const { start, end } = getRange();
        const time =
            restartOnPlay ||
            video.currentTime < start ||
            video.currentTime >= end
                ? start
                : video.currentTime;
        restartOnPlay = false;
        pendingSeek = undefined;
        if (video.readyState < 1) pendingSeek = time;
        else if (Math.abs(video.currentTime - time) >= 0.002)
            video.currentTime = time;
        const current = ++generation;
        playRequested = true;
        waiting();
        void video.play().catch(() => {
            if (generation != current) return;
            failed();
        });
    };

    video.addEventListener("play", onPlay);
    video.addEventListener("pause", onPause);
    video.addEventListener("ended", onEnded);
    video.addEventListener("timeupdate", checkRange);
    video.addEventListener("seeked", applySeek);
    video.addEventListener("loadedmetadata", applySeek);
    video.addEventListener("playing", clearLoadingTimer);
    video.addEventListener("waiting", waiting);
    video.addEventListener("error", failed);

    return {
        toggle,
        seek,
        dispose: () => {
            pause();
            video.removeEventListener("play", onPlay);
            video.removeEventListener("pause", onPause);
            video.removeEventListener("ended", onEnded);
            video.removeEventListener("timeupdate", checkRange);
            video.removeEventListener("seeked", applySeek);
            video.removeEventListener("loadedmetadata", applySeek);
            video.removeEventListener("playing", clearLoadingTimer);
            video.removeEventListener("waiting", waiting);
            video.removeEventListener("error", failed);
        },
    };
};
