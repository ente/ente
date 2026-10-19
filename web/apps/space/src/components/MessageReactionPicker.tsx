import { Add01Icon, Search01Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { Box, Dialog, Popover, useMediaQuery } from "@mui/material";
import { keyframes } from "@mui/material/styles";
import { SpaceBottomSheetTransition } from "components/BottomSheetTransition";
import {
    emojiName,
    emojiWithSkinTone,
    quickReactionEmojis,
    searchEmojis,
    spaceEmojis,
    type SpaceEmoji,
} from "data/emojis";
import { useBrowserBackClose } from "hooks/use-browser-back-close";
import React from "react";
import {
    spaceControlBackground,
    spaceDialogBackground,
    spaceMenuBackground,
    spaceMenuHover,
    spaceSurface,
    spaceSurfaceHover,
    spaceText,
    spaceTextMuted,
} from "styles/colors";

const emojiFont =
    '"Apple Color Emoji", "Segoe UI Emoji", "Noto Color Emoji", sans-serif';
const pickerEnter = keyframes`
    from { opacity: 0; scale: 0.94; }
    70% { opacity: 1; scale: 1.015; }
    to { opacity: 1; scale: 1; }
`;
const buttonSx = {
    alignItems: "center",
    appearance: "none",
    bgcolor: "transparent",
    border: 0,
    borderRadius: "12px",
    color: spaceText,
    cursor: "pointer",
    display: "flex",
    flexShrink: 0,
    fontFamily: emojiFont,
    fontSize: 26,
    height: 40,
    justifyContent: "center",
    lineHeight: 1,
    p: 0,
    width: 40,
    transition: "transform 160ms cubic-bezier(0.2, 0.8, 0.2, 1)",
    "&:hover, &[aria-pressed=true]": { bgcolor: spaceMenuHover },
    "@media (hover: hover)": {
        "&:hover": { transform: "translateY(-2px) scale(1.12)" },
    },
    "&:active": { transform: "scale(0.9)" },
    "&:focus-visible": {
        outline: `2px solid ${spaceTextMuted}`,
        outlineOffset: -2,
    },
    "@media (prefers-reduced-motion: reduce)": {
        transition: "none",
        "&:hover, &:active": { transform: "none" },
    },
};

export const MessageQuickReactions: React.FC<{
    selected?: string;
    onSelect: (emoji: string) => void;
    onMore: () => void;
}> = ({ selected, onSelect, onMore }) => {
    const groupRef = React.useRef<HTMLDivElement>(null);
    React.useEffect(() => {
        groupRef.current?.focus({ preventScroll: true });
    }, []);

    return (
        <Box
            ref={groupRef}
            role="group"
            aria-label="React to message"
            tabIndex={-1}
            sx={{
                bgcolor: spaceMenuBackground,
                borderRadius: "999px",
                boxShadow:
                    "0 0 0 1px rgba(255, 255, 255, 0.08), 0 8px 24px rgba(0, 0, 0, 0.32)",
                boxSizing: "border-box",
                display: "flex",
                gap: "2px",
                maxWidth: "calc(100vw - 16px)",
                outline: 0,
                p: "5px",
                "& > button": {
                    transition: "none",
                    "&:hover, &:active": { transform: "none" },
                },
            }}
        >
            {quickReactionEmojis(selected).map((emoji) => {
                const name = emojiName(emoji);
                const label =
                    selected == emoji ? `Remove ${name} reaction` : name;
                return (
                    <Box
                        key={emoji}
                        component="button"
                        type="button"
                        aria-label={label}
                        aria-pressed={selected == emoji}
                        title={label}
                        onClick={() => onSelect(emoji)}
                        sx={{
                            ...buttonSx,
                            borderRadius: "50%",
                            flexShrink: 1,
                            fontSize: 25,
                            height: 41,
                            pt: "2px",
                            width: 41,
                        }}
                    >
                        {emoji}
                    </Box>
                );
            })}
            <Box
                component="button"
                type="button"
                aria-label="More reactions"
                title="More reactions"
                onClick={onMore}
                sx={{
                    ...buttonSx,
                    bgcolor: spaceControlBackground,
                    borderRadius: "50%",
                    flexShrink: 1,
                    height: 41,
                    width: 41,
                }}
            >
                <HugeiconsIcon icon={Add01Icon} size={22} strokeWidth={1.8} />
            </Box>
        </Box>
    );
};

const skinTones = [
    { tone: "", name: "Default" },
    { tone: "🏻", name: "Light" },
    { tone: "🏼", name: "Medium light" },
    { tone: "🏽", name: "Medium" },
    { tone: "🏾", name: "Medium dark" },
    { tone: "🏿", name: "Dark" },
];
const tonePickerWidth = skinTones.length * 40 + 8;

export const MessageReactionPicker: React.FC<{
    selected?: string;
    onSelect: (emoji: string) => void;
    onClose: () => void;
}> = ({ selected, onSelect, onClose }) => {
    const isBottomSheet = useMediaQuery("(max-width: 599px)");
    const prefersReducedMotion = useMediaQuery(
        "(prefers-reduced-motion: reduce)",
    );
    const resultsID = React.useId();
    const [open, setOpen] = React.useState(true);
    useBrowserBackClose({
        open,
        onClose: () => setOpen(false),
        stateKey: "space-message-reaction-picker",
    });
    const [query, setQuery] = React.useState("");
    const [tonePicker, setTonePicker] = React.useState<{
        entry: SpaceEmoji;
        position: { top: number; left: number };
    } | null>(null);
    const tone = selected?.match(/[\u{1F3FB}-\u{1F3FF}]/u)?.[0] ?? "";
    const [focusedIndex, setFocusedIndex] = React.useState(0);
    const gridRef = React.useRef<HTMLDivElement>(null);
    const dragStartY = React.useRef<number | undefined>(undefined);
    const wasDragged = React.useRef(false);
    const [isDragging, setIsDragging] = React.useState(false);
    const [dragOffset, setDragOffset] = React.useState(0);
    const entries = query.trim()
        ? searchEmojis(spaceEmojis, query)
        : spaceEmojis;

    const select = (entry: SpaceEmoji, selectedTone = tone) => {
        onSelect(emojiWithSkinTone(entry, selectedTone));
        setOpen(false);
    };

    const navigate = (event: React.KeyboardEvent<HTMLDivElement>) => {
        const grid = gridRef.current;
        if (!grid) return;
        const columns =
            getComputedStyle(grid).gridTemplateColumns.split(" ").length;
        const offsets: Record<string, number> = {
            ArrowLeft: -1,
            ArrowRight: 1,
            ArrowUp: -columns,
            ArrowDown: columns,
            Home: -focusedIndex,
            End: entries.length - 1 - focusedIndex,
        };
        const offset = offsets[event.key];
        if (offset == undefined) return;
        event.preventDefault();
        const next = Math.max(
            0,
            Math.min(entries.length - 1, focusedIndex + offset),
        );
        setFocusedIndex(next);
        grid.querySelectorAll<HTMLButtonElement>("button")[next]?.focus();
    };

    return (
        <Dialog
            open={open}
            onClose={() => setOpen(false)}
            maxWidth={false}
            slots={
                isBottomSheet && !prefersReducedMotion
                    ? { transition: SpaceBottomSheetTransition }
                    : undefined
            }
            transitionDuration={prefersReducedMotion ? 0 : undefined}
            sx={{ zIndex: 1500 }}
            slotProps={{
                paper: {
                    "aria-label": "React to message",
                    style: {
                        translate: `0 ${dragOffset}px`,
                        transition:
                            isDragging || prefersReducedMotion
                                ? "none"
                                : "translate 160ms ease-out",
                    },
                    sx: {
                        bgcolor: spaceDialogBackground,
                        borderRadius: "28px 28px 0 0",
                        bottom: 0,
                        boxShadow: "none",
                        boxSizing: "border-box",
                        display: "flex",
                        flexDirection: "column",
                        height: "min(340px, 50dvh)",
                        left: 0,
                        m: 0,
                        maxHeight: "calc(100dvh - 16px)",
                        maxWidth: "none",
                        overflow: "hidden",
                        p: "0 16px max(16px, env(safe-area-inset-bottom))",
                        position: "fixed",
                        width: "100vw",
                        animation: open
                            ? `${pickerEnter} 280ms ease-out`
                            : "none",
                        transformOrigin: "bottom center",
                        "@media (prefers-reduced-motion: reduce)": {
                            animation: "none",
                        },
                        "@media (min-width: 600px)": {
                            borderRadius: "20px",
                            bottom: "auto",
                            left: "50%",
                            p: "0 20px 20px",
                            top: "50%",
                            transform: "translate(-50%, -50%)",
                            transformOrigin: "center",
                            width: 420,
                        },
                    },
                },
                transition: { onExited: onClose },
            }}
        >
            <Box
                component="button"
                type="button"
                aria-label="Dismiss emoji picker"
                onClick={(event: React.MouseEvent<HTMLButtonElement>) => {
                    if (event.detail == 0 || !wasDragged.current)
                        setOpen(false);
                    wasDragged.current = false;
                }}
                onPointerDown={(
                    event: React.PointerEvent<HTMLButtonElement>,
                ) => {
                    if (event.button != 0) return;
                    dragStartY.current = event.clientY;
                    wasDragged.current = false;
                    setIsDragging(true);
                    event.currentTarget.setPointerCapture(event.pointerId);
                }}
                onPointerMove={(
                    event: React.PointerEvent<HTMLButtonElement>,
                ) => {
                    if (dragStartY.current == undefined) return;
                    const distance = event.clientY - dragStartY.current;
                    if (Math.abs(distance) > 4) wasDragged.current = true;
                    setDragOffset(Math.max(0, distance));
                }}
                onPointerUp={(event: React.PointerEvent<HTMLButtonElement>) => {
                    if (dragStartY.current == undefined) return;
                    const distance = event.clientY - dragStartY.current;
                    dragStartY.current = undefined;
                    setIsDragging(false);
                    if (distance > 80) setOpen(false);
                    else setDragOffset(0);
                }}
                onPointerCancel={() => {
                    dragStartY.current = undefined;
                    wasDragged.current = true;
                    setIsDragging(false);
                    setDragOffset(0);
                }}
                sx={{
                    ...buttonSx,
                    borderRadius: "999px",
                    cursor: isDragging ? "grabbing" : "grab",
                    height: 32,
                    touchAction: "none",
                    width: "100%",
                    "&:hover": { bgcolor: "transparent" },
                    "@media (hover: hover)": {
                        "&:hover": { transform: "none" },
                    },
                    "&:active": { transform: "none" },
                }}
            >
                <Box
                    component="span"
                    sx={{
                        bgcolor: "#686868",
                        borderRadius: "999px",
                        height: 4,
                        width: 32,
                    }}
                />
            </Box>
            <Box
                sx={{
                    alignItems: "center",
                    bgcolor: spaceSurface,
                    borderRadius: "12px",
                    display: "flex",
                    flexShrink: 0,
                    gap: "8px",
                    mb: "12px",
                    px: "12px",
                }}
            >
                <HugeiconsIcon
                    icon={Search01Icon}
                    size={16}
                    color={spaceTextMuted}
                />
                <Box
                    component="input"
                    type="search"
                    aria-label="Search emojis"
                    aria-controls={resultsID}
                    autoFocus={!isBottomSheet}
                    placeholder="Search"
                    value={query}
                    onChange={(event: React.ChangeEvent<HTMLInputElement>) => {
                        setQuery(event.target.value);
                        setFocusedIndex(0);
                        gridRef.current?.scrollTo({ top: 0 });
                    }}
                    sx={{
                        bgcolor: "transparent",
                        border: 0,
                        color: spaceText,
                        fontFamily: "inherit",
                        fontSize: 14,
                        height: 40,
                        minWidth: 0,
                        outline: 0,
                        width: "100%",
                        "&::placeholder": { color: spaceTextMuted, opacity: 1 },
                    }}
                />
            </Box>
            <Box
                id={resultsID}
                ref={gridRef}
                role="group"
                aria-label={query.trim() ? "Emoji search results" : "Emojis"}
                onKeyDown={navigate}
                sx={{
                    alignContent: "start",
                    display: "grid",
                    gap: "4px",
                    gridTemplateColumns: "repeat(auto-fill, minmax(38px, 1fr))",
                    minHeight: 0,
                    overflowY: "auto",
                    overscrollBehavior: "contain",
                    p: "2px",
                }}
            >
                {entries.map((entry, index) => {
                    const emoji = emojiWithSkinTone(entry, tone);
                    return (
                        <Box
                            key={entry.emoji}
                            component="button"
                            type="button"
                            aria-label={entry.name}
                            aria-pressed={selected == emoji}
                            aria-haspopup={
                                entry.skinTone ? "dialog" : undefined
                            }
                            aria-expanded={
                                entry.skinTone
                                    ? tonePicker?.entry.emoji == entry.emoji
                                    : undefined
                            }
                            tabIndex={index == focusedIndex ? 0 : -1}
                            title={entry.name}
                            onFocus={() => setFocusedIndex(index)}
                            onClick={(
                                event: React.MouseEvent<HTMLButtonElement>,
                            ) => {
                                if (entry.skinTone) {
                                    const anchor =
                                        event.currentTarget.getBoundingClientRect();
                                    const grid =
                                        gridRef.current!.getBoundingClientRect();
                                    setTonePicker({
                                        entry,
                                        position: {
                                            top: anchor.top,
                                            left: Math.max(
                                                grid.left + tonePickerWidth / 2,
                                                Math.min(
                                                    grid.right -
                                                        tonePickerWidth / 2,
                                                    anchor.left +
                                                        anchor.width / 2,
                                                ),
                                            ),
                                        },
                                    });
                                } else select(entry);
                            }}
                            sx={{
                                ...buttonSx,
                                height: 42,
                                position: "relative",
                                width: "100%",
                            }}
                        >
                            {emoji}
                            {entry.skinTone && (
                                <Box
                                    component="span"
                                    aria-hidden
                                    sx={{
                                        borderRight: `5px solid ${spaceTextMuted}`,
                                        borderTop: "5px solid transparent",
                                        bottom: 5,
                                        position: "absolute",
                                        right: 5,
                                    }}
                                />
                            )}
                        </Box>
                    );
                })}
                {!entries.length && (
                    <Box
                        role="status"
                        sx={{
                            color: spaceTextMuted,
                            fontSize: 14,
                            gridColumn: "1 / -1",
                            py: "36px",
                            textAlign: "center",
                        }}
                    >
                        No emojis found. Try another search.
                    </Box>
                )}
            </Box>
            <Popover
                open={open && Boolean(tonePicker)}
                anchorReference="anchorPosition"
                anchorPosition={tonePicker?.position}
                onClose={() => setTonePicker(null)}
                transformOrigin={{ vertical: "bottom", horizontal: "center" }}
                transitionDuration={prefersReducedMotion ? 0 : "auto"}
                sx={{ zIndex: 1501 }}
                slotProps={{
                    paper: {
                        role: "dialog",
                        "aria-label": `Skin tones for ${tonePicker?.entry.name ?? "emoji"}`,
                        sx: {
                            bgcolor: spaceSurfaceHover,
                            backgroundImage: "none",
                            borderRadius: "999px",
                            boxShadow: "0 8px 24px rgba(0, 0, 0, 0.3)",
                            display: "flex",
                            p: "4px",
                            width: tonePickerWidth,
                        },
                    },
                }}
            >
                {tonePicker &&
                    skinTones.map((item, index) => {
                        const emoji = emojiWithSkinTone(
                            tonePicker.entry,
                            item.tone,
                        );
                        return (
                            <Box
                                key={item.tone}
                                component="button"
                                type="button"
                                autoFocus={item.tone == tone}
                                aria-label={`${tonePicker.entry.name}: ${item.name.toLowerCase()} skin tone`}
                                aria-pressed={selected == emoji}
                                onClick={() =>
                                    select(tonePicker.entry, item.tone)
                                }
                                onKeyDown={(
                                    event: React.KeyboardEvent<HTMLButtonElement>,
                                ) => {
                                    const offsets: Record<string, number> = {
                                        ArrowLeft: -1,
                                        ArrowRight: 1,
                                        Home: -index,
                                        End: skinTones.length - 1 - index,
                                    };
                                    const offset = offsets[event.key];
                                    if (offset == undefined) return;
                                    event.preventDefault();
                                    const next = Math.max(
                                        0,
                                        Math.min(
                                            skinTones.length - 1,
                                            index + offset,
                                        ),
                                    );
                                    const buttons =
                                        event.currentTarget.parentElement?.querySelectorAll<HTMLButtonElement>(
                                            "button",
                                        );
                                    buttons?.[next]?.focus();
                                }}
                                sx={{ ...buttonSx, borderRadius: "50%" }}
                            >
                                {emoji}
                            </Box>
                        );
                    })}
            </Popover>
        </Dialog>
    );
};
