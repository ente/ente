import { HugeiconsIcon } from "@hugeicons/react";
import { useColorScheme, useMediaQuery } from "@mui/material";
import type { Rive } from "@rive-app/canvas-lite";
import { RiveIllustration } from "ente-base/components/RiveIllustration";
import { useEffect, useRef, type ComponentProps } from "react";

export type RailIconArtboard =
    "home" | "search" | "albums" | "people" | "links" | "places" | "settings";

const src = new URL("../../../assets/ente-sidebar-icons.riv", import.meta.url);
const stateMachine = "Icon";

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
    const { mode, systemMode } = useColorScheme();
    const dark = (mode === "system" ? systemMode : mode) === "dark";
    const reduceMotion = useMediaQuery("(prefers-reduced-motion: reduce)");
    const current = useRef({ dark, selected });
    const sync = useRef<() => void>(undefined);

    useEffect(() => {
        current.current = { dark, selected };
        sync.current?.();
    }, [dark, selected]);

    const setup = (rive: Rive, canvas: HTMLCanvasElement) => {
        const button = canvas.closest("button");
        const controls = rive.stateMachineInputs(stateMachine);
        const { active, dark, hover, click } = Object.fromEntries(
            (controls ?? []).map((input) => [input.name, input]),
        );
        if (!button || !active || !dark || !hover || !click)
            return false as const;

        let secondsLeft = 0;
        const play = () => {
            secondsLeft = 1.5;
            rive.play();
        };
        const syncState = () => {
            active.value = current.current.selected;
            dark.value = current.current.dark;
            hover.value =
                !button.disabled &&
                window.matchMedia("(any-hover: hover)").matches &&
                button.matches(":hover");
            play();
        };
        const pointerEnter = (event: PointerEvent) => {
            if (event.pointerType === "touch" || button.disabled) return;
            hover.value = true;
            play();
        };
        const pointerLeave = () => {
            hover.value = false;
            play();
        };
        const press = () => {
            if (button.disabled) return;
            click.fire();
            play();
        };

        sync.current = syncState;
        syncState();
        button.addEventListener("pointerenter", pointerEnter);
        button.addEventListener("pointerleave", pointerLeave);
        button.addEventListener("click", press);

        return {
            advance: (seconds: number) => {
                secondsLeft -= seconds;
                if (secondsLeft <= 0) rive.pause();
            },
            cleanup: () => {
                sync.current = undefined;
                button.removeEventListener("pointerenter", pointerEnter);
                button.removeEventListener("pointerleave", pointerLeave);
                button.removeEventListener("click", press);
            },
        };
    };

    const fallback = (
        <HugeiconsIcon
            icon={icon}
            size={16}
            strokeWidth={1.8}
            style={{ display: "block" }}
        />
    );
    return artboard ? (
        <RiveIllustration
            {...{ src, artboard, stateMachine, fallback, setup }}
            element="span"
            staticFrameOnReducedMotion
            style={{ display: "flex" }}
            canvasStyle={{
                inset: "auto",
                width: 24,
                height: 24,
                top: "50%",
                left: "50%",
                transform: "translate(-50%, -50%)",
                filter:
                    reduceMotion && (dark || selected)
                        ? "invert(1)"
                        : undefined,
            }}
        />
    ) : (
        fallback
    );
};
