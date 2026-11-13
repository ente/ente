import { Box } from "@mui/material";
import type { Rive, ViewModelInstance } from "@rive-app/canvas-lite";
import { pickLikeVariant } from "components/post-like-animation";
import { preloadPostLikeAnimation } from "components/post-like-rive";
import log from "ente-base/log";
import React from "react";

const jumpVariant = -1;
const likeAnimationMs = 1600;

interface SpacePostLikeHeartProps {
    liked: boolean;
    toggleID: number;
    popID: number;
    size: number;
    fallback: React.ReactNode;
}

export const SpacePostLikeHeart: React.FC<SpacePostLikeHeartProps> = ({
    liked,
    toggleID,
    popID,
    size,
    fallback,
}) => {
    const canvasRef = React.useRef<HTMLCanvasElement | null>(null);
    const riveRef = React.useRef<Rive | undefined>(undefined);
    const pauseTimerRef = React.useRef(0);
    const readyRef = React.useRef(false);
    const shownRef = React.useRef({ liked, toggleID, variant: jumpVariant });
    const [viewModel, setViewModel] = React.useState<ViewModelInstance>();
    const [ready, setReady] = React.useState(false);
    const canvasSize = Math.round((160 * size) / 22);

    const playFor = React.useCallback((ms: number) => {
        const rive = riveRef.current;
        if (!rive) return;
        window.clearTimeout(pauseTimerRef.current);
        rive.play();
        pauseTimerRef.current = window.setTimeout(() => rive.pause(), ms);
    }, []);

    React.useEffect(() => {
        const canvas = canvasRef.current!;
        if (window.matchMedia("(prefers-reduced-motion: reduce)").matches)
            return;
        let disposed = false;
        let started = false;
        let firstFrame = 0;
        let didDraw = false;
        const prepare = async () => {
            if (started) return;
            started = true;
            const prepared = await preloadPostLikeAnimation();
            if (!prepared || disposed) return;
            const { runtime, file } = prepared;
            const rive = new runtime.Rive({
                autoBind: true,
                autoplay: false,
                canvas,
                enableRiveAssetCDN: false,
                layout: new runtime.Layout({ fit: runtime.Fit.Contain }),
                riveFile: file,
                stateMachine: "Like",
                onLoad: () => {
                    if (disposed) return;
                    rive.resizeDrawingSurfaceToCanvas();
                    const instance = rive.viewModelInstance;
                    if (!instance) return;
                    instance.number("variant")!.value = jumpVariant;
                    instance.boolean("liked")!.value = shownRef.current.liked;
                    playFor(150);
                },
                onAdvance: () => {
                    if (disposed || didDraw) return;
                    didDraw = true;
                    firstFrame = requestAnimationFrame(() => {
                        if (!disposed)
                            setViewModel(rive.viewModelInstance ?? undefined);
                    });
                },
                onLoadError: () =>
                    log.warn("Failed to load the like animation"),
            });
            riveRef.current = rive;
        };
        const observer = new IntersectionObserver(
            (entries) => {
                if (entries.some((entry) => entry.isIntersecting)) {
                    observer.disconnect();
                    void prepare();
                }
            },
            { rootMargin: "200px" },
        );
        observer.observe(canvas.parentElement!);
        return () => {
            disposed = true;
            observer.disconnect();
            cancelAnimationFrame(firstFrame);
            window.clearTimeout(pauseTimerRef.current);
            riveRef.current?.cleanup();
            riveRef.current = undefined;
        };
    }, [playFor]);

    React.useLayoutEffect(() => {
        const shown = shownRef.current;
        const animate = readyRef.current && toggleID != shown.toggleID;
        if (viewModel) {
            const variant = viewModel.number("variant")!;
            if (!animate) {
                variant.value = jumpVariant;
            } else if (liked) {
                shown.variant = pickLikeVariant(shown.variant);
                variant.value = shown.variant;
            } else if (variant.value < 0) {
                variant.value = 0;
            }
            viewModel.boolean("liked")!.value = liked;
            playFor(animate ? likeAnimationMs : 150);
        }
        shown.liked = liked;
        shown.toggleID = toggleID;
    }, [liked, toggleID, viewModel, playFor]);

    React.useEffect(() => {
        if (viewModel && popID == 0) {
            readyRef.current = true;
            setReady(true);
        }
    }, [viewModel, popID]);

    return (
        <Box
            component="span"
            sx={{ display: "flex", lineHeight: 0, position: "relative" }}
        >
            <Box
                component="span"
                sx={{
                    display: "flex",
                    visibility: ready ? "hidden" : "visible",
                }}
            >
                {fallback}
            </Box>
            <Box
                ref={canvasRef}
                component="canvas"
                aria-hidden
                sx={{
                    height: canvasSize,
                    left: "50%",
                    pointerEvents: "none",
                    position: "absolute",
                    top: "50%",
                    transform: "translate(-50%, -50%)",
                    visibility: ready ? "visible" : "hidden",
                    width: canvasSize,
                }}
            />
        </Box>
    );
};
