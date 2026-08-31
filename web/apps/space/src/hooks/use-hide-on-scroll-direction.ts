import React from "react";

const hideStartY = 96;
const hideDelta = 4;

const pageScrollY = () =>
    Math.max(
        0,
        window.scrollY ||
            document.scrollingElement?.scrollTop ||
            document.documentElement.scrollTop ||
            document.body.scrollTop ||
            0,
    );

export const useHideOnScrollDirection = () => {
    const [isHidden, setIsHidden] = React.useState(false);
    const lastScrollYRef = React.useRef(0);
    const frameRef = React.useRef<number | null>(null);

    React.useEffect(() => {
        lastScrollYRef.current = pageScrollY();

        const updateVisibility = () => {
            frameRef.current = null;
            const nextScrollY = pageScrollY();
            const delta = nextScrollY - lastScrollYRef.current;
            lastScrollYRef.current = nextScrollY;

            if (nextScrollY <= hideStartY) {
                setIsHidden(false);
                return;
            }

            if (delta > hideDelta) {
                setIsHidden(true);
                return;
            }

            if (delta < -1) setIsHidden(false);
        };

        const scheduleUpdate = () => {
            if (frameRef.current != null) return;
            frameRef.current = window.requestAnimationFrame(updateVisibility);
        };

        window.addEventListener("scroll", scheduleUpdate, { passive: true });
        document.addEventListener("scroll", scheduleUpdate, { passive: true });
        return () => {
            window.removeEventListener("scroll", scheduleUpdate);
            document.removeEventListener("scroll", scheduleUpdate);
            if (frameRef.current != null) {
                window.cancelAnimationFrame(frameRef.current);
            }
        };
    }, []);

    return isHidden;
};
