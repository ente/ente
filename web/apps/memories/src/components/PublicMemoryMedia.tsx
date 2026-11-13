import { Box, CircularProgress, Typography } from "@mui/material";
import log from "ente-base/log";
import {
    downloadManager,
    type RenderableSourceURLs,
} from "ente-gallery/services/download";
import type { HLSPlaylistData } from "ente-gallery/services/video";
import type { EnteFile } from "ente-media/file";
import "hls-video-element";
import {
    type CSSProperties,
    type RefObject,
    type SyntheticEvent,
    useCallback,
    useEffect,
    useRef,
    useState,
} from "react";
import type { PublicMemoryShareFrameCrop } from "../services/public-memory";
import { computeMediaCropStyle } from "../utils/lane";

const DEFAULT_MEDIA_MAX_WIDTH_CSS = "min(1360px, calc(100vw - 32px))";
const DEFAULT_MEDIA_MAX_HEIGHT_CSS = "calc(100dvh - 184px)";
const ASPECT_RATIO_CHANGE_EPSILON = 0.00001;

const buildMediaStyle = ({
    cropRect,
    cropContainerAspectRatio,
    fillFrame,
    mediaAspectRatio,
    objectFit,
}: {
    cropRect?: PublicMemoryShareFrameCrop;
    cropContainerAspectRatio?: number;
    fillFrame?: boolean;
    mediaAspectRatio?: number;
    objectFit: "contain" | "cover";
}): CSSProperties => {
    const cropStyle = computeMediaCropStyle({
        cropRect,
        mediaAspectRatio,
        containerAspectRatio: cropContainerAspectRatio,
    });

    return {
        display: "block",
        ...(cropStyle ?? {
            width: fillFrame ? "100%" : "auto",
            height: fillFrame ? "100%" : "auto",
            maxWidth: fillFrame ? "100%" : DEFAULT_MEDIA_MAX_WIDTH_CSS,
            maxHeight: fillFrame ? "100%" : DEFAULT_MEDIA_MAX_HEIGHT_CSS,
            objectFit,
        }),
        userSelect: "none",
        pointerEvents: "none",
    };
};

function MediaLoadingOverlay() {
    return (
        <Box
            sx={{
                position: "absolute",
                inset: 0,
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                backgroundColor: "rgba(0, 0, 0, 0.5)",
                zIndex: 2,
            }}
        >
            <CircularProgress sx={{ color: "#08c225" }} size={32} />
        </Box>
    );
}

export interface PhotoImageProps {
    file: EnteFile;
    onFullLoad?: () => void;
    onThumbnailResolved?: () => void;
    enableFullLoad?: boolean;
    fillFrame?: boolean;
    objectFit?: "contain" | "cover";
    thumbnailOnly?: boolean;
    cropRect?: PublicMemoryShareFrameCrop;
    cropContainerAspectRatio?: number;
    mediaAspectRatio?: number;
    onAspectRatio?: (width: number, height: number) => void;
    showLoadingOverlay?: boolean;
}

