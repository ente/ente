import {
    Box,
    Button,
    FormControlLabel,
    MenuItem,
    Stack,
    Switch,
    TextField,
    Typography,
} from "@mui/material";
import { t } from "i18next";
import { useEffect, useRef, type RefObject } from "react";

import { drawEditorText, type EditorTextLayer } from "./ImageEditor.text";

export const EditorTextPreview = ({
    base,
    layers,
    onPlace,
}: {
    base: RefObject<HTMLCanvasElement | null>;
    layers: EditorTextLayer[];
    onPlace?: (x: number, y: number) => void;
}) => {
    const ref = useRef<HTMLCanvasElement>(null);
    useEffect(() => {
        const image = base.current;
        const overlay = ref.current;
        if (!image || !overlay) return;
        const draw = () => {
            overlay.width = image.width;
            overlay.height = image.height;
            const bounds = image.getBoundingClientRect();
            overlay.style.width = `${bounds.width}px`;
            overlay.style.height = `${bounds.height}px`;
            drawEditorText(overlay, layers);
        };
        draw();
        const observer = new ResizeObserver(draw);
        observer.observe(image);
        return () => observer.disconnect();
    }, [base, layers]);
    const place = (event: React.PointerEvent<HTMLCanvasElement>) => {
        const bounds = event.currentTarget.getBoundingClientRect();
        const clamp = (n: number) => Math.max(0, Math.min(1, n));
        onPlace?.(
            clamp((event.clientX - bounds.left) / bounds.width),
            clamp((event.clientY - bounds.top) / bounds.height),
        );
    };
    return (
        <canvas
            ref={ref}
            aria-hidden
            style={{
                position: "absolute",
                pointerEvents: onPlace ? "auto" : "none",
                cursor: onPlace ? "crosshair" : undefined,
                touchAction: "none",
            }}
            onPointerDown={(event) => {
                if (onPlace) {
                    event.currentTarget.setPointerCapture(event.pointerId);
                    place(event);
                }
            }}
            onPointerMove={(event) => {
                if (event.currentTarget.hasPointerCapture(event.pointerId))
                    place(event);
            }}
        />
    );
};

export const EditorTextMenu = ({
    layers,
    selected,
    select,
    update,
    add,
    remove,
}: {
    layers: EditorTextLayer[];
    selected: number;
    select: (index: number) => void;
    update: (patch: Partial<EditorTextLayer>) => void;
    add: () => void;
    remove: () => void;
}) => {
    const layer = layers[selected]!;
    return (
        <Stack spacing={2} sx={{ pt: 1 }}>
            {layers.length > 1 && (
                <TextField
                    select
                    label={t("text_layer")}
                    value={selected}
                    onChange={(e) => select(Number(e.target.value))}
                >
                    {layers.map((l, i) => (
                        <MenuItem key={i} value={i}>
                            {i + 1}. {l.text.trim() || t("text")}
                        </MenuItem>
                    ))}
                </TextField>
            )}
            <TextField
                multiline
                minRows={2}
                label={t("text")}
                onKeyDown={(event) => {
                    if (!event.altKey) return;
                    const step = 0.02;
                    const offset = {
                        ArrowUp: [0, -step],
                        ArrowDown: [0, step],
                        ArrowLeft: [-step, 0],
                        ArrowRight: [step, 0],
                    }[event.key];
                    if (!offset) return;
                    event.preventDefault();
                    update({
                        x: Math.max(0, Math.min(1, layer.x + offset[0]!)),
                        y: Math.max(0, Math.min(1, layer.y + offset[1]!)),
                    });
                }}
                value={layer.text}
                onChange={(e) => update({ text: e.target.value })}
            />
            <Typography variant="small">
                {t("editor_text_position_hint")}
            </Typography>
            <Stack direction="row" spacing={1}>
                <TextField
                    fullWidth
                    select
                    label={t("font")}
                    value={layer.font}
                    onChange={(e) =>
                        update({
                            font: e.target.value as EditorTextLayer["font"],
                        })
                    }
                >
                    {(["sans-serif", "serif", "monospace"] as const).map(
                        (font) => (
                            <MenuItem
                                key={font}
                                value={font}
                                sx={{ fontFamily: font }}
                            >
                                {t(font)}
                            </MenuItem>
                        ),
                    )}
                </TextField>
                <TextField
                    fullWidth
                    select
                    label={t("alignment")}
                    value={layer.align}
                    onChange={(e) =>
                        update({
                            align: e.target.value as EditorTextLayer["align"],
                        })
                    }
                >
                    {(["left", "center", "right"] as const).map((align) => (
                        <MenuItem key={align} value={align}>
                            {t(align)}
                        </MenuItem>
                    ))}
                </TextField>
            </Stack>
            <Box component="label">
                {t("text_size")}
                <input
                    style={{ width: "100%" }}
                    type="range"
                    min={2}
                    max={30}
                    value={layer.size}
                    onChange={(e) => update({ size: Number(e.target.value) })}
                />
            </Box>
            <Stack
                direction="row"
                sx={{ justifyContent: "space-between", alignItems: "center" }}
            >
                <Box component="label">
                    {t("text_color")}{" "}
                    <input
                        type="color"
                        value={layer.color}
                        onChange={(e) => update({ color: e.target.value })}
                    />
                </Box>
                <FormControlLabel
                    label={t("background")}
                    control={
                        <Switch
                            checked={layer.background}
                            onChange={(e) =>
                                update({ background: e.target.checked })
                            }
                        />
                    }
                />
            </Stack>
            <Stack direction="row" spacing={1}>
                <Button disabled={!layer.text.trim()} onClick={add}>
                    {t("add_text")}
                </Button>
                <Button
                    disabled={layers.length === 1 && !layer.text}
                    onClick={remove}
                >
                    {t("remove")}
                </Button>
            </Stack>
        </Stack>
    );
};
