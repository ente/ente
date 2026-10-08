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
    muted: boolean;
    onLoadVideo?: SpacePostAssetURLLoader;
}> = ({ imageUrl, video, isActive, muted, onLoadVideo }) => {
    const root = useRef<HTMLDivElement>(null);
    const player = useRef<
        ReturnType<typeof createSpaceVideoContent> | undefined
    >(undefined);
    const playback = useRef<ReturnType<typeof registerFeedVideo>>(undefined);

    useEffect(() => {
        const container = root.current!;
        let queuedLoad: ReturnType<typeof queueFeedVideoLoad> | undefined;
        const content = createSpaceVideoContent(
            { video },
            onLoadVideo
                ? (asset) => {
                      queuedLoad?.cancel();
                      queuedLoad = queueFeedVideoLoad(container, () =>
                          onLoadVideo(asset),
                      );
                      return queuedLoad.promise;
                  }
                : undefined,
            {
                inline: true,
                onPlay: () => queuedLoad?.prioritize(),
                onPause: () => queuedLoad?.deprioritize(),
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
        void content.preload().catch((error: unknown) => {
            if (!(error instanceof DOMException && error.name == "AbortError"))
                log.warn("Failed to preload feed video", error);
        });
        return () => {
            registration.unregister();
            content.destroy();
            queuedLoad?.cancel();
            content.element.remove();
            player.current = undefined;
            playback.current = undefined;
        };
    }, [onLoadVideo, video]);

    useEffect(() => {
        const element = player.current!.video;
        if (imageUrl) element.poster = imageUrl;
        else element.removeAttribute("poster");
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
