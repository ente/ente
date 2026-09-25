import {
    Airplane01Icon,
    Apple01Icon,
    BulbIcon,
    Cancel01Icon,
    FavouriteIcon,
    Flag01Icon,
    FootballIcon,
    Leaf01Icon,
    Search01Icon,
    SmileIcon,
    UserIcon,
} from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import {
    Box,
    ClickAwayListener,
    Dialog,
    Popper,
    useMediaQuery,
} from "@mui/material";
import { SpaceBottomSheetTransition } from "components/BottomSheetTransition";
import { SpaceEmoji } from "components/Emoji";
import React from "react";
import {
    spaceControlBackgroundActive,
    spaceDialogBackground,
    spaceSurface,
    spaceSurfaceHover,
    spaceText,
    spaceTextMuted,
} from "styles/colors";
import { spaceTouchTargetSize } from "styles/touch-targets";
import { emojiKey, findEmoji, sameEmoji, type EmojiEntry } from "utils/emoji";

const categories = [
    { id: 0, name: "Smileys & emotion", icon: SmileIcon },
    { id: 1, name: "People & body", icon: UserIcon },
    { id: 3, name: "Animals & nature", icon: Leaf01Icon },
    { id: 4, name: "Food & drink", icon: Apple01Icon },
    { id: 5, name: "Travel & places", icon: Airplane01Icon },
    { id: 6, name: "Activities", icon: FootballIcon },
    { id: 7, name: "Objects", icon: BulbIcon },
    { id: 8, name: "Symbols", icon: FavouriteIcon },
    { id: 9, name: "Flags", icon: Flag01Icon },
];
const variantPopperModifiers = [
    { name: "offset", options: { offset: [0, 8] } },
    { name: "flip", options: { padding: 16, altBoundary: false } },
    { name: "preventOverflow", options: { padding: 16, altBoundary: false } },
];
const buttonStyle = {
    WebkitTapHighlightColor: "transparent",
    alignItems: "center",
    bgcolor: "transparent",
    border: 0,
    borderRadius: "14px",
    color: spaceText,
    cursor: "pointer",
    display: "inline-flex",
    flexShrink: 0,
    height: spaceTouchTargetSize,
    justifyContent: "center",
    minWidth: spaceTouchTargetSize,
    p: 0,
    "@media (hover: hover)": { "&:hover": { bgcolor: spaceSurfaceHover } },
    "&:focus-visible": { outline: "2px solid #08C225", outlineOffset: -2 },
    "&[aria-pressed=true]": { bgcolor: spaceSurfaceHover },
};

interface EmojiPickerProps {
    catalog: EmojiEntry[];
    reaction?: string;
    onSelect: (emoji: string) => void;
    onClose: () => void;
}

