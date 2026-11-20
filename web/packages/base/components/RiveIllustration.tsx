import { useMediaQuery } from "@mui/material";
import type { Rive } from "@rive-app/canvas-lite";
import log from "ente-base/log";
import { useEffect, useRef, useState, type ReactNode } from "react";

interface RiveIllustrationProps {
    src: URL;
    stateMachine: string;
    fallback: ReactNode;
    className?: string;
    runtime?: "canvas-lite" | "canvas";
}

export function RiveIllustration({
    src,
    stateMachine,
    fallback,
    className,
    runtime = "canvas-lite",
}: RiveIllustrationProps) {
    const canvasRef = useRef<HTMLCanvasElement>(null);
    const prefersReducedMotion = useMediaQuery(
        "(prefers-reduced-motion: reduce)",
    );
    const [readySource, setReadySource] = useState<string>();
    const url = src.href;
    const showCanvas = !prefersReducedMotion && readySource === url;

    useEffect(() => {
        const canvas = canvasRef.current;
        if (!canvas || prefersReducedMotion) return;

        let disposed = false;
        let rive:
            Pick<Rive, "cleanup" | "resizeDrawingSurfaceToCanvas"> | undefined;
        let resizeObserver: ResizeObserver | undefined;
        let firstFrame = 0;

        const load = async () => {
            const { RuntimeLoader, Rive } =
                runtime === "canvas"
                    ? await import("@rive-app/canvas")
                    : await import("@rive-app/canvas-lite");
            RuntimeLoader.setWasmUrl(
                runtime === "canvas"
                    ? new URL("@rive-app/canvas/rive.wasm", import.meta.url)
                          .href
                    : new URL(
                          "@rive-app/canvas-lite/rive.wasm",
                          import.meta.url,
                      ).href,
            );
            RuntimeLoader.setWasmFallbackUrl(null);
            await RuntimeLoader.awaitInstance();
            if (disposed) return;

            let drewFrame = false;
            rive = new Rive({
                canvas,
                src: url,
                stateMachine,
                autoplay: true,
                enableRiveAssetCDN: false,
                shouldDisableRiveListeners: true,
                onLoad: () => {
                    if (disposed || !rive) return;
                    const resize = () => rive?.resizeDrawingSurfaceToCanvas();
                    resize();
                    resizeObserver = new ResizeObserver(resize);
                    resizeObserver.observe(canvas);
                },
                onAdvance: () => {
                    if (disposed || drewFrame) return;
                    drewFrame = true;
                    firstFrame = requestAnimationFrame(() => {
                        if (!disposed) setReadySource(url);
                    });
                },
                onLoadError: (error) =>
                    log.warn("Failed to load Rive illustration", error),
            });
        };

        // Auth renders separate panels for each breakpoint. Only load the
        // illustration that is visible.
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
            rive?.cleanup();
        };
    }, [prefersReducedMotion, runtime, stateMachine, url]);

    return (
        <div
            className={className}
            aria-hidden="true"
            style={{ position: "relative" }}
        >
            <div style={{ visibility: showCanvas ? "hidden" : undefined }}>
                {fallback}
            </div>
            <canvas
                ref={canvasRef}
                style={{
                    position: "absolute",
                    inset: 0,
                    width: "100%",
                    height: "100%",
                    visibility: showCanvas ? undefined : "hidden",
                    pointerEvents: "none",
                }}
            />
        </div>
    );
}
