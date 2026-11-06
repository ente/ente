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
    const bookTitle =
        book.title === "Untitled photobook (for spine)"
            ? ""
            : (book.title ?? "");
    const [title, setTitle] = useState(bookTitle);
    const [focused, setFocused] = useState(false);

    useEffect(() => {
        if (!focused) setTitle(bookTitle);
    }, [bookTitle, focused]);

    return (
        <>
            <Box
                component="input"
                aria-label="Photobook title"
                value={title}
                placeholder="Untitled photobook (for the spine)"
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
                    if (title !== bookTitle) {
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
                    width: "auto",
                    fieldSizing: "content",
                    maxWidth: "100%",
                    minWidth: 0,
                    height: headerButtonSx.height,
                    p: { xs: "8px 12px", sm: "9px 16px" },
                    fontFamily: "var(--font-inter), sans-serif",
                    fontSize: 14,
                    fontWeight: 600,
                    lineHeight: "20px",
                    color: uiColors.text,
                    textAlign: "left",
                    bgcolor: "transparent",
                    border: compact
                        ? "1px solid #484848"
                        : "1px solid transparent",
                    borderRadius: headerButtonSx.borderRadius,
                    outline: "none",
                    transition: "border-color 120ms ease",
                    "&:enabled:hover": { borderColor: "#484848" },
                    "&:enabled:focus, &:enabled:active": {
                        borderColor: "#707070",
                    },
                    "&:disabled": { opacity: 0.45 },
                }}
            />
            {editing && (
                <MobileTextDialog
                    title="Book title"
                    description="Shown on the spine of your photobook."
                    value={bookTitle}
                    onSave={(value) =>
                        setBook((previous) => ({ ...previous, title: value }))
                    }
                    onClose={() => setEditing(false)}
                />
            )}
        </>
    );
}
