import { useCallback, useEffect, useRef } from "react";

export function useAutoScroll(
    containerRef: React.RefObject<HTMLElement | null>,
) {
    const frameRef = useRef<number | null>(null);
    const speed = useRef(0);

    const start = useCallback(() => {
        if (frameRef.current !== null) return;
        const tick = () => {
            const el = containerRef.current;
            if (el && speed.current !== 0) {
                el.scrollTop += speed.current;
            }
            frameRef.current = requestAnimationFrame(tick);
        };
        frameRef.current = requestAnimationFrame(tick);
    }, [containerRef]);

    const stop = useCallback(() => {
        if (frameRef.current !== null) {
            cancelAnimationFrame(frameRef.current);
            frameRef.current = null;
        }
        speed.current = 0;
    }, []);

    // Clean up on unmount
    useEffect(
        () => () => {
            if (frameRef.current !== null)
                cancelAnimationFrame(frameRef.current);
        },
        [],
    );

    return { start, stop, speed };
}
