import { useBook } from "@/context/book";
import { headerButtonSx } from "@/theme/buttons";
import { uiColors } from "@/theme/colors";
import { Box, useMediaQuery } from "@mui/material";
import { useEffect, useState } from "react";
import { MOBILE_QUERY } from "./editorLayout";
import MobileTextDialog from "./MobileTextDialog";

export default function BookTitleInput({
    disabled = false,
}: {
    disabled?: boolean;
}) {
    const compact = useMediaQuery(MOBILE_QUERY);
    const [editing, setEditing] = useState(false);
    const { book, setBook } = useBook("book", "setBook");
    const [title, setTitle] = useState(book.title ?? "");
    const [focused, setFocused] = useState(false);

    useEffect(() => {
        if (!focused) setTitle(book.title ?? "");
    }, [book.title, focused]);

    return (
        <>
            <Box
                component="input"
                aria-label="Photobook title"
                value={title}
                placeholder="Book title (on spine)"
                autoComplete="off"
                disabled={disabled}
                readOnly={compact}
                onClick={compact ? () => setEditing(true) : undefined}
                onChange={(event) => setTitle(event.target.value)}
                onFocus={() => {
                    if (!compact) setFocused(true);
                }}
                onBlur={() => {
                    setFocused(false);
                    if (title !== (book.title ?? "")) {
                        setBook((previous) => ({ ...previous, title }));
                    }
                }}
                onKeyDown={(event) => {
                    if (event.key === "Enter") {
                        if (compact) setEditing(true);
                        else event.currentTarget.blur();
                    }
                }}
                sx={{
                    gridColumn: { xs: 1, md: 2 },
                    gridRow: { xs: 2, md: 1 },
                    justifySelf: { xs: "start", md: "center" },
                    width: 240,
                    maxWidth: "100%",
                    minWidth: 0,
                    minHeight: compact ? 44 : undefined,
                    p: { xs: "8px 12px", sm: "9px 16px" },
                    fontFamily: "var(--font-inter), sans-serif",
                    fontSize: 14,
                    fontWeight: 600,
                    lineHeight: "20px",
                    color: uiColors.text,
                    textAlign: "center",
                    bgcolor: "#262626",
                    border: "1px solid transparent",
                    borderRadius: headerButtonSx.borderRadius,
                    outline: "none",
                    transition:
                        "background-color 120ms ease, border-color 120ms ease",
                    "&::placeholder": { color: uiColors.muted, opacity: 1 },
                    "&:enabled:hover": {
                        bgcolor: "#2E2E2E",
                        borderColor: "#484848",
                    },
                    "&:enabled:focus": {
                        bgcolor: "#2E2E2E",
                        borderColor: "#707070",
                    },
                    "&:disabled": { opacity: 0.45 },
                }}
            />
            {editing && (
                <MobileTextDialog
                    title="Book title (on spine)"
                    value={book.title ?? ""}
                    onSave={(value) =>
                        setBook((previous) => ({ ...previous, title: value }))
                    }
                    onClose={() => setEditing(false)}
                />
            )}
        </>
    );
}
