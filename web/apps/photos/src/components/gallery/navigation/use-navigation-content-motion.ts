import { useEffect, useLayoutEffect, useRef } from "react";

export const navigationMotion = {
    easing: "cubic-bezier(0.32, 0.72, 0, 1)",
    duration: 200,
    fadeDuration: 150,
};

export const useNavigationContentMotion = (
    layoutKey: string | boolean,
    reduceMotion: boolean,
) => {
    const ref = useRef<HTMLDivElement>(null);
    const previousLeft = useRef<number | undefined>(undefined);
    const animation = useRef<Animation | undefined>(undefined);

    useLayoutEffect(() => {
        const element = ref.current;
        if (!element) {
            animation.current?.cancel();
            animation.current = undefined;
            previousLeft.current = undefined;
            return;
        }
        const previousAnimation = animation.current;
        const offset =
            !reduceMotion && previousAnimation?.playState == "running"
                ? new DOMMatrixReadOnly(getComputedStyle(element).transform).m41
                : 0;
        previousAnimation?.cancel();
        animation.current = undefined;
        const left = element.getBoundingClientRect().left;
        const from = previousLeft.current;
        previousLeft.current = left;
        if (from === undefined || reduceMotion) return;
        const delta = from + offset - left;
        if (Math.abs(delta) < 0.5) return;
        const motion = element.animate(
            [
                { transform: `translateX(${delta}px)` },
                { transform: "translateX(0)" },
            ],
            {
                duration: navigationMotion.duration,
                easing: navigationMotion.easing,
            },
        );
        animation.current = motion;
    }, [layoutKey, reduceMotion]);

    useEffect(() => {
        const resetPosition = () => {
            animation.current?.cancel();
            previousLeft.current = ref.current?.getBoundingClientRect().left;
        };
        window.addEventListener("resize", resetPosition);
        return () => {
            window.removeEventListener("resize", resetPosition);
            animation.current?.cancel();
        };
    }, []);
    return ref;
};
