import CloseIcon from "@mui/icons-material/Close";
import NavigateBeforeIcon from "@mui/icons-material/NavigateBefore";
import NavigateNextIcon from "@mui/icons-material/NavigateNext";
import PauseIcon from "@mui/icons-material/Pause";
import PlayArrowIcon from "@mui/icons-material/PlayArrow";
import SettingsIcon from "@mui/icons-material/Settings";
import {
    Box,
    CircularProgress,
    Dialog,
    IconButton,
    Stack,
    Typography,
} from "@mui/material";
import { CenteredFill } from "ente-base/components/containers";
import { useModalVisibility } from "ente-base/components/utils/modal";
import log from "ente-base/log";
import { downloadManager } from "ente-gallery/services/download";
import type { EnteFile } from "ente-media/file";
import { fileFileName } from "ente-media/file-metadata";
import { usePhotosAppContext } from "ente-new/photos/types/context";
import { shuffled } from "ente-utils/array";
import { t } from "i18next";
import {
    useCallback,
    useEffect,
    useRef,
    useState,
    type KeyboardEvent,
    type MouseEvent,
} from "react";
import {
    savedSlideshowSettings,
    saveSlideshowSettings,
    scheduleSlideshowAdvance,
    slideshowIndex,
    slideshowPrefetchFiles,
    type SlideshowSettings,
} from "./album-slideshow";
import { AlbumSlideshowSettings } from "./AlbumSlideshowSettings";

interface AlbumSlideshowProps {
    files: EnteFile[];
    title: string;
    onClose: () => void;
}

