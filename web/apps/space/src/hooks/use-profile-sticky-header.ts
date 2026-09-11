import React from "react";

export const useProfileStickyHeader = (
    enabled: boolean,
    identityRef: React.RefObject<HTMLDivElement | null>,
    compactHeight: number,
) => {
    const [header, setHeader] = React.useState({
        isSticky: false,
        shouldAnimate: false,
    });
    const syncScroll = React.useCallback(() => {
        const identity = identityRef.current;
        if (!enabled || !identity) return;
        setHeader({
            isSticky: identity.getBoundingClientRect().bottom < compactHeight,
            shouldAnimate: false,
        });
    }, [compactHeight, enabled, identityRef]);

    React.useLayoutEffect(() => {
        const identity = identityRef.current;
        if (!enabled || !identity) return;
        syncScroll();
        const observer = new IntersectionObserver(
            ([entry]) => {
                const isSticky =
                    entry!.boundingClientRect.bottom < compactHeight;
                setHeader((current) =>
                    current.isSticky == isSticky
                        ? current
                        : { isSticky, shouldAnimate: true },
                );
            },
            { rootMargin: `-${compactHeight}px 0px 0px`, threshold: 0 },
        );
        observer.observe(identity);
        return () => observer.disconnect();
    }, [compactHeight, enabled, identityRef, syncScroll]);

    return { ...header, syncScroll };
};