const EmojiPicker: React.FC<EmojiPickerProps> = ({
    catalog,
    reaction,
    onSelect,
    onClose,
}) => {
    const emojiEntries = React.useMemo(
        () =>
            new Map(
                catalog.flatMap((entry) =>
                    [entry, ...entry.skins].map(
                        ({ emoji }) => [emojiKey(emoji), entry] as const,
                    ),
                ),
            ),
        [catalog],
    );
    const resultsID = React.useId();
    const variantsID = React.useId();
    const [open, setOpen] = React.useState(true);
    const [query, setQuery] = React.useState("");
    const [category, setCategory] = React.useState(0);
    const [focusedIndex, setFocusedIndex] = React.useState(0);
    const [variants, setVariants] = React.useState<{
        entry: EmojiEntry;
        anchor: HTMLButtonElement;
    }>();
    const gridRef = React.useRef<HTMLDivElement>(null);
    const paperRef = React.useRef<HTMLDivElement>(null);
    const searchRef = React.useRef<HTMLInputElement>(null);
    const draggedRef = React.useRef(false);
    const dragRef = React.useRef<
        { pointerID: number; startY: number; startTime: number } | undefined
    >(undefined);
    const isBottomSheet = useMediaQuery("(max-width: 599px)");
    const results = React.useMemo(
        () => findEmoji(catalog, query, category, 0),
        [catalog, query, category],
    );
    const categoryName = categories.find(({ id }) => id === category)!.name;

    React.useEffect(() => {
        setFocusedIndex(0);
        gridRef.current?.scrollTo(0, 0);
        setVariants(undefined);
    }, [query, category]);

    const closeVariants = (restoreFocus: boolean) => {
        if (restoreFocus) variants?.anchor.focus({ preventScroll: true });
        setVariants(undefined);
    };

    const finishDrag = (
        event: React.PointerEvent<HTMLButtonElement>,
        cancelled = false,
    ) => {
        const drag = dragRef.current;
        if (drag?.pointerID !== event.pointerId) return;
        dragRef.current = undefined;
        const paper = paperRef.current!;
        const distance = Math.max(0, event.clientY - drag.startY);
        const speed = distance / Math.max(1, event.timeStamp - drag.startTime);
        paper.style.transition = "";
        if (!cancelled && (distance >= 80 || (distance >= 24 && speed > 0.6))) {
            setOpen(false);
        } else {
            paper.style.removeProperty("--emoji-picker-offset");
        }
    };

    const handleGridKey = (event: React.KeyboardEvent<HTMLDivElement>) => {
        const grid = gridRef.current;
        if (!grid) return;
        const buttons = grid.querySelectorAll<HTMLButtonElement>("button");
        const columns =
            getComputedStyle(grid).gridTemplateColumns.split(" ").length;
        const current = Array.from(buttons).indexOf(
            event.target as HTMLButtonElement,
        );
        let next: number;
        switch (event.key) {
            case "ArrowRight":
                next = current + 1;
                break;
            case "ArrowLeft":
                next = current - 1;
                break;
            case "ArrowDown":
                next = current + columns;
                break;
            case "ArrowUp":
                next = current - columns;
                break;
            case "Home":
                next = 0;
                break;
            case "End":
                next = buttons.length - 1;
                break;
            default:
                return;
        }
        event.preventDefault();
        next = Math.max(0, Math.min(buttons.length - 1, next));
        setFocusedIndex(next);
        buttons[next]?.focus();
    };

    return (
        <Dialog
            open={open}
            disableRestoreFocus
            onClose={() => setOpen(false)}
            maxWidth={false}
            slots={
                isBottomSheet
                    ? { transition: SpaceBottomSheetTransition }
                    : undefined
            }
            sx={{
                zIndex: 1500,
                "--space-dialog-backdrop": "rgba(0 0 0 / 0.86)",
            }}
            slotProps={{
                transition: { onExited: onClose },
                paper: {
                    ref: paperRef,
                    "aria-label": "Emoji picker",
                    sx: {
                        bgcolor: spaceDialogBackground,
                        borderRadius: "28px 28px 0 0",
                        bottom: 0,
                        boxShadow: "none",
                        boxSizing: "border-box",
                        color: spaceText,
                        fontFamily: '"Inter Variable", Inter, sans-serif',
                        height: 416,
                        left: 0,
                        m: 0,
                        maxHeight: "calc(100dvh - 24px)",
                        maxWidth: "none",
                        overflow: "visible",
                        p: "0 20px max(16px, env(safe-area-inset-bottom))",
                        position: "fixed",
                        transform:
                            "translateY(var(--emoji-picker-offset, 0px))",
                        transition: "transform 180ms ease-out",
                        width: "100vw",
                        "@media (min-width: 600px)": {
                            borderRadius: "20px",
                            bottom: "auto",
                            left: "auto",
                            m: "24px",
                            position: "relative",
                            width: 440,
                        },
                    },
                },
            }}
        >
            <Box
                component="button"
                type="button"
                aria-label="Dismiss emoji picker"
                onPointerDown={(event) => {
                    if (!event.isPrimary || event.button !== 0) return;
                    event.preventDefault();
                    draggedRef.current = false;
                    setVariants(undefined);
                    dragRef.current = {
                        pointerID: event.pointerId,
                        startY: event.clientY,
                        startTime: event.timeStamp,
                    };
                    event.currentTarget.setPointerCapture(event.pointerId);
                    paperRef.current!.style.transition = "none";
                }}
                onPointerMove={(event) => {
                    const drag = dragRef.current;
                    if (drag?.pointerID !== event.pointerId) return;
                    if (Math.abs(event.clientY - drag.startY) > 4)
                        draggedRef.current = true;
                    paperRef.current!.style.setProperty(
                        "--emoji-picker-offset",
                        `${Math.max(0, event.clientY - drag.startY)}px`,
                    );
                }}
                onPointerUp={(event) => finishDrag(event)}
                onPointerCancel={(event) => finishDrag(event, true)}
                onLostPointerCapture={(event) => finishDrag(event, true)}
                onKeyDown={() => {
                    draggedRef.current = false;
                }}
                onClick={() => {
                    if (draggedRef.current) {
                        draggedRef.current = false;
                        return;
                    }
                    setOpen(false);
                }}
                sx={{
                    ...buttonStyle,
                    alignItems: "center",
                    borderRadius: "28px 28px 0 0",
                    cursor: "grab",
                    mx: "-20px",
                    touchAction: "none",
                    userSelect: "none",
                    "@media (hover: hover)": {
                        "&:hover": { bgcolor: "transparent" },
                    },
                    "&:active": { cursor: "grabbing" },
                }}
            >
                <Box
                    component="span"
                    aria-hidden
                    sx={{
                        bgcolor: spaceTextMuted,
                        borderRadius: "4px",
                        height: 4,
                        opacity: 0.5,
                        width: 32,
                    }}
                />
            </Box>
            <Box
                component="label"
                sx={{
                    alignItems: "center",
                    bgcolor: spaceSurface,
                    border: "1px solid transparent",
                    borderRadius: "14px",
                    color: spaceTextMuted,
                    display: "flex",
                    flexShrink: 0,
                    gap: "10px",
                    height: 44,
                    mb: "12px",
                    px: "14px",
                    "&:focus-within": { borderColor: "#08C225" },
                }}
            >
                <HugeiconsIcon
                    icon={Search01Icon}
                    size={20}
                    strokeWidth={1.8}
                />
                <Box
                    component="input"
                    ref={searchRef}
                    type="search"
                    aria-label="Search emoji"
                    placeholder="Search"
                    autoFocus={!isBottomSheet}
                    autoComplete="off"
                    spellCheck={false}
                    value={query}
                    onChange={(event) => setQuery(event.target.value)}
                    sx={{
                        bgcolor: "transparent",
                        border: 0,
                        color: spaceText,
                        flex: 1,
                        font: "inherit",
                        fontSize: { xs: 16, sm: 14 },
                        height: "100%",
                        minWidth: 0,
                        outline: 0,
                        p: 0,
                        "&::placeholder": {
                            color: spaceTextMuted,
                            fontSize: 14,
                            opacity: 1,
                        },
                        "&::-webkit-search-cancel-button": { display: "none" },
                    }}
                />
                {query && (
                    <Box
                        component="button"
                        type="button"
                        aria-label="Clear search"
                        onClick={() => {
                            setQuery("");
                            searchRef.current?.focus();
                        }}
                        sx={{
                            ...buttonStyle,
                            borderRadius: "50%",
                            color: spaceTextMuted,
                            mr: "-10px",
                        }}
                    >
                        <HugeiconsIcon
                            icon={Cancel01Icon}
                            size={18}
                            strokeWidth={1.8}
                        />
                    </Box>
                )}
            </Box>
            <Box
                ref={gridRef}
                id={resultsID}
                role="group"
                aria-label={query ? "Emoji search results" : categoryName}
                onKeyDown={handleGridKey}
                onScroll={() => setVariants(undefined)}
                sx={{
                    alignContent: "start",
                    display: "grid",
                    flex: 1,
                    gap: "2px",
                    gridTemplateColumns: "repeat(auto-fill, minmax(44px, 1fr))",
                    minHeight: 0,
                    overflowY: "auto",
                    overscrollBehavior: "contain",
                    pb: "4px",
                }}
            >
                {results.map(({ emoji, name }, index) => {
                    const entry = emojiEntries.get(emojiKey(emoji))!;
                    return (
                        <EmojiButton
                            key={emoji}
                            emoji={emoji}
                            name={name}
                            selected={sameEmoji(reaction, emoji)}
                            focused={index === focusedIndex}
                            hasVariants={entry.skins.length > 0}
                            variantsID={variantsID}
                            expanded={variants?.entry === entry}
                            onFocus={() => setFocusedIndex(index)}
                            onSelect={() => onSelect(emoji)}
                            onOpenVariants={(anchor) =>
                                setVariants({ entry, anchor })
                            }
                        />
                    );
                })}
                {!results.length && (
                    <Box
                        sx={{
                            color: spaceTextMuted,
                            fontSize: 14,
                            gridColumn: "1 / -1",
                            py: "32px",
                            textAlign: "center",
                        }}
                    >
                        No emoji found
                    </Box>
                )}
            </Box>
            <Box
                role="group"
                aria-label="Emoji categories"
                sx={{
                    borderTop: "1px solid rgba(255, 255, 255, 0.06)",
                    display: "flex",
                    flexShrink: 0,
                    justifyContent: "space-between",
                    overflowX: "auto",
                    pt: "10px",
                    scrollbarWidth: "none",
                    "&::-webkit-scrollbar": { display: "none" },
                }}
            >
                {categories.map(({ id, name, icon }) => (
                    <Box
                        component="button"
                        type="button"
                        key={id}
                        aria-label={name}
                        aria-pressed={!query && category === id}
                        aria-controls={resultsID}
                        onClick={(event) => {
                            setQuery("");
                            setCategory(id);
                            event.currentTarget.scrollIntoView({
                                block: "nearest",
                                inline: "nearest",
                            });
                        }}
                        sx={{
                            ...buttonStyle,
                            color: spaceTextMuted,
                            "&[aria-pressed=true]": {
                                bgcolor: spaceSurface,
                                color: spaceText,
                            },
                        }}
                    >
                        <HugeiconsIcon
                            icon={icon}
                            size={22}
                            strokeWidth={1.8}
                        />
                    </Box>
                ))}
            </Box>
            {variants && (
                <EmojiVariants
                    id={variantsID}
                    entry={variants.entry}
                    anchor={variants.anchor}
                    reaction={reaction}
                    onClose={closeVariants}
                    onSelect={onSelect}
                />
            )}
        </Dialog>
    );
};

