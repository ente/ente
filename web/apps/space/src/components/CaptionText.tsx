import { Box } from "@mui/material";
import React from "react";

const captionBubbleSx = {
    borderRadius: "5px",
    boxDecorationBreak: "clone",
    px: "10px",
    py: "4px",
    WebkitBoxDecorationBreak: "clone",
} as const;

const captionSegmenter =
    typeof Intl !== "undefined" && "Segmenter" in Intl
        ? new Intl.Segmenter(undefined, { granularity: "grapheme" })
        : null;

export const SpaceCaptionText: React.FC<{
    caption: string;
    lineClamp?: number;
}> = ({ caption, lineClamp }) => {
    const measureRef = React.useRef<HTMLSpanElement>(null);
    const [clampedCaption, setClampedCaption] = React.useState(caption);

    React.useLayoutEffect(() => {
        const measure = measureRef.current;
        if (!measure || !lineClamp) return;

        const text = measure.firstElementChild!;
        const updateCaption = () => {
            const maxHeight =
                parseFloat(getComputedStyle(measure).lineHeight) * lineClamp;
            text.textContent = caption;
            if (measure.getBoundingClientRect().height <= maxHeight) {
                setClampedCaption(caption);
                return;
            }

            const characters = captionSegmenter
                ? Array.from(
                      captionSegmenter.segment(caption),
                      ({ segment }) => segment,
                  )
                : Array.from(caption);
            const truncated = (length: number) =>
                `${characters.slice(0, length).join("").trimEnd()}…`;
            let start = 0;
            let end = characters.length;
            while (start < end) {
                const middle = Math.ceil((start + end) / 2);
                text.textContent = truncated(middle);
                if (measure.getBoundingClientRect().height <= maxHeight) {
                    start = middle;
                } else {
                    end = middle - 1;
                }
            }
            text.textContent = caption;
            setClampedCaption(truncated(start));
        };

        updateCaption();
        const observer = new ResizeObserver(updateCaption);
        observer.observe(measure);
        document.fonts.addEventListener("loadingdone", updateCaption);
        return () => {
            observer.disconnect();
            document.fonts.removeEventListener("loadingdone", updateCaption);
        };
    }, [caption, lineClamp]);

    const displayCaption = lineClamp ? clampedCaption : caption;
    const layerSx = {
        display: "block",
        gridArea: "1 / 1",
        minWidth: 0,
        overflowWrap: lineClamp ? "anywhere" : undefined,
    } as const;

    return (
        <Box component="span" sx={{ display: "grid" }}>
            {lineClamp ? (
                <Box
                    component="span"
                    sx={{ ...layerSx, height: 0, overflow: "hidden" }}
                >
                    <Box component="span" ref={measureRef} sx={layerSx}>
                        <Box component="span" sx={captionBubbleSx}>
                            {caption}
                        </Box>
                    </Box>
                </Box>
            ) : null}
            <Box
                component="span"
                aria-hidden
                sx={{ ...layerSx, color: "transparent", opacity: 0.85 }}
            >
                <Box
                    component="span"
                    sx={{ ...captionBubbleSx, bgcolor: "#202020" }}
                >
                    <Box component="span" sx={{ opacity: 0 }}>
                        {displayCaption}
                    </Box>
                </Box>
            </Box>
            <Box
                component="span"
                aria-hidden={lineClamp ? true : undefined}
                sx={{ ...layerSx, zIndex: 1 }}
            >
                <Box component="span" sx={captionBubbleSx}>
                    {displayCaption}
                </Box>
            </Box>
        </Box>
    );
};