export function AlbumSlideshow({ files, title, onClose }: AlbumSlideshowProps) {
    const [settings, setSettings] = useState(savedSlideshowSettings);
    const [orderedFiles, setOrderedFiles] = useState(() =>
        settings.randomOrder ? shuffled(files) : files,
    );
    const settingsModal = useModalVisibility();
    const [slide, setSlide] = useState({ index: 0, ready: false });
    const [playing, setPlaying] = useState(true);
    const [visible, setVisible] = useState(() => !document.hidden);
    const [controlsVisible, setControlsVisible] = useState(true);
    const controlsHideTimer = useRef<ReturnType<typeof setTimeout>>(undefined);
    const prefetchDirection = useRef(1);
    const { setIsFileViewerOpen } = usePhotosAppContext();
    const current = orderedFiles[slide.index]!;

    const showControls = useCallback(() => {
        setControlsVisible(true);
        clearTimeout(controlsHideTimer.current);
        if (playing && visible && !settingsModal.props.open) {
            controlsHideTimer.current = setTimeout(
                () => setControlsVisible(false),
                2000,
            );
        }
    }, [playing, visible, settingsModal.props.open]);

    useEffect(() => {
        showControls();
        return () => clearTimeout(controlsHideTimer.current);
    }, [showControls]);

    const navigate = useCallback(
        (offset: number) => {
            prefetchDirection.current = offset;
            setSlide((previous) => {
                const index = slideshowIndex(
                    previous.index,
                    offset,
                    files.length,
                );
                return index === previous.index
                    ? previous
                    : { index, ready: false };
            });
        },
        [files.length],
    );

    const markReady = useCallback(
        (id: number) => {
            setSlide((previous) =>
                orderedFiles[previous.index]?.id === id && !previous.ready
                    ? { ...previous, ready: true }
                    : previous,
            );
        },
        [orderedFiles],
    );

    useEffect(
        () =>
            scheduleSlideshowAdvance(
                {
                    enabled: playing && visible && !settingsModal.props.open,
                    ready: slide.ready,
                    count: files.length,
                    durationSeconds: settings.durationSeconds,
                },
                () => navigate(1),
            ),
        [
            playing,
            visible,
            settingsModal.props.open,
            settings.durationSeconds,
            slide.ready,
            files.length,
            current.id,
            navigate,
        ],
    );

    useEffect(() => {
        for (const file of slideshowPrefetchFiles(
            orderedFiles,
            slide.index,
            prefetchDirection.current,
        )) {
            void downloadManager
                .renderableThumbnailURL(file)
                .then(() => downloadManager.renderableSourceURLs(file))
                .catch(() => undefined);
        }
    }, [orderedFiles, slide.index]);

    useEffect(() => {
        const changed = () => setVisible(!document.hidden);
        document.addEventListener("visibilitychange", changed);
        return () => document.removeEventListener("visibilitychange", changed);
    }, []);

    useEffect(() => {
        setIsFileViewerOpen?.(true);
        return () => setIsFileViewerOpen?.(false);
    }, [setIsFileViewerOpen]);

    const handleKeyDown = (event: KeyboardEvent) => {
        if (settingsModal.props.open) return;
        showControls();
        if (
            (event.target as HTMLElement).closest("button") &&
            event.key === " "
        )
            return;
        switch (event.key) {
            case "ArrowLeft":
                navigate(-1);
                break;
            case "ArrowRight":
                navigate(1);
                break;
            case " ":
                if (files.length > 1) setPlaying((value) => !value);
                break;
            default:
                return;
        }
        event.preventDefault();
        event.stopPropagation();
    };

    const handlePhotoClick = (event: MouseEvent<HTMLElement>) => {
        const bounds = event.currentTarget.getBoundingClientRect();
        const x = (event.clientX - bounds.left) / bounds.width;
        if (x < 0.25) navigate(-1);
        else if (x > 0.75) navigate(1);
    };

    const handleSettingsChange = (next: SlideshowSettings) => {
        if (next.randomOrder !== settings.randomOrder) {
            const reordered = next.randomOrder ? shuffled(files) : files;
            setOrderedFiles(reordered);
            setSlide((previous) => ({
                ...previous,
                index: reordered.findIndex((file) => file.id === current.id),
            }));
        }
        setSettings(next);
        saveSlideshowSettings(next);
    };

    return (
        <Dialog
            open
            fullScreen
            onClose={onClose}
            aria-labelledby="album-slideshow-title"
            onKeyDown={handleKeyDown}
            onPointerMove={showControls}
            onPointerDown={showControls}
            onFocusCapture={showControls}
            slotProps={{
                paper: {
                    sx: {
                        bgcolor: "#000",
                        color: "#fff",
                        overflow: "hidden",
                        "& .slideshow-controls": {
                            opacity: controlsVisible ? 1 : 0,
                            transition: "opacity 200ms",
                        },
                        "&:has(button:focus-visible) .slideshow-controls": {
                            opacity: 1,
                            "& button": { pointerEvents: "auto" },
                        },
                    },
                },
            }}
        >
            <Slide
                key={current.id}
                file={current}
                onReady={markReady}
                blurredBackground={settings.blurredBackground}
            />
            <Box
                onClick={handlePhotoClick}
                sx={{ position: "absolute", inset: 0 }}
            />
            <Stack
                className="slideshow-controls"
                direction="row"
                sx={{
                    position: "relative",
                    alignItems: "center",
                    p: 2,
                    gap: 2,
                    background: "linear-gradient(#000b, transparent)",
                    pointerEvents: controlsVisible ? "auto" : "none",
                }}
            >
                <IconButton
                    aria-label={t("close")}
                    onClick={onClose}
                    color="inherit"
                >
                    <CloseIcon />
                </IconButton>
                <Typography id="album-slideshow-title" noWrap sx={{ flex: 1 }}>
                    {title}
                </Typography>
                <IconButton
                    aria-label={t("slideshow_settings")}
                    aria-haspopup="dialog"
                    onClick={settingsModal.show}
                    color="inherit"
                >
                    <SettingsIcon />
                </IconButton>
            </Stack>
            {files.length > 1 && (
                <Stack
                    className="slideshow-controls"
                    direction="row"
                    sx={{
                        position: "absolute",
                        top: "50%",
                        width: "100%",
                        transform: "translateY(-50%)",
                        alignItems: "center",
                        justifyContent: "space-between",
                        px: 2,
                        pointerEvents: "none",
                        "& button": {
                            pointerEvents: controlsVisible ? "auto" : "none",
                            color: "inherit",
                        },
                    }}
                >
                    <IconButton
                        aria-label={t("previous")}
                        onClick={() => navigate(-1)}
                    >
                        <NavigateBeforeIcon />
                    </IconButton>
                    <IconButton
                        aria-label={t(playing ? "pause" : "play")}
                        onClick={() => setPlaying((value) => !value)}
                        sx={{ bgcolor: "#0007", width: 56, height: 56 }}
                    >
                        {playing ? <PauseIcon /> : <PlayArrowIcon />}
                    </IconButton>
                    <IconButton
                        aria-label={t("next")}
                        onClick={() => navigate(1)}
                    >
                        <NavigateNextIcon />
                    </IconButton>
                </Stack>
            )}
            <AlbumSlideshowSettings
                {...settingsModal.props}
                settings={settings}
                onChange={handleSettingsChange}
            />
        </Dialog>
    );
}

