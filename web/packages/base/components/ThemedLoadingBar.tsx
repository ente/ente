import { keyframes } from "@emotion/react";
import { Box } from "@mui/material";
import type { LoadingBarController } from "ente-base/components/utils/use-loading-bar";
import React, { useEffect, useImperativeHandle, useRef, useState } from "react";

interface ThemedLoadingBarProps {
    ref: React.Ref<LoadingBarController>;
}

const loadingBarProgress = keyframes({
    from: { transform: "scaleX(0)" },
    to: { transform: "scaleX(0.9)" },
});

const completionDuration = 200;

type LoadingBarPhase = "hidden" | "running" | "completing";

export function ThemedLoadingBar({
    ref,
}: ThemedLoadingBarProps): React.JSX.Element {
    const [phase, setPhase] = useState<LoadingBarPhase>("hidden");
    const completionTimer = useRef<ReturnType<typeof setTimeout>>(undefined);

    useImperativeHandle(ref, () => ({
        continuousStart: () => {
            clearTimeout(completionTimer.current);
            setPhase("running");
        },
        complete: () => {
            clearTimeout(completionTimer.current);
            setPhase((phase) => (phase === "hidden" ? phase : "completing"));
            completionTimer.current = setTimeout(() => {
                setPhase("hidden");
            }, completionDuration);
        },
    }));

    useEffect(
        () => () => {
            clearTimeout(completionTimer.current);
        },
        [],
    );

    const isRunning = phase === "running";
    const isVisible = phase !== "hidden";

    return (
        <Box
            aria-hidden={!isVisible}
            role="progressbar"
            sx={{
                animation: isRunning
                    ? `${loadingBarProgress} 10s ease-out forwards`
                    : "none",
                bgcolor: "accent.main",
                bottom: 0,
                height: "2px",
                left: 0,
                opacity: isVisible ? 1 : 0,
                pointerEvents: "none",
                position: "fixed",
                transform: isRunning ? "scaleX(0)" : "scaleX(1)",
                transformOrigin: "left",
                transition: !isRunning
                    ? `transform ${completionDuration}ms ease-out, opacity 150ms ease-out`
                    : "none",
                width: "100%",
                zIndex: "calc(var(--mui-zIndex-tooltip) + 1)",
            }}
        />
    );
}
