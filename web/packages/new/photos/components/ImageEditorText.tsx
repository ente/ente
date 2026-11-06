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
    Dialog,
    IconButton,
    MenuItem,
    Select,
    Slider,
    Stack,
    TextField,
    Typography,
} from "@mui/material";
import { t } from "i18next";
import {
    useCallback,
    useEffect,
    useRef,
    useState,
    type RefObject,
} from "react";
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
const colors = [
    "#000000",
    "#ffffff",
    "#1877ff",
    "#ff3743",
    "#08b153",
    "#ff9e2c",
    "#ff59a4",
    "#00aaa4",
    "#9255d9",
];
const alignments = ["center", "left", "right"] as const;
const alignIcons = {
    center: <FormatAlignCenterIcon />,
    left: <FormatAlignLeftIcon />,
    right: <FormatAlignRightIcon />,
};
const control = {
    width: 48,
    height: 48,
    bgcolor: "secondary.main",
    flexShrink: 0,
    '&[aria-pressed="true"]': {
        color: "background.paper",
        bgcolor: "text.base",
    },
};
const bar = {
    width: "100%",
    maxWidth: 440,
    mx: "auto",
    gap: 0.5,
    alignItems: "center",
};

const TextComposer = ({
    initial,
    base,
    onCancel,
    onDone,
}: {
    initial: EditorTextLayer;
    base: RefObject<HTMLCanvasElement | null>;
    onCancel: () => void;
    onDone: (layer: EditorTextLayer) => void;
}) => {
    const [draft, setDraft] = useState(initial);
    const [background, setBackground] = useState(false);
    const [showHue, setShowHue] = useState(false);
    const [hue, setHue] = useState(180);
    const [imageUnit, setImageUnit] = useState(1);
    const color = background ? draft.backgroundColor : draft.color;
    const update = (patch: Partial<EditorTextLayer>) =>
        setDraft((current) => ({ ...current, ...patch }));
    const setColor = (value: string) =>
        update(background ? { backgroundColor: value } : { color: value });
    const showPhoto = useCallback(
        (snapshot: HTMLCanvasElement | null) => {
            const image = base.current;
            if (!image || !snapshot) return;
            snapshot.width = image.width;
            snapshot.height = image.height;
            snapshot.getContext("2d")!.drawImage(image, 0, 0);
            const scale = Math.min(
                snapshot.clientWidth / image.width,
                snapshot.clientHeight / image.height,
            );
            setImageUnit(
                Math.max(1, Math.min(image.width, image.height) * scale),
            );
        },
        [base],
    );
    return (
        <Dialog fullScreen open onClose={onCancel} aria-label={t("add_text")}>
            <Stack sx={{ height: "100%", bgcolor: "background.paper" }}>
                <Stack
                    direction="row"
                    sx={{
                        px: 2,
                        minHeight: 56,
                        alignItems: "center",
                        justifyContent: "space-between",
                    }}
                >
                    <Button variant="text" onClick={onCancel}>
                        {t("cancel")}
                    </Button>
                    <Button
                        color="accent"
                        variant="text"
                        disabled={!draft.text.trim()}
                        onClick={() =>
                            onDone({
                                ...draft,
                                size: draft.size || 24 / imageUnit,
                            })
                        }
                    >
                        {t("done")}
                    </Button>
                </Stack>
                <Box
                    sx={{
                        position: "relative",
                        flex: 1,
                        minHeight: 0,
                        display: "grid",
                        placeItems: "center",
                        containerType: "size",
                    }}
                >
                    <canvas
                        ref={showPhoto}
                        style={{
                            width: `min(100cqw, ${(100 * mobileTextFrame.width) / mobileTextFrame.height}cqh, ${mobileTextFrame.logicalWidth}px)`,
                            height: "auto",
                            aspectRatio: `${mobileTextFrame.width} / ${mobileTextFrame.height}`,
                            objectFit: "contain",
                            position: "absolute",
                        }}
                    />
                    <Box
                        sx={{
                            position: "absolute",
                            inset: 0,
                            bgcolor: "rgba(0, 0, 0, 0.42)",
                        }}
                    />
                    <Box
                        component="textarea"
                        autoFocus
                        aria-label={t("text")}
                        placeholder={t("enter_text")}
                        value={draft.text}
                        onChange={(e) => update({ text: e.target.value })}
                        sx={{
                            position: "absolute",
                            top: "12%",
                            width: "fit-content",
                            maxWidth: "95%",
                            minWidth: "5ch",
                            maxHeight: "80%",
                            fieldSizing: "content",
                            border: 0,
                            outline: 0,
                            resize: "none",
                            borderRadius: "6px",
                            px: 1,
                            py: 0.25,
                            backgroundColor: draft.text
                                ? `color-mix(in srgb, ${draft.backgroundColor} ${draft.opacity * 100}%, transparent)`
                                : "transparent",
                            color: draft.color,
                            font: textFont(
                                draft,
                                draft.size ? draft.size * imageUnit : 24,
                            ),
                            textAlign: draft.align,
                            "&::placeholder": { color: "#fff", opacity: 0.7 },
                        }}
                    />
                </Box>
                <Stack
                    spacing={1}
                    sx={{ p: 1, pb: "max(8px, env(safe-area-inset-bottom))" }}
                >
                    <Stack direction="row" sx={bar}>
                        <Select
                            size="small"
                            value={draft.font}
                            inputProps={{ "aria-label": t("font") }}
                            onChange={(e) => update({ font: e.target.value })}
                            sx={{
                                borderRadius: 24,
                                bgcolor: "secondary.main",
                                height: 48,
                                minWidth: 0,
                                mr: "auto",
                                "& fieldset": { border: 0 },
                            }}
                        >
                            {fonts.map((font) => (
                                <MenuItem
                                    key={font}
                                    value={font}
                                    sx={{
                                        font: textFont({ ...draft, font }, 16),
                                    }}
                                >
                                    {font}
                                </MenuItem>
                            ))}
                        </Select>
                        <IconButton
                            sx={control}
                            title={t("bold")}
                            aria-label={t("bold")}
                            aria-pressed={draft.bold}
                            onClick={() => update({ bold: !draft.bold })}
                        >
                            <FormatBoldIcon />
                        </IconButton>
                        <IconButton
                            sx={control}
                            title={t("italic")}
                            aria-label={t("italic")}
                            aria-pressed={draft.italic}
                            onClick={() => update({ italic: !draft.italic })}
                        >
                            <FormatItalicIcon />
                        </IconButton>
                        <IconButton
                            sx={control}
                            aria-label={t("alignment") + ": " + t(draft.align)}
                            onClick={() =>
                                update({
                                    align: alignments[
                                        (alignments.indexOf(draft.align) + 1) %
                                            3
                                    ]!,
                                })
                            }
                        >
                            {alignIcons[draft.align]}
                        </IconButton>
                        <IconButton
                            sx={control}
                            aria-label={`${t("background")}: ${Math.round(100 * draft.opacity)}%`}
                            onClick={() => {
                                const opacity =
                                    draft.opacity === 1
                                        ? 0.5
                                        : draft.opacity === 0.5
                                          ? 0
                                          : 1;
                                update({ opacity });
                                if (!opacity) setBackground(false);
                            }}
                        >
                            Aa
                        </IconButton>
                    </Stack>
                    <Stack direction="row" sx={bar}>
                        <Stack
                            direction="row"
                            sx={{ bgcolor: "secondary.main", borderRadius: 24 }}
                        >
                            <IconButton
                                sx={control}
                                aria-label={t("text_color")}
                                aria-pressed={!background}
                                onClick={() => setBackground(false)}
                            >
                                <FormatColorTextIcon />
                            </IconButton>
                            <IconButton
                                sx={control}
                                aria-label={t("background_color")}
                                aria-pressed={background}
                                onClick={() => {
                                    setBackground(true);
                                    if (!draft.opacity) update({ opacity: 1 });
                                }}
                            >
                                <FormatColorFillIcon />
                            </IconButton>
                        </Stack>
                        {showHue ? (
                            <Slider
                                aria-label={t("hue")}
                                value={hue}
                                max={360}
                                onChange={(_, v) => {
                                    const h = v;
                                    setHue(h);
                                    setColor(`hsl(${h} 100% 50%)`);
                                }}
                                sx={{
                                    flex: 1,
                                    minWidth: 0,
                                    mx: 1,
                                    color,
                                    "& .MuiSlider-track": { display: "none" },
                                    "& .MuiSlider-rail": {
                                        opacity: 1,
                                        background:
                                            "linear-gradient(90deg, red, yellow, lime, cyan, blue, magenta, red)",
                                    },
                                }}
                            />
                        ) : (
                            <Stack
                                direction="row"
                                sx={{
                                    flex: 1,
                                    alignItems: "center",
                                    height: 48,
                                    bgcolor: "secondary.main",
                                    borderRadius: 24,
                                    px: 1,
                                    gap: 1,
                                    overflowX: "auto",
                                    scrollbarWidth: "none",
                                }}
                            >
                                {colors.map((c) => (
                                    <IconButton
                                        key={c}
                                        aria-label={c}
                                        aria-pressed={color === c}
                                        onClick={() => setColor(c)}
                                        sx={{
                                            width: 26,
                                            height: 26,
                                            p: 0,
                                            flexShrink: 0,
                                            border:
                                                color === c
                                                    ? "2px solid currentColor"
                                                    : 0,
                                        }}
                                    >
                                        <Box
                                            sx={{
                                                width: 20,
                                                height: 20,
                                                bgcolor: c,
                                                borderRadius: "50%",
                                            }}
                                        />
                                    </IconButton>
                                ))}
                            </Stack>
                        )}
                        <IconButton
                            sx={control}
                            aria-label={t("hue")}
                            aria-pressed={showHue}
                            onClick={() => setShowHue(!showHue)}
                        >
                            <PaletteIcon />
                        </IconButton>
                    </Stack>
                </Stack>
            </Stack>
        </Dialog>
    );
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
    const [mode, setMode] = useState<"edit" | "add" | undefined>(() =>
        layer.text ? undefined : "edit",
    );
    const bounds = base.current?.getBoundingClientRect();
    const unit = Math.max(1, Math.min(bounds?.width ?? 1, bounds?.height ?? 1));
    const size = layer.size ? layer.size * unit : 24;
    return (
        <Stack spacing={1.5} sx={{ pt: 1 }}>
            {layers.length > 1 && (
                <TextField
                    select
                    label={t("text_layer")}
                    value={selected}
                    onChange={(e) => select(Number(e.target.value))}
                >
                    {layers.map((l, i) => (
                        <MenuItem key={i} value={i}>
                            {i + 1}. {l.text}
                        </MenuItem>
                    ))}
                </TextField>
            )}
            <Button
                variant="contained"
                color="secondary"
                onClick={() => setMode("edit")}
            >
                {layer.text || t("add_text")}
            </Button>
            {layer.text && (
                <>
                    <Typography variant="small">
                        {t("editor_text_position_hint")}
                    </Typography>
                    <Box component="label">
                        {t("text_size")}
                        <Slider
                            aria-label={t("text_size")}
                            min={7.2}
                            max={Math.max(72, size)}
                            step={0.1}
                            value={size}
                            onChange={(_, v) => update({ size: v / unit })}
                        />
                    </Box>
                    <Stack direction="row">
                        <Button onClick={() => setMode("add")}>
                            {t("add_text")}
                        </Button>
                        <Button onClick={remove}>{t("remove")}</Button>
                    </Stack>
                </>
            )}
            {mode && (
                <TextComposer
                    base={base}
                    initial={mode === "add" ? newTextLayer() : layer}
                    onCancel={() => setMode(undefined)}
                    onDone={(draft) => {
                        if (mode === "add") add(draft);
                        else update(draft);
                        setMode(undefined);
                    }}
                />
            )}
        </Stack>
    );
};
