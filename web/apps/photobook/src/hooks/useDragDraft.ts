import { useCallback, useEffect, useRef, useState } from "react";

export function useDragDraft<T>() {
    const [draft, setDraft] = useState<T | null>(null);
    const cleanup = useRef<(() => void) | null>(null);

    useEffect(() => () => cleanup.current?.(), []);

    const startDrag = useCallback(
        (calculate: (event: MouseEvent) => T, commit: (value: T) => void) => {
            cleanup.current?.();
            let frame: number | null = null;
            let latest: MouseEvent | null = null;
            const move = (event: MouseEvent) => {
                latest = event;
                if (frame !== null) return;
                frame = requestAnimationFrame(() => {
                    frame = null;
                    setDraft(calculate(latest!));
                });
            };
            const stop = () => {
                if (frame !== null) cancelAnimationFrame(frame);
                document.removeEventListener("mousemove", move);
                document.removeEventListener("mouseup", finish);
                cleanup.current = null;
            };
            const finish = (event: MouseEvent) => {
                stop();
                if (latest) commit(calculate(event));
                setDraft(null);
            };
            cleanup.current = stop;
            document.addEventListener("mousemove", move);
            document.addEventListener("mouseup", finish);
        },
        [],
    );

    return { draft, startDrag };
}