export function PhotoImage({
    file,
    onFullLoad,
    onThumbnailResolved,
    enableFullLoad = true,
    fillFrame,
    objectFit = "contain",
    thumbnailOnly = false,
    cropRect,
    cropContainerAspectRatio,
    mediaAspectRatio,
    onAspectRatio,
    showLoadingOverlay = true,
}: PhotoImageProps) {
    const [thumbnailURL, setThumbnailURL] = useState<string | undefined>(
        undefined,
    );
    const [fullImageURL, setFullImageURL] = useState<string | undefined>(
        undefined,
    );
    const [isLoading, setIsLoading] = useState(true);
    const imageRef = useRef<HTMLImageElement | null>(null);
    const onFullLoadRef = useRef(onFullLoad);
    const onThumbnailResolvedRef = useRef(onThumbnailResolved);
    const onAspectRatioRef = useRef(onAspectRatio);
    const mediaReadyRef = useRef(false);
    const thumbnailResolvedRef = useRef(false);
    const fullImageLoadTokenRef = useRef<symbol | null>(null);
    const hasNotifiedDisplayReadyRef = useRef(false);
    const hasNotifiedThumbnailResolvedRef = useRef(false);
    const lastReportedAspectRatioRef = useRef<number | undefined>(undefined);

    onFullLoadRef.current = onFullLoad;
    onThumbnailResolvedRef.current = onThumbnailResolved;
    onAspectRatioRef.current = onAspectRatio;

    const signalReady = useCallback(() => {
        mediaReadyRef.current = true;
        if (hasNotifiedDisplayReadyRef.current || !onFullLoadRef.current) {
            return;
        }
        hasNotifiedDisplayReadyRef.current = true;
        onFullLoadRef.current();
    }, []);

    const signalThumbnailResolved = useCallback(() => {
        thumbnailResolvedRef.current = true;
        if (
            hasNotifiedThumbnailResolvedRef.current ||
            !onThumbnailResolvedRef.current
        ) {
            return;
        }

        hasNotifiedThumbnailResolvedRef.current = true;
        onThumbnailResolvedRef.current();
    }, []);

    const reportAspectRatio = useCallback((width: number, height: number) => {
        if (width <= 0 || height <= 0) {
            return;
        }

        const nextAspectRatio = width / height;
        const previousAspectRatio = lastReportedAspectRatioRef.current;
        if (
            typeof previousAspectRatio === "number" &&
            Math.abs(previousAspectRatio - nextAspectRatio) <
                ASPECT_RATIO_CHANGE_EPSILON
        ) {
            return;
        }

        lastReportedAspectRatioRef.current = nextAspectRatio;
        onAspectRatioRef.current?.(width, height);
    }, []);

    useEffect(() => {
        let cancelled = false;
        setIsLoading(true);
        setThumbnailURL(undefined);
        setFullImageURL(undefined);
        mediaReadyRef.current = false;
        thumbnailResolvedRef.current = false;
        hasNotifiedDisplayReadyRef.current = false;
        hasNotifiedThumbnailResolvedRef.current = false;
        lastReportedAspectRatioRef.current = undefined;

        const loadThumbnail = async () => {
            try {
                const nextThumbnailURL =
                    await downloadManager.renderableThumbnailURL(file);
                if (cancelled) {
                    return;
                }

                if (nextThumbnailURL) {
                    setThumbnailURL(nextThumbnailURL);
                } else if (thumbnailOnly) {
                    setIsLoading(false);
                }
            } catch (error) {
                log.error("Failed to load thumbnail", error);
                if (!cancelled && thumbnailOnly) {
                    setIsLoading(false);
                }
            } finally {
                if (!cancelled) {
                    signalThumbnailResolved();
                }
            }
        };

        void loadThumbnail();

        return () => {
            cancelled = true;
        };
    }, [file, signalThumbnailResolved, thumbnailOnly]);

    useEffect(() => {
        if (!onFullLoad) {
            hasNotifiedDisplayReadyRef.current = false;
            return;
        }
        if (mediaReadyRef.current && !hasNotifiedDisplayReadyRef.current) {
            hasNotifiedDisplayReadyRef.current = true;
            onFullLoad();
        }
    }, [onFullLoad]);

    useEffect(() => {
        if (!onThumbnailResolved) {
            hasNotifiedThumbnailResolvedRef.current = false;
            return;
        }
        if (
            thumbnailResolvedRef.current &&
            !hasNotifiedThumbnailResolvedRef.current
        ) {
            hasNotifiedThumbnailResolvedRef.current = true;
            onThumbnailResolved();
        }
    }, [onThumbnailResolved]);

    useEffect(() => {
        if (thumbnailOnly || !enableFullLoad) {
            return;
        }

        const loadToken = Symbol("full-image-load");
        fullImageLoadTokenRef.current = loadToken;

        const isStaleLoad = () => fullImageLoadTokenRef.current !== loadToken;

        const loadFullImage = async () => {
            try {
                const sourceURLs =
                    await downloadManager.renderableSourceURLs(file);
                if (isStaleLoad()) {
                    return;
                }
                if (sourceURLs.type === "video") {
                    signalReady();
                    return;
                }

                let nextFullImageURL: string;
                if (sourceURLs.type === "livePhoto") {
                    nextFullImageURL = await sourceURLs.imageURL();
                    if (isStaleLoad()) {
                        return;
                    }
                } else {
                    nextFullImageURL = sourceURLs.imageURL;
                }

                setFullImageURL(nextFullImageURL);
            } catch (error) {
                log.error("Failed to load full image", error);
                if (!isStaleLoad()) {
                    signalReady();
                }
            }
        };

        void loadFullImage();

        return () => {
            if (fullImageLoadTokenRef.current === loadToken) {
                fullImageLoadTokenRef.current = null;
            }
        };
    }, [enableFullLoad, file, signalReady, thumbnailOnly]);

    useEffect(() => {
        if (thumbnailOnly || !fullImageURL) {
            return;
        }
        const image = imageRef.current;
        if (!image?.complete) {
            return;
        }
        if (image.naturalWidth > 0 && image.naturalHeight > 0) {
            reportAspectRatio(image.naturalWidth, image.naturalHeight);
        }
    }, [fullImageURL, reportAspectRatio, thumbnailOnly]);

    const handleImageLoad = useCallback(
        (event: SyntheticEvent<HTMLImageElement>) => {
            const image = event.currentTarget;
            reportAspectRatio(image.naturalWidth, image.naturalHeight);
            const isFullImageLoad =
                !thumbnailOnly &&
                !!fullImageURL &&
                (image.currentSrc || image.src) === fullImageURL;
            setIsLoading(false);
            if (thumbnailOnly || isFullImageLoad) {
                signalReady();
            }
        },
        [fullImageURL, reportAspectRatio, signalReady, thumbnailOnly],
    );

    const handleImageError = useCallback(
        (event: SyntheticEvent<HTMLImageElement>) => {
            const failedURL =
                event.currentTarget.currentSrc || event.currentTarget.src;
            log.error("Failed to render public memory image", failedURL);
            setIsLoading(false);

            if (!thumbnailOnly && fullImageURL && failedURL === fullImageURL) {
                setFullImageURL(undefined);
            } else if (thumbnailURL && failedURL === thumbnailURL) {
                setThumbnailURL(undefined);
            }

            signalReady();
        },
        [fullImageURL, signalReady, thumbnailOnly, thumbnailURL],
    );

    const displayURL = fullImageURL ?? thumbnailURL;
    const mediaStyle = buildMediaStyle({
        cropRect,
        cropContainerAspectRatio,
        fillFrame,
        mediaAspectRatio,
        objectFit,
    });

    return (
        <Box
            sx={{
                position: "relative",
                display: fillFrame ? "block" : "inline-block",
                width: fillFrame ? "100%" : "auto",
                height: fillFrame ? "100%" : "auto",
                overflow: "hidden",
            }}
        >
            {isLoading && showLoadingOverlay && <MediaLoadingOverlay />}

            {displayURL && (
                <img
                    ref={imageRef}
                    src={displayURL}
                    alt=""
                    draggable={false}
                    onLoad={handleImageLoad}
                    onError={handleImageError}
                    style={mediaStyle}
                />
            )}
        </Box>
    );
}

