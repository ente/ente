import AddIcon from "@mui/icons-material/Add";
import DeleteOutlinedIcon from "@mui/icons-material/DeleteOutlined";
import FormatAlignCenterIcon from "@mui/icons-material/FormatAlignCenter";
import FormatAlignLeftIcon from "@mui/icons-material/FormatAlignLeft";
import FormatAlignRightIcon from "@mui/icons-material/FormatAlignRight";
import FormatBoldIcon from "@mui/icons-material/FormatBold";
import FormatColorFillIcon from "@mui/icons-material/FormatColorFill";
import FormatColorTextIcon from "@mui/icons-material/FormatColorText";
import FormatItalicIcon from "@mui/icons-material/FormatItalic";
import PaletteIcon from "@mui/icons-material/Palette";
import {
    Box,
    Button,
    IconButton,
    MenuItem,
    Slider,
    Stack,
    TextField,
    Typography,
} from "@mui/material";
import { t } from "i18next";
import { useEffect, useRef, useState, type RefObject } from "react";
import {
    drawEditorText,
    loadTextFonts,
    mobileTextFrame,
    newTextLayer,
    textFont,
    type EditorTextLayer,
} from "./ImageEditor.text";

export const EditorTextPreview = ({
    base,
    layers,
    onPlace,
    selected,
}: {
    base: RefObject<HTMLCanvasElement | null>;
    layers: EditorTextLayer[];
    selected: number;
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
        let active = true;
        void loadTextFonts(layers).then(() => {
            if (active) draw();
        });
        const observer = new ResizeObserver(draw);
        observer.observe(image);
        return () => {
            active = false;
            observer.disconnect();
        };
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
            aria-hidden={!onPlace}
            aria-label={onPlace ? t("text_position") : undefined}
            tabIndex={onPlace ? 0 : undefined}
            onKeyDown={(event) => {
                const delta = {
                    ArrowUp: [0, -0.02],
                    ArrowDown: [0, 0.02],
                    ArrowLeft: [-0.02, 0],
                    ArrowRight: [0.02, 0],
                }[event.key];
                if (!delta || !onPlace) return;
                event.preventDefault();
                const layer = layers[selected]!;
                onPlace(
                    Math.max(0, Math.min(1, layer.x + delta[0]!)),
                    Math.max(0, Math.min(1, layer.y + delta[1]!)),
                );
            }}
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

const fonts = ["Inter", "Outfit", "Gochi Hand"] as const;
const swatchHues: Record<string, number> = {
    "#000000": 0,
    "#ffffff": 0,
    "#1877ff": 215,
    "#ff3743": 355,
    "#08b153": 146,
    "#ff9e2c": 32,
    "#ff59a4": 333,
    "#00aaa4": 178,
    "#9255d9": 269,
};
const alignIcons = {
    center: <FormatAlignCenterIcon />,
    left: <FormatAlignLeftIcon />,
    right: <FormatAlignRightIcon />,
};
const control = {
    width: 36,
    height: 36,
    borderRadius: "10px",
    bgcolor: "secondary.main",
    '&[aria-pressed="true"]': { color: "accent.main", bgcolor: "fill.faint" },
};

export const EditorTextMenu = ({
    layers,
    selected,
    select,
    update,
    add,
    remove,
    base,
}: {
    layers: EditorTextLayer[];
    selected: number;
    select: (index: number) => void;
    update: (patch: Partial<EditorTextLayer>) => void;
    add: (layer: EditorTextLayer) => void;
    remove: () => void;
    base: RefObject<HTMLCanvasElement | null>;
}) => {
    const layer = layers[selected]!;
    const input = useRef<HTMLTextAreaElement>(null);
    const [background, setBackground] = useState(false);
    const [showHue, setShowHue] = useState(false);
    // Express font size in the reference frame's logical pixels so resizing
    // the web sidebar or canvas doesn't affect caption size on export.
    const image = base.current;
    const scale = image
        ? Math.min(
              mobileTextFrame.logicalWidth / image.width,
              (mobileTextFrame.logicalWidth * mobileTextFrame.height) /
                  mobileTextFrame.width /
                  image.height,
          )
        : 1;
    const unit = image ? Math.min(image.width, image.height) * scale : 1;
    const size = layer.size ? layer.size * unit : 24;
    const color = background ? layer.backgroundColor : layer.color;
    const setColor = (value: string) =>
        update(
            background
                ? { backgroundColor: value, opacity: layer.opacity || 1 }
                : { color: value },
        );
    const hue = color.startsWith("hsl(")
        ? parseFloat(color.slice(4))
        : (swatchHues[color] ?? 0);
    return (
        <Stack spacing={2} sx={{ pt: 1 }}>
            {layers.length > 1 && (
                <TextField
                    select
                    size="small"
                    label={t("text_layer")}
                    value={selected}
                    onChange={(e) => select(Number(e.target.value))}
                >
                    {layers.map((l, i) => (
                        <MenuItem key={i} value={i}>
                            {i + 1}. {l.text || t("text")}
                        </MenuItem>
                    ))}
                </TextField>
            )}
            <TextField
                autoFocus
                inputRef={input}
                multiline
                minRows={2}
                maxRows={5}
                label={t("text")}
                placeholder={t("enter_text")}
                value={layer.text}
                onChange={(e) =>
                    update({
                        text: e.target.value,
                        size: layer.size || 24 / unit,
                    })
                }
            />
            <Stack direction="row" spacing={1} sx={{ alignItems: "center" }}>
                <TextField
                    select
                    size="small"
                    label={t("font")}
                    value={layer.font}
                    sx={{ flex: 1 }}
                    onChange={(e) =>
                        update({
                            font: e.target.value as EditorTextLayer["font"],
                        })
                    }
                >
                    {fonts.map((font) => (
                        <MenuItem
                            key={font}
                            value={font}
                            sx={{ font: textFont({ ...layer, font }, 16) }}
                        >
                            {font}
                        </MenuItem>
                    ))}
                </TextField>
                <IconButton
                    sx={control}
                    title={t("bold")}
                    aria-label={t("bold")}
                    aria-pressed={layer.bold}
                    onClick={() => update({ bold: !layer.bold })}
                >
                    <FormatBoldIcon />
                </IconButton>
                <IconButton
                    sx={control}
                    title={t("italic")}
                    aria-label={t("italic")}
                    aria-pressed={layer.italic}
                    onClick={() => update({ italic: !layer.italic })}
                >
                    <FormatItalicIcon />
                </IconButton>
            </Stack>
            <Stack
                direction="row"
                sx={{ alignItems: "center", justifyContent: "space-between" }}
            >
                <Typography variant="small">{t("alignment")}</Typography>
                <Stack direction="row" spacing={0.5}>
                    {(["left", "center", "right"] as const).map((align) => (
                        <IconButton
                            key={align}
                            title={t(align)}
                            aria-label={t(align)}
                            aria-pressed={layer.align === align}
                            sx={control}
                            onClick={() => update({ align })}
                        >
                            {alignIcons[align]}
                        </IconButton>
                    ))}
                </Stack>
            </Stack>
            <Box>
                <Stack
                    direction="row"
                    sx={{
                        alignItems: "center",
                        justifyContent: "space-between",
                    }}
                >
                    <Typography variant="small">{t("text_size")}</Typography>
                    <Typography variant="small">
                        {Math.round(size)} px
                    </Typography>
                </Stack>
                <Slider
                    aria-label={t("text_size")}
                    min={7.2}
                    max={Math.max(72, size)}
                    step={0.1}
                    value={size}
                    onChange={(_, v) => update({ size: v / unit })}
                />
            </Box>
            <Stack direction="row" spacing={1}>
                <Button
                    variant="text"
                    sx={{
                        flex: 1,
                        color: "text.muted",
                        borderRadius: "10px",
                        '&[aria-pressed="true"]': {
                            color: "text.base",
                            bgcolor: "secondary.main",
                        },
                    }}
                    startIcon={<FormatColorTextIcon />}
                    aria-pressed={!background}
                    onClick={() => setBackground(false)}
                >
                    {t("text_color")}
                </Button>
                <Button
                    variant="text"
                    sx={{
                        flex: 1,
                        color: "text.muted",
                        borderRadius: "10px",
                        '&[aria-pressed="true"]': {
                            color: "text.base",
                            bgcolor: "secondary.main",
                        },
                    }}
                    startIcon={<FormatColorFillIcon />}
                    aria-pressed={background}
                    onClick={() => setBackground(true)}
                >
                    {t("background")}
                </Button>
            </Stack>
            <Stack
                direction="row"
                sx={{ flexWrap: "wrap", alignItems: "center", gap: 0.5 }}
            >
                {Object.keys(swatchHues).map((c) => (
                    <IconButton
                        key={c}
                        aria-label={c}
                        aria-pressed={color === c}
                        onClick={() => setColor(c)}
                        sx={{
                            width: 26,
                            height: 26,
                            p: 0,
                            border: color === c ? "2px solid currentColor" : 0,
                        }}
                    >
                        <Box
                            sx={{
                                width: 19,
                                height: 19,
                                bgcolor: c,
                                borderRadius: "50%",
                                border: "1px solid",
                                borderColor: "divider",
                            }}
                        />
                    </IconButton>
                ))}
                <IconButton
                    sx={control}
                    title={t("hue")}
                    aria-label={t("hue")}
                    aria-pressed={showHue}
                    onClick={() => setShowHue(!showHue)}
                >
                    <PaletteIcon fontSize="small" />
                </IconButton>
            </Stack>
            {showHue && (
                <Slider
                    aria-label={t("hue")}
                    value={hue}
                    max={360}
                    onChange={(_, v) => setColor(`hsl(${v} 100% 50%)`)}
                    sx={{
                        color,
                        "& .MuiSlider-track": { display: "none" },
                        "& .MuiSlider-rail": {
                            opacity: 1,
                            background:
                                "linear-gradient(90deg, red, yellow, lime, cyan, blue, magenta, red)",
                        },
                    }}
                />
            )}
            {background && (
                <TextField
                    select
                    size="small"
                    label={t("background_opacity")}
                    value={layer.opacity}
                    onChange={(e) =>
                        update({
                            opacity: Number(
                                e.target.value,
                            ) as EditorTextLayer["opacity"],
                        })
                    }
                >
                    {([0, 0.5, 1] as const).map((opacity) => (
                        <MenuItem key={opacity} value={opacity}>
                            {opacity * 100}%
                        </MenuItem>
                    ))}
                </TextField>
            )}
            <Typography variant="small" color="text.muted">
                {t("editor_text_position_hint")}
            </Typography>
            <Stack direction="row" spacing={1}>
                <Button
                    variant="outlined"
                    disabled={!layer.text.trim()}
                    startIcon={<AddIcon />}
                    onClick={() => {
                        add(newTextLayer());
                        input.current?.focus();
                    }}
                >
                    {t("add_text")}
                </Button>
                <IconButton
                    title={t("remove")}
                    aria-label={t("remove")}
                    disabled={layers.length === 1 && !layer.text}
                    onClick={remove}
                >
                    <DeleteOutlinedIcon />
                </IconButton>
            </Stack>
        </Stack>
    );
};
