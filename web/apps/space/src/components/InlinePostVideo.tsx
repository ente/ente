import { Box } from "@mui/material";
import { createSpaceVideoContent } from "components/PostVideoContent";
import { registerFeedVideo } from "components/feed-video-playback";
import { queueFeedVideoLoad } from "components/feed-video-preloading";
import log from "ente-base/log";
import React, { useEffect, useRef } from "react";
import type { SpacePostAssetURLLoader, SpacePostVideo } from "services/space";

export const SpaceInlinePostVideo: React.FC<{
    imageUrl?: string;
    video: SpacePostVideo;
    isActive: boolean;
    shouldPreload: boolean;
    muted: boolean;
    onLoadVideo?: SpacePostAssetURLLoader;
}> = ({ imageUrl, video, isActive, shouldPreload, muted, onLoadVideo }) => {
    const root = useRef<HTMLDivElement>(null);
    const player = useRef<
        ReturnType<typeof createSpaceVideoContent> | undefined
    >(undefined);
    const playback = useRef<ReturnType<typeof registerFeedVideo>>(undefined);
    const queuedLoad = useRef<ReturnType<typeof queueFeedVideoLoad>>(undefined);

    useEffect(() => {
        const container = root.current!;
        const content = createSpaceVideoContent(
            { video },
            onLoadVideo
                ? (asset) => {
                      queuedLoad.current?.cancel();
                      queuedLoad.current = queueFeedVideoLoad(
                          container,
                          (signal) => onLoadVideo(asset, signal),
                      );
                      return queuedLoad.current.promise;
                  }
                : undefined,
            {
                inline: true,
                onPlay: () => queuedLoad.current?.prioritize(),
                onPause: () => queuedLoad.current?.deprioritize(),
                onTogglePlayback: (play) => {
                    if (play) registration.play();
                    else registration.pause();
                },
            },
        );
        const registration = registerFeedVideo(container, content);
        playback.current = registration;
        player.current = content;
        container.append(content.element);
        return () => {
            registration.unregister();
            content.destroy();
            queuedLoad.current?.cancel();
            content.element.remove();
            player.current = undefined;
            playback.current = undefined;
            queuedLoad.current = undefined;
        };
    }, [onLoadVideo, video]);

    useEffect(() => {
        queuedLoad.current?.setPreloading(shouldPreload);
        if (shouldPreload)
            void player.current!.preload().catch((error: unknown) => {
                if (!(
                    error instanceof DOMException && error.name == "AbortError"
                ))
                    log.warn("Failed to preload feed video", error);
            });
    }, [shouldPreload, onLoadVideo, video]);

    useEffect(() => {
        const element = player.current!.video;
        const updatePoster = () => {
            if (imageUrl && element.readyState < element.HAVE_CURRENT_DATA)
                element.poster = imageUrl;
            else element.removeAttribute("poster");
        };
        updatePoster();
        element.addEventListener("loadeddata", updatePoster);
        element.addEventListener("emptied", updatePoster);
        return () => {
            element.removeEventListener("loadeddata", updatePoster);
            element.removeEventListener("emptied", updatePoster);
        };
    }, [imageUrl, onLoadVideo, video]);

    useEffect(() => {
        const content = player.current!;
        content.video.tabIndex = isActive ? 0 : -1;
        content.element.querySelector("button")!.tabIndex = isActive ? 0 : -1;
        playback.current!.setActive(isActive);
    }, [isActive, onLoadVideo, video]);

    useEffect(() => {
        player.current!.video.muted = muted;
    }, [muted, onLoadVideo, video]);

    return (
        <Box ref={root} sx={{ position: "absolute", inset: 0, zIndex: 1 }} />
    );
};