function Slide({
    file,
    onReady,
    blurredBackground,
}: {
    file: EnteFile;
    onReady: (id: number) => void;
    blurredBackground: boolean;
}) {
    const [thumbnail, setThumbnail] = useState<string>();
    const [original, setOriginal] = useState<string>();
    const [loaded, setLoaded] = useState(false);
    const [failed, setFailed] = useState(false);
    const [thumbnailLoaded, setThumbnailLoaded] = useState(false);

    useEffect(() => {
        let cancelled = false;
        const isCancelled = () => cancelled;
        let livePhotoURL: string | undefined;
        void downloadManager
            .renderableThumbnailURL(file)
            .then((url) => {
                if (!isCancelled()) setThumbnail(url);
            })
            .catch(() => undefined);
        void downloadManager
            .renderableSourceURLs(file)
            .then(async (source) => {
                if (isCancelled()) return;
                if (source.type === "livePhoto") {
                    const url = await source.imageURL();
                    if (isCancelled()) {
                        URL.revokeObjectURL(url);
                    } else {
                        // Only Live Photo still URLs are owned by this slide.
                        livePhotoURL = url;
                        setOriginal(url);
                    }
                } else if (source.type === "image") {
                    setOriginal(source.imageURL);
                }
            })
            .catch((error: unknown) => {
                if (!isCancelled()) {
                    log.error("Failed to load slideshow photo", error);
                    setFailed(true);
                }
            });
        return () => {
            cancelled = true;
            if (livePhotoURL) URL.revokeObjectURL(livePhotoURL);
        };
    }, [file]);

    return (
        <>
            {blurredBackground && (
                <Box
                    aria-hidden
                    sx={{
                        position: "absolute",
                        inset: -100,
                        backgroundImage: `url("${thumbnail ?? original ?? ""}")`,
                        backgroundSize: "cover",
                        backgroundPosition: "center",
                        filter: "blur(100px)",
                        opacity: 0.6,
                    }}
                />
            )}
            {thumbnail && (
                <Box
                    component="img"
                    src={thumbnail}
                    alt={loaded ? "" : fileFileName(file)}
                    sx={imageStyle}
                    onLoad={() => {
                        setThumbnailLoaded(true);
                        onReady(file.id);
                    }}
                />
            )}
            {original && (
                <Box
                    component="img"
                    src={original}
                    alt={loaded ? fileFileName(file) : ""}
                    sx={{ ...imageStyle, opacity: loaded ? 1 : 0 }}
                    onLoad={() => {
                        setLoaded(true);
                        onReady(file.id);
                    }}
                    onError={() => {
                        setOriginal(undefined);
                        setFailed(true);
                    }}
                />
            )}
            {!loaded && !thumbnailLoaded && (
                <CenteredFill sx={{ position: "absolute", inset: 0 }}>
                    {failed ? (
                        <Typography>
                            {t("unpreviewable_file_message")}
                        </Typography>
                    ) : (
                        <CircularProgress color="inherit" />
                    )}
                </CenteredFill>
            )}
        </>
    );
}

const imageStyle = {
    position: "absolute",
    inset: 0,
    width: "100%",
    height: "100%",
    objectFit: "contain",
} as const;