export default EmojiPicker;

interface EmojiButtonProps {
    emoji: string;
    name: string;
    selected: boolean;
    focused: boolean;
    hasVariants: boolean;
    variantsID: string;
    expanded: boolean;
    onFocus: () => void;
    onSelect: () => void;
    onOpenVariants: (anchor: HTMLButtonElement) => void;
}

const EmojiButton: React.FC<EmojiButtonProps> = ({
    emoji,
    name,
    selected,
    focused,
    hasVariants,
    variantsID,
    expanded,
    onFocus,
    onSelect,
    onOpenVariants,
}) => {
    const timer = React.useRef<number | undefined>(undefined);
    const start = React.useRef<{ x: number; y: number } | undefined>(undefined);
    const suppressClick = React.useRef(false);
    const cancelPress = React.useCallback(() => {
        window.clearTimeout(timer.current);
        timer.current = undefined;
        start.current = undefined;
    }, []);
    React.useEffect(() => cancelPress, [cancelPress]);

    const openVariants = (anchor: HTMLButtonElement) => {
        cancelPress();
        suppressClick.current = true;
        onOpenVariants(anchor);
    };

    return (
        <Box
            component="button"
            type="button"
            title={expanded ? undefined : name}
            aria-label={name}
            aria-pressed={selected}
            aria-haspopup={hasVariants ? "menu" : undefined}
            aria-expanded={hasVariants ? expanded : undefined}
            aria-controls={expanded ? variantsID : undefined}
            tabIndex={focused ? 0 : -1}
            onFocus={onFocus}
            onPointerDown={(event) => {
                cancelPress();
                suppressClick.current = false;
                if (!hasVariants || event.button !== 0 || !event.isPrimary)
                    return;
                const anchor = event.currentTarget;
                start.current = { x: event.clientX, y: event.clientY };
                timer.current = window.setTimeout(
                    () => openVariants(anchor),
                    520,
                );
            }}
            onPointerMove={(event) => {
                if (
                    start.current &&
                    Math.hypot(
                        event.clientX - start.current.x,
                        event.clientY - start.current.y,
                    ) > 10
                ) {
                    cancelPress();
                    suppressClick.current = true;
                }
            }}
            onPointerUp={cancelPress}
            onPointerCancel={cancelPress}
            onPointerLeave={cancelPress}
            onContextMenu={(event) => {
                event.preventDefault();
                if (hasVariants) openVariants(event.currentTarget);
            }}
            onKeyDown={(event) => {
                if (
                    hasVariants &&
                    (event.key === "ContextMenu" ||
                        (event.shiftKey && event.key === "F10") ||
                        (event.altKey && event.key === "ArrowDown"))
                ) {
                    event.preventDefault();
                    event.stopPropagation();
                    openVariants(event.currentTarget);
                } else {
                    suppressClick.current = false;
                }
            }}
            onClick={() => {
                if (suppressClick.current) {
                    suppressClick.current = false;
                    return;
                }
                onSelect();
            }}
            sx={{
                ...buttonStyle,
                position: "relative",
                touchAction: "pan-y",
                userSelect: "none",
                WebkitTouchCallout: "none",
                "@media (hover: hover)": {
                    "&:hover": { bgcolor: spaceControlBackgroundActive },
                },
                "&[aria-expanded=true]": { bgcolor: spaceSurfaceHover },
            }}
        >
            <SpaceEmoji emoji={emoji} size={28} />
            {hasVariants && (
                <Box
                    component="span"
                    aria-hidden
                    sx={{
                        borderBottom: `5px solid ${spaceTextMuted}`,
                        borderLeft: "5px solid transparent",
                        bottom: 5,
                        opacity: 0.6,
                        position: "absolute",
                        right: 5,
                    }}
                />
            )}
        </Box>
    );
};