export interface VideoPlayerProps {
    file: EnteFile;
    onReady?: () => void;
    onThumbnailResolved?: () => void;
    enableFullLoad?: boolean;
    onDuration?: (durationSeconds: number) => void;
    onEnded?: () => void;
    onPlaybackBlocked?: () => void;
    muted?: boolean;
    paused?: boolean;
    mediaRef?: RefObject<HTMLVideoElement | null>;
    fillFrame?: boolean;
    objectFit?: "contain" | "cover";
    cropRect?: PublicMemoryShareFrameCrop;
    cropContainerAspectRatio?: number;
    mediaAspectRatio?: number;
    onAspectRatio?: (width: number, height: number) => void;
    showLoadingOverlay?: boolean;
}

export function VideoPlayer({
    file,
    onReady,
    onThumbnailResolved,
    enableFullLoad = true,
    onDuration,
    onEnded,
    onPlaybackBlocked,
    muted = false,
    paused,
    mediaRef,
    fillFrame,
    objectFit = "contain",
    cropRect,
    cropContainerAspectRatio,
    mediaAspectRatio,
    onAspectRatio,
    showLoadingOverlay = true,
}: VideoPlayerProps) {
    const [hlsData, setHlsData] = useState<HLSPlaylistData | undefined>(
        undefined,
    );
    const [videoURL, setVideoURL] = useState<string | undefined>(undefined);
    const [thumbnailURL, setThumbnailURL] = useState<string | undefined>(
        undefined,
    );
    const [isLoading, setIsLoading] = useState(true);
    const [error, setError] = useState(false);
    const [videoElement, setVideoElement] = useState<HTMLVideoElement | null>(
        null,
    );
    const videoRef = useRef<HTMLVideoElement>(null);
    const onReadyRef = useRef(onReady);
    const onThumbnailResolvedRef = useRef(onThumbnailResolved);
    const onDurationRef = useRef(onDuration);
    const onEndedRef = useRef(onEnded);
    const onPlaybackBlockedRef = useRef(onPlaybackBlocked);
    const pausedRef = useRef(paused);
    const playbackRequestIDRef = useRef(0);
    const hasSignalledReadyRef = useRef(false);
    const thumbnailResolvedRef = useRef(false);
    const hasNotifiedThumbnailResolvedRef = useRef(false);

    onReadyRef.current = onReady;
    onThumbnailResolvedRef.current = onThumbnailResolved;
    onDurationRef.current = onDuration;
    onEndedRef.current = onEnded;
    onPlaybackBlockedRef.current = onPlaybackBlocked;
    pausedRef.current = paused;

    const invalidatePlaybackRequest = useCallback(() => {
        playbackRequestIDRef.current += 1;
    }, []);

    const requestPlayback = useCallback(() => {
        const video = videoRef.current;
        if (!video || pausedRef.current) {
            return;
        }

        const requestID = playbackRequestIDRef.current + 1;
        playbackRequestIDRef.current = requestID;
        const playPromise = video.play();
        void playPromise.catch((error: unknown) => {
            if (
                requestID !== playbackRequestIDRef.current ||
                pausedRef.current ||
                video !== videoRef.current
            ) {
                return;
            }

            log.warn("Failed to start public memory video playback", error);
            video.pause();
            setIsLoading(false);
            onPlaybackBlockedRef.current?.();
        });
    }, []);

    const signalThumbnailResolved = useCallback(() => {
        thumbnailResolvedRef.current = true;
        if (
            hasNotifiedThumbnailResolvedRef.current ||
            !onThumbnailResolvedRef.current
        ) {
            return;
        }

        hasNotifiedThumbnailResolvedRef.current = true;
        onThumbnailResolvedRef.current();
    }, []);

    const setVideoElementRef = useCallback(
        (node: HTMLVideoElement | null) => {
            videoRef.current = node;
            setVideoElement(node);
            if (mediaRef) {
                mediaRef.current = node;
            }
        },
        [mediaRef],
    );

    useEffect(() => {
        let cancelled = false;
        invalidatePlaybackRequest();
        setIsLoading(true);
        setError(false);
        setVideoURL(undefined);
        setHlsData(undefined);
        setThumbnailURL(undefined);
        hasSignalledReadyRef.current = false;
        thumbnailResolvedRef.current = false;
        hasNotifiedThumbnailResolvedRef.current = false;

        const loadThumbnail = async () => {
            try {
                const nextThumbnailURL =
                    await downloadManager.renderableThumbnailURL(file);
                if (cancelled) {
                    return;
                }

                if (nextThumbnailURL) {
                    setThumbnailURL(nextThumbnailURL);
                }
            } catch (error) {
                log.error("Failed to load video thumbnail", error);
            } finally {
                if (!cancelled) {
                    signalThumbnailResolved();
                }
            }
        };

        void loadThumbnail();

        return () => {
            cancelled = true;
        };
    }, [file, invalidatePlaybackRequest, signalThumbnailResolved]);

    useEffect(() => {
        if (!onThumbnailResolved) {
            hasNotifiedThumbnailResolvedRef.current = false;
            return;
        }
        if (
            thumbnailResolvedRef.current &&
            !hasNotifiedThumbnailResolvedRef.current
        ) {
            hasNotifiedThumbnailResolvedRef.current = true;
            onThumbnailResolved();
        }
    }, [onThumbnailResolved]);

    useEffect(() => {
        if (!enableFullLoad) {
            return;
        }

        let cancelled = false;

        const load = async () => {
            try {
                const nextHlsData =
                    await downloadManager.hlsPlaylistDataForPublicMemory(file);
                if (
                    !cancelled &&
                    typeof nextHlsData === "object" &&
                    nextHlsData.playlistURL
                ) {
                    setHlsData(nextHlsData);
                    return;
                }

                const sourceURLs: RenderableSourceURLs =
                    await downloadManager.renderableSourceURLs(file);
                if (!cancelled && sourceURLs.type === "video") {
                    setVideoURL(sourceURLs.videoURL);
                } else if (!cancelled) {
                    setIsLoading(false);
                }
            } catch (error) {
                log.error("Failed to load video", error);
                if (!cancelled) {
                    setError(true);
                    setIsLoading(false);
                }
            }
        };

        void load();

        return () => {
            cancelled = true;
        };
    }, [enableFullLoad, file]);

    useEffect(() => {
        const video = videoRef.current;
        if (!video || (!videoURL && !hlsData)) {
            return;
        }

        if (paused) {
            invalidatePlaybackRequest();
            video.pause();
        } else {
            requestPlayback();
        }
    }, [hlsData, invalidatePlaybackRequest, paused, requestPlayback, videoURL]);

    useEffect(() => {
        const video = videoRef.current;
        if (!video) {
            return;
        }

        video.muted = muted;
    }, [muted, videoElement]);

    const handleLoadedMetadata = useCallback(() => {
        const video = videoRef.current;
        if (video && !Number.isNaN(video.duration) && video.duration > 0) {
            onAspectRatio?.(video.videoWidth, video.videoHeight);
            onDurationRef.current?.(video.duration);
        }
    }, [onAspectRatio]);

    const handleMediaReady = useCallback(() => {
        setIsLoading(false);
        if (!hasSignalledReadyRef.current) {
            hasSignalledReadyRef.current = true;
            onReadyRef.current?.();
        }
        if (!pausedRef.current) {
            requestPlayback();
        }
    }, [requestPlayback]);

    const handleEnded = useCallback(() => {
        onEndedRef.current?.();
    }, []);

    useEffect(() => {
        const video = videoElement;
        if (!video) {
            return;
        }

        const handleError = () => {
            const mediaError = video.error;
            log.error("Public memory video element error", mediaError);
            setError(true);
            setIsLoading(false);
        };

        video.addEventListener("loadedmetadata", handleLoadedMetadata);
        video.addEventListener("loadeddata", handleMediaReady);
        video.addEventListener("canplay", handleMediaReady);
        video.addEventListener("playing", handleMediaReady);
        video.addEventListener("ended", handleEnded);
        video.addEventListener("error", handleError);

        if (video.readyState >= HTMLMediaElement.HAVE_CURRENT_DATA) {
            handleMediaReady();
        }

        return () => {
            video.removeEventListener("loadedmetadata", handleLoadedMetadata);
            video.removeEventListener("loadeddata", handleMediaReady);
            video.removeEventListener("canplay", handleMediaReady);
            video.removeEventListener("playing", handleMediaReady);
            video.removeEventListener("ended", handleEnded);
            video.removeEventListener("error", handleError);
        };
    }, [handleEnded, handleLoadedMetadata, handleMediaReady, videoElement]);

    const mediaStyle = buildMediaStyle({
        cropRect,
        cropContainerAspectRatio,
        fillFrame,
        mediaAspectRatio,
        objectFit,
    });

    if (error) {
        return (
            <Box
                sx={{
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "center",
                    width: "100%",
                    height: "100%",
                }}
            >
                <Typography sx={{ color: "rgba(255,255,255,0.7)" }}>
                    Unable to play video
                </Typography>
            </Box>
        );
    }

    return (
        <Box
            sx={{
                position: "relative",
                display: fillFrame ? "block" : "inline-block",
                width: fillFrame ? "100%" : "auto",
                height: fillFrame ? "100%" : "auto",
                overflow: "hidden",
            }}
        >
            {isLoading && showLoadingOverlay && <MediaLoadingOverlay />}

            {hlsData && (
                <hls-video
                    ref={setVideoElementRef}
                    src={hlsData.playlistURL}
                    poster={thumbnailURL}
                    playsInline
                    style={mediaStyle}
                />
            )}

            {!hlsData && videoURL && (
                <video
                    ref={setVideoElementRef}
                    src={videoURL}
                    poster={thumbnailURL}
                    playsInline
                    style={mediaStyle}
                />
            )}

            {!videoURL && !hlsData && thumbnailURL && (
                <img src={thumbnailURL} alt="" style={mediaStyle} />
            )}
        </Box>
    );
}
