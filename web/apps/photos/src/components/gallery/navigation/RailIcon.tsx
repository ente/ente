import { HugeiconsIcon } from "@hugeicons/react";
import { Box, useColorScheme, useMediaQuery } from "@mui/material";
import type { Rive } from "@rive-app/canvas-lite";
import log from "ente-base/log";
import {
    useEffect,
    useEffectEvent,
    useRef,
    useState,
    type ComponentProps,
} from "react";

export type RailIconArtboard =
    "home" | "search" | "albums" | "people" | "links" | "places" | "settings";

const stateMachine = "Icon";

// Share the parsed file across the rail's canvases and keep it available for
// subsequent gallery mounts.
const loadIconFile = async () => {
    const { Rive, RiveFile, RuntimeLoader } =
        await import("@rive-app/canvas-lite");
    RuntimeLoader.setWasmUrl(
        new URL("@rive-app/canvas-lite/rive.wasm", import.meta.url).href,
    );
    RuntimeLoader.setWasmFallbackUrl(null);
    await RuntimeLoader.awaitInstance();

    const file = new RiveFile({
        src: new URL("../../../assets/ente-sidebar-icons.riv", import.meta.url)
            .href,
        enableRiveAssetCDN: false,
    });
    await file.init();
    file.getInstance();
    return { Rive, file };
};

let iconFile: ReturnType<typeof loadIconFile> | undefined;

interface RailIconProps {
    icon: ComponentProps<typeof HugeiconsIcon>["icon"];
    artboard?: RailIconArtboard;
    selected?: boolean;
}

export const RailIcon = ({
    icon,
    artboard,
    selected = false,
}: RailIconProps) => {
    const reduceMotion = useMediaQuery("(prefers-reduced-motion: reduce)");
    const fallback = <HugeiconsIcon icon={icon} size={16} strokeWidth={1.8} />;
    return artboard ? (
        <AnimatedRailIcon
            key={`${artboard}:${reduceMotion}`}
            {...{ artboard, fallback, selected, reduceMotion }}
        />
    ) : (
        fallback
    );
};

interface RailIconInputs {
    active: { value: number | boolean };
    dark: { value: number | boolean };
    hover: { value: number | boolean };
    click: { fire: () => void };
}

const AnimatedRailIcon = ({
    artboard,
    fallback,
    selected,
    reduceMotion,
}: {
    artboard: RailIconArtboard;
    fallback: React.ReactNode;
    selected: boolean;
    reduceMotion: boolean;
}) => {
    const canvasRef = useRef<HTMLCanvasElement>(null);
    const syncRef = useRef<() => void>(undefined);
    const [ready, setReady] = useState(false);
    const { mode, systemMode } = useColorScheme();
    const dark = (mode === "system" ? systemMode : mode) === "dark";
    const syncState = useEffectEvent(
        (inputs: RailIconInputs, button: HTMLButtonElement) => {
            inputs.dark.value = dark;
            inputs.active.value = selected;
            inputs.hover.value =
                !button.disabled &&
                window.matchMedia("(any-hover: hover)").matches &&
                button.matches(":hover");
        },
    );
    useEffect(() => {
        syncRef.current?.();
    }, [dark, reduceMotion, selected]);

    useEffect(() => {
        const canvas = canvasRef.current!;
        const button = canvas.closest("button")!;
        let disposed = false;
        let rive: Rive | undefined;
        let inputs: RailIconInputs | undefined;
        let secondsLeft = 0;
        let drewFrame = false;

        const play = () => {
            // Let the authored transition finish, then stop advancing the idle
            // state. Use animation time so background tabs can resume cleanly.
            secondsLeft = 1.5;
            rive?.play();
        };
        const sync = () => {
            if (reduceMotion || !inputs) return;
            syncState(inputs, button);
            play();
        };
        const setHover = (hover: boolean) => {
            if (!inputs) return;
            inputs.hover.value = hover;
            play();
        };
        const pointerEnter = (event: PointerEvent) => {
            if (event.pointerType !== "touch" && !button.disabled)
                setHover(true);
        };
        const pointerLeave = () => setHover(false);
        const click = () => {
            if (!inputs || button.disabled) return;
            inputs.click.fire();
            play();
        };
        const resize = () => {
            rive?.resizeDrawingSurfaceToCanvas();
            rive?.drawFrame();
        };

        syncRef.current = sync;
        if (!reduceMotion) {
            button.addEventListener("pointerenter", pointerEnter);
            button.addEventListener("pointerleave", pointerLeave);
            button.addEventListener("click", click);
        }
        window.addEventListener("resize", resize);

        iconFile ??= loadIconFile().catch((error: unknown) => {
            iconFile = undefined;
            throw error;
        });
        void iconFile
            .then(({ Rive, file }) => {
                if (disposed) return;
                rive = new Rive({
                    canvas,
                    artboard,
                    riveFile: file,
                    stateMachine,
                    autoplay: false,
                    shouldDisableRiveListeners: true,
                    onLoad: () => {
                        if (disposed || !rive) return;
                        // The supplied artboards expose state machine inputs.
                        // eslint-disable-next-line @typescript-eslint/no-deprecated
                        const controls = rive.stateMachineInputs(stateMachine);
                        const { active, dark, hover, click } =
                            Object.fromEntries(
                                (controls ?? []).map((input) => [
                                    input.name,
                                    input,
                                ]),
                            );
                        if (!active || !dark || !hover || !click) return;
                        inputs = { active, dark, hover, click };
                        rive.resizeDrawingSurfaceToCanvas();
                        if (reduceMotion) play();
                        else sync();
                    },
                    onAdvance: ({ data }) => {
                        if (disposed || !inputs || typeof data !== "number")
                            return;
                        if (!drewFrame) {
                            drewFrame = true;
                            setReady(true);
                        }
                        secondsLeft -= data;
                        if (reduceMotion || secondsLeft <= 0) rive?.pause();
                    },
                    onLoadError: (error) =>
                        log.warn("Failed to load navigation rail icon", error),
                });
            })
            .catch((error: unknown) => {
                if (!disposed)
                    log.warn(
                        "Failed to initialize navigation rail icon",
                        error,
                    );
            });

        return () => {
            disposed = true;
            syncRef.current = undefined;
            button.removeEventListener("pointerenter", pointerEnter);
            button.removeEventListener("pointerleave", pointerLeave);
            button.removeEventListener("click", click);
            window.removeEventListener("resize", resize);
            rive?.cleanup();
        };
    }, [artboard, reduceMotion]);

    return (
        <Box
            component="span"
            aria-hidden
            sx={{ display: "flex", position: "relative" }}
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
                component="canvas"
                ref={canvasRef}
                sx={{
                    position: "absolute",
                    width: 24,
                    height: 24,
                    top: "50%",
                    left: "50%",
                    transform: "translate(-50%, -50%)",
                    visibility: ready ? "visible" : "hidden",
                    pointerEvents: "none",
                    // Recolor the idle frame without playing selection or theme transitions.
                    filter:
                        reduceMotion && (dark || selected)
                            ? "invert(1)"
                            : undefined,
                }}
            />
        </Box>
    );
};
