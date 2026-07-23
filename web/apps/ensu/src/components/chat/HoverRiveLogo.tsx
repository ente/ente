import { Box } from "@mui/material";
import { useRouter } from "next/router";
import { memo, useEffect, useRef, useState } from "react";

type HoverRiveLogoProps = { staticSrc: string; alt: string; sizePx?: number };

type RivePlaybackTarget = string | string[];

type RiveInstance = {
    cleanup?: () => void;
    resizeDrawingSurfaceToCanvas?: () => void;
    play?: (animation?: RivePlaybackTarget) => void;
    pause?: () => void;
    stop?: () => void;
    reset?: () => void;
    animationNames?: string[];
    stateMachineNames?: string[];
};

const RIVE_SRC = "/animations/ensu.riv";

const HoverRiveLogo = memo(
    ({ staticSrc, alt, sizePx = 28 }: HoverRiveLogoProps) => {
        const canvasRef = useRef<HTMLCanvasElement | null>(null);
        const riveRef = useRef<RiveInstance | null>(null);
        const playbackTargetRef = useRef<RivePlaybackTarget | undefined>(
            undefined,
        );
        const [isHovering, setIsHovering] = useState(false);
        const [isReady, setIsReady] = useState(false);
        const [failedToLoad, setFailedToLoad] = useState(false);
        const { basePath } = useRouter();
        const riveSrc = `${basePath ?? ""}${RIVE_SRC}`;

        useEffect(() => {
            if (typeof window === "undefined") return;

            let canceled = false;

            const initialize = async () => {
                try {
                    const rive = await import("@rive-app/canvas");
                    if (canceled || !canvasRef.current) return;

                    const { Alignment, Fit, Layout, Rive } = rive;
                    riveRef.current = new Rive({
                        src: riveSrc,
                        canvas: canvasRef.current,
                        autoplay: false,
                        layout: new Layout({
                            fit: Fit.Contain,
                            alignment: Alignment.Center,
                        }),
                        onLoad: () => {
                            try {
                                riveRef.current?.resizeDrawingSurfaceToCanvas?.();

                                const stateMachineNames =
                                    riveRef.current?.stateMachineNames ?? [];
                                const animationNames =
                                    riveRef.current?.animationNames ?? [];

                                if (stateMachineNames.length > 0) {
                                    playbackTargetRef.current =
                                        stateMachineNames[0];
                                } else if (animationNames.length > 1) {
                                    playbackTargetRef.current = animationNames;
                                } else if (animationNames.length === 1) {
                                    playbackTargetRef.current =
                                        animationNames[0];
                                }

                                riveRef.current?.pause?.();
                            } catch {
                                // noop
                            }
                            if (!canceled) {
                                setIsReady(true);
                            }
                        },
                        onLoadError: () => {
                            if (!canceled) {
                                setFailedToLoad(true);
                            }
                        },
                    });
                } catch {
                    if (!canceled) {
                        setFailedToLoad(true);
                    }
                }
            };

            void initialize();

            return () => {
                canceled = true;
                try {
                    riveRef.current?.cleanup?.();
                } catch {
                    // noop
                }
                riveRef.current = null;
                playbackTargetRef.current = undefined;
            };
        }, [riveSrc]);

        const startAnimation = () => {
            setIsHovering(true);
            try {
                riveRef.current?.reset?.();
                const target = playbackTargetRef.current;
                if (target) {
                    riveRef.current?.play?.(target);
                } else {
                    riveRef.current?.play?.();
                }
            } catch {
                // noop
            }
        };

        const stopAnimation = () => {
            setIsHovering(false);
            try {
                riveRef.current?.pause?.();
                riveRef.current?.stop?.();
            } catch {
                // noop
            }
        };

        const canShowRive = isReady && !failedToLoad;
        const showRive = isHovering && canShowRive;

        return (
            <Box
                onMouseEnter={startAnimation}
                onMouseLeave={stopAnimation}
                sx={{
                    position: "relative",
                    width: sizePx,
                    height: sizePx,
                    display: "inline-flex",
                    alignItems: "center",
                    justifyContent: "center",
                    flexShrink: 0,
                }}
            >
                <Box
                    component="img"
                    src={staticSrc}
                    alt={alt}
                    sx={{
                        width: "100%",
                        height: "100%",
                        display: "block",
                        opacity: showRive ? 0 : 1,
                        transition: "opacity 160ms ease-out",
                    }}
                />
                <Box
                    component="canvas"
                    ref={canvasRef}
                    aria-label={`${alt} animation`}
                    sx={{
                        position: "absolute",
                        inset: 0,
                        width: "100%",
                        height: "100%",
                        display: "block",
                        opacity: showRive ? 1 : 0,
                        transition: "opacity 160ms ease-out",
                        transform: "scale(1.08)",
                        transformOrigin: "50% 50%",
                        pointerEvents: "none",
                    }}
                />
            </Box>
        );
    },
);

HoverRiveLogo.displayName = "HoverRiveLogo";

export default HoverRiveLogo;
