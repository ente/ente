import { Box, ButtonBase, Typography } from "@mui/material";
import log from "ente-base/log";
import { t } from "i18next";
import { useEffect, useState } from "react";
import { applyEditorFilter, editorFilterPresets } from "./ImageEditor.filters";

export const ImageEditorFilters: React.FC<{
    fileURL: string | undefined;
    selected: string;
    disabled: boolean;
    onSelect: (name: string) => void;
}> = ({ fileURL, selected, disabled, onSelect }) => {
    const [thumbnails, setThumbnails] = useState<string[]>([]);

    useEffect(() => {
        if (!fileURL) return;
        let cancelled = false;
        const image = new Image();
        image.onload = () => {
            if (cancelled) return;
            try {
                const canvas = document.createElement("canvas");
                canvas.width = canvas.height = 96;
                const context = canvas.getContext("2d")!;
                const side = Math.min(image.width, image.height);
                setThumbnails(
                    editorFilterPresets.map(({ matrix }) => {
                        context.clearRect(0, 0, 96, 96);
                        context.drawImage(
                            image,
                            (image.width - side) / 2,
                            (image.height - side) / 2,
                            side,
                            side,
                            0,
                            0,
                            96,
                            96,
                        );
                        const pixels = context.getImageData(0, 0, 96, 96);
                        applyEditorFilter(pixels.data, matrix);
                        context.putImageData(pixels, 0, 0);
                        return canvas.toDataURL();
                    }),
                );
            } catch (e) {
                log.error("Error rendering filter thumbnails", e);
            }
        };
        image.src = fileURL;
        return () => {
            cancelled = true;
        };
    }, [fileURL]);

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
