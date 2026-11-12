import { Box, ButtonBase, Typography } from "@mui/material";
import log from "ente-base/log";
import { t } from "i18next";
import { useEffect, useState } from "react";
import { editorFilterPresets } from "./ImageEditor.filters";
import {
    renderEditorCanvas,
    type EditorAdjustments,
} from "./ImageEditor.render";

export const ImageEditorFilters: React.FC<{
    fileURL: string | undefined;
    selected: string;
    adjustments: Omit<EditorAdjustments, "preset">;
    previewCanvasRef: React.RefObject<HTMLCanvasElement | null>;
    disabled: boolean;
    onSelect: (name: string) => void;
}> = ({
    fileURL,
    selected,
    adjustments: { brightness, contrast, saturation, blur, invert },
    previewCanvasRef,
    disabled,
    onSelect,
}) => {
    const [thumbnails, setThumbnails] = useState<string[]>([]);

    useEffect(() => {
        if (!fileURL) return;
        let cancelled = false;
        const image = new Image();
        let renderRevision = 0;
        const renderThumbnails = async () => {
            if (cancelled || !image.complete || !image.naturalWidth) return;
            const revision = ++renderRevision;
            const isCurrent = () => !cancelled && revision === renderRevision;
            try {
                const canvas = document.createElement("canvas");
                canvas.width = canvas.height = 96;
                const side = Math.min(image.width, image.height);
                const bounds =
                    previewCanvasRef.current?.getBoundingClientRect();
                const previewSide = bounds
                    ? Math.max(1, Math.min(bounds.width, bounds.height))
                    : 96;
                const thumbnails: string[] = [];
                for (const { name } of editorFilterPresets) {
                    await renderEditorCanvas(
                        canvas,
                        image,
                        {
                            preset: name,
                            brightness,
                            contrast,
                            saturation,
                            blur,
                            invert,
                        },
                        {
                            blurScale: 96 / previewSide,
                            sourceRect: {
                                x: (image.width - side) / 2,
                                y: (image.height - side) / 2,
                                width: side,
                                height: side,
                            },
                            isCurrent,
                        },
                    );
                    if (!isCurrent()) return;
                    thumbnails.push(canvas.toDataURL());
                }
                setThumbnails(thumbnails);
            } catch (e) {
                if (isCurrent())
                    log.error("Error rendering filter thumbnails", e);
            }
        };
        image.onload = () => void renderThumbnails();
        image.src = fileURL;
        const observer = new ResizeObserver(() => void renderThumbnails());
        if (previewCanvasRef.current)
            observer.observe(previewCanvasRef.current);
        return () => {
            cancelled = true;
            observer.disconnect();
        };
    }, [
        fileURL,
        brightness,
        contrast,
        saturation,
        blur,
        invert,
        previewCanvasRef,
    ]);

    return (
        <Box
            sx={{
                display: "grid",
                gridTemplateColumns: "repeat(3, minmax(0, 1fr))",
                gap: 1.5,
            }}
        >
            {editorFilterPresets.map(({ name }, index) => (
                <ButtonBase
                    key={name}
                    aria-pressed={selected === name}
                    disabled={disabled}
                    onClick={() => onSelect(name)}
                    sx={{
                        display: "flex",
                        flexDirection: "column",
                        gap: 0.75,
                        minWidth: 0,
                        p: 0.5,
                        borderRadius: 2,
                        "&.Mui-focusVisible": {
                            outline: "2px solid",
                            outlineColor: "accent.main",
                        },
                    }}
                >
                    <Box
                        sx={{
                            width: "100%",
                            aspectRatio: "1",
                            p: 0.5,
                            boxSizing: "border-box",
                            border: "2px solid",
                            borderColor:
                                selected === name
                                    ? "accent.main"
                                    : "transparent",
                            borderRadius: 3,
                        }}
                    >
                        <Box
                            component="img"
                            src={thumbnails[index]}
                            alt=""
                            sx={{
                                display: "block",
                                width: "100%",
                                height: "100%",
                                objectFit: "cover",
                                borderRadius: 2,
                                bgcolor: "secondary.main",
                            }}
                        />
                    </Box>
                    <Typography
                        variant="small"
                        sx={{
                            color:
                                selected === name ? "text.base" : "text.muted",
                            fontWeight: selected === name ? "bold" : "regular",
                        }}
                    >
                        {name === "None" ? t("none") : name}
                    </Typography>
                </ButtonBase>
            ))}
        </Box>
    );
};
