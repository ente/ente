import { useMediaQuery } from "@mui/material";
import type { Rive, RiveFile } from "@rive-app/canvas-lite";
import log from "ente-base/log";
import {
    useEffect,
    useEffectEvent,
    useRef,
    useState,
    type CSSProperties,
    type ReactNode,
} from "react";

interface RiveIllustrationPlayback {
    advance?: (seconds: number) => void;
    cleanup?: () => void;
}

interface RiveIllustrationProps {
    src: URL;
    stateMachine: string;
    fallback: ReactNode;
    className?: string;
    artboard?: string;
    element?: "div" | "span";
    style?: CSSProperties;
    canvasStyle?: CSSProperties;
    staticFrameOnReducedMotion?: boolean;
    setup?: (
        rive: Rive,
        canvas: HTMLCanvasElement,
    ) => RiveIllustrationPlayback | false;
}

const artboardFiles = new Map<string, Promise<RiveFile>>();

const getArtboardFile = (url: string, File: typeof RiveFile) => {
    let pending = artboardFiles.get(url);
    if (!pending) {
        const file = new File({ src: url, enableRiveAssetCDN: false });
        pending = file
            .init()
            .then(() => {
                file.getInstance();
                return file;
            })
            .catch((error: unknown) => {
                artboardFiles.delete(url);
                file.cleanup();
                throw error;
            });
        artboardFiles.set(url, pending);
    }
    return pending;
};

export function RiveIllustration(props: RiveIllustrationProps) {
    const prefersReducedMotion = useMediaQuery(
        "(prefers-reduced-motion: reduce)",
    );
    const motion = prefersReducedMotion
        ? props.staticFrameOnReducedMotion
            ? "static"
            : "fallback"
        : "animated";
    return (
        <RiveIllustrationCanvas
            key={JSON.stringify([
                props.src.href,
                props.stateMachine,
                props.artboard,
                motion,
            ])}
            {...props}
            motion={motion}
        />
    );
}

function RiveIllustrationCanvas({
    src,
    stateMachine,
    fallback,
    className,
    artboard,
    element: Root = "div",
    style,
    canvasStyle,
    setup,
    motion,
}: RiveIllustrationProps & { motion: "animated" | "static" | "fallback" }) {
    const canvasRef = useRef<HTMLCanvasElement>(null);
    const [showCanvas, setShowCanvas] = useState(false);
    const url = src.href;
    const manualPlayback = motion === "animated" && !!setup;
    const setupPlayback = useEffectEvent(
        (rive: Rive, canvas: HTMLCanvasElement) => setup?.(rive, canvas),
    );

    useEffect(() => {
        const canvas = canvasRef.current;
        if (!canvas || motion === "fallback") return;

        let disposed = false;
        let rive: Rive | undefined;
        let playback: RiveIllustrationPlayback | false | undefined;
        let resizeObserver: ResizeObserver | undefined;
        let firstFrame = 0;
        let drewFrame = false;

        const load = async () => {
            const { RuntimeLoader, Rive, RiveFile } =
                await import("@rive-app/canvas-lite");
            RuntimeLoader.setWasmUrl(
                new URL("@rive-app/canvas-lite/rive.wasm", import.meta.url)
                    .href,
            );
            RuntimeLoader.setWasmFallbackUrl(null);
            await RuntimeLoader.awaitInstance();
            const file =
                artboard && !disposed
                    ? await getArtboardFile(url, RiveFile)
                    : undefined;
            if (disposed) return;

            rive = new Rive({
                canvas,
                ...(file ? { riveFile: file } : { src: url }),
                artboard,
                stateMachine,
                autoplay: !manualPlayback,
                enableRiveAssetCDN: false,
                shouldDisableRiveListeners: true,
                onLoad: () => {
                    if (disposed || !rive) return;
                    rive.resizeDrawingSurfaceToCanvas();
                    if (manualPlayback) playback = setupPlayback(rive, canvas);
                    if (playback === false) return;

                    resizeObserver = new ResizeObserver(() => {
                        rive?.resizeDrawingSurfaceToCanvas();
                        if (manualPlayback || motion === "static")
                            rive?.drawFrame();
                    });
                    resizeObserver.observe(canvas);
                },
                onAdvance: ({ data }) => {
                    if (disposed || playback === false) return;
                    if (typeof data === "number") playback?.advance?.(data);
                    if (drewFrame) return;
                    drewFrame = true;
                    if (motion === "static") rive?.pause();
                    firstFrame = requestAnimationFrame(() => {
                        if (!disposed) setShowCanvas(true);
                    });
                },
                onLoadError: (error) =>
                    log.warn("Failed to load Rive illustration", error),
            });
        };

        const observer = new IntersectionObserver((entries) => {
            if (!entries.some((entry) => entry.isIntersecting)) return;
            observer.disconnect();
            void load().catch((error: unknown) =>
                log.warn("Failed to initialize Rive illustration", error),
            );
        });
        observer.observe(canvas);

        return () => {
            disposed = true;
            observer.disconnect();
            resizeObserver?.disconnect();
            cancelAnimationFrame(firstFrame);
            if (playback) playback.cleanup?.();
            rive?.cleanup();
        };
    }, [artboard, manualPlayback, motion, stateMachine, url]);

    return (
        <Root
            className={className}
            aria-hidden="true"
            style={{ position: "relative", ...style }}
        >
            <Root style={{ visibility: showCanvas ? "hidden" : undefined }}>
                {fallback}
            </Root>
            <canvas
                ref={canvasRef}
                style={{
                    position: "absolute",
                    inset: 0,
                    width: "100%",
                    height: "100%",
                    ...canvasStyle,
                    visibility: showCanvas ? undefined : "hidden",
                    pointerEvents: "none",
                }}
            />
        </Root>
    );
}