const EmojiVariants: React.FC<{
    id: string;
    entry: EmojiEntry;
    anchor: HTMLButtonElement;
    reaction?: string;
    onClose: (restoreFocus: boolean) => void;
    onSelect: (emoji: string) => void;
}> = ({ id, entry, anchor, reaction, onClose, onSelect }) => {
    const choices = [entry, ...entry.skins];
    const selectedIndex = Math.max(
        0,
        choices.findIndex(({ emoji }) => sameEmoji(reaction, emoji)),
    );

    return (
        <Popper
            open
            disablePortal
            anchorEl={anchor}
            placement="top"
            modifiers={variantPopperModifiers}
            sx={{ zIndex: 1 }}
        >
            <ClickAwayListener
                mouseEvent="onMouseDown"
                touchEvent="onTouchStart"
                onClickAway={() => onClose(false)}
            >
                <Box
                    id={id}
                    role="menu"
                    aria-label={`${entry.name} variants`}
                    aria-orientation="horizontal"
                    onBlur={(event) => {
                        if (
                            event.relatedTarget &&
                            !event.currentTarget.contains(event.relatedTarget)
                        )
                            onClose(false);
                    }}
                    onKeyDown={(event) => {
                        if (event.key === "Escape") {
                            event.preventDefault();
                            event.stopPropagation();
                            onClose(true);
                            return;
                        }
                        const buttons = Array.from(
                            event.currentTarget.querySelectorAll<HTMLButtonElement>(
                                "button",
                            ),
                        );
                        const current = buttons.indexOf(
                            event.target as HTMLButtonElement,
                        );
                        let next: number;
                        switch (event.key) {
                            case "ArrowRight":
                                next = (current + 1) % buttons.length;
                                break;
                            case "ArrowLeft":
                                next =
                                    (current - 1 + buttons.length) %
                                    buttons.length;
                                break;
                            case "Home":
                                next = 0;
                                break;
                            case "End":
                                next = buttons.length - 1;
                                break;
                            default:
                                return;
                        }
                        event.preventDefault();
                        event.stopPropagation();
                        buttons[next]?.focus();
                    }}
                    sx={{
                        bgcolor: spaceSurface,
                        border: "1px solid rgba(255, 255, 255, 0.08)",
                        borderRadius: "28px",
                        boxShadow: "0 8px 28px rgba(0, 0, 0, 0.3)",
                        display: "flex",
                        maxWidth: "min(360px, calc(100vw - 32px))",
                        overflowX: "auto",
                        overscrollBehavior: "contain",
                        p: "6px",
                    }}
                >
                    {choices.map(({ emoji, name }, index) => (
                        <Box
                            component="button"
                            type="button"
                            key={emoji}
                            role="menuitemradio"
                            aria-label={name}
                            aria-checked={sameEmoji(reaction, emoji)}
                            title={name}
                            autoFocus={index === selectedIndex}
                            onClick={() => onSelect(emoji)}
                            sx={{
                                ...buttonStyle,
                                borderRadius: "50%",
                                "&[aria-checked=true]": {
                                    bgcolor: spaceSurfaceHover,
                                },
                            }}
                        >
                            <SpaceEmoji emoji={emoji} size={28} />
                        </Box>
                    ))}
                </Box>
            </ClickAwayListener>
        </Popper>
    );
};
