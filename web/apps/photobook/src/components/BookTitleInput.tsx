"use client";

import { useBook } from "@/context/book";
import { headerButtonSx } from "@/theme/buttons";
import { uiColors } from "@/theme/colors";
import { Box } from "@mui/material";
import { useEffect, useState } from "react";

export default function BookTitleInput() {
    const { book, setBook } = useBook();
    const [title, setTitle] = useState(book.title ?? "");
    const [focused, setFocused] = useState(false);
    const placeholder = focused ? "" : "Book title (on spine)";

    useEffect(() => {
        if (!focused) setTitle(book.title ?? "");
    }, [book.title, focused]);

    return (
        <Box
            sx={{
                position: "relative",
                gridColumn: 2,
                gridRow: 1,
                justifySelf: "center",
                width: "max-content",
                maxWidth: { xs: "min(38vw, 160px)", md: "min(360px, 100%)" },
                minWidth: 0,
                fontFamily: "var(--font-inter), sans-serif",
                fontSize: 14,
                fontWeight: 600,
                lineHeight: "20px",
            }}
        >
            <Box
                component="span"
                aria-hidden="true"
                sx={{
                    display: "block",
                    visibility: "hidden",
                    whiteSpace: "pre",
                    overflow: "hidden",
                    minWidth: "calc(1ch + 34px)",
                    p: { xs: "8px 12px", sm: "9px 16px" },
                    border: "1px solid transparent",
                }}
            >
                {title || placeholder || " "}
            </Box>
            <Box
                component="input"
                aria-label="Photobook title"
                value={title}
                placeholder={placeholder}
                autoComplete="off"
                onChange={(event) => setTitle(event.target.value)}
                onFocus={() => setFocused(true)}
                onBlur={() => {
                    setFocused(false);
                    if (title !== (book.title ?? "")) {
                        setBook((previous) => ({ ...previous, title }));
                    }
                }}
                onKeyDown={(event) => {
                    if (event.key === "Enter") event.currentTarget.blur();
                }}
                sx={{
                    position: "absolute",
                    inset: 0,
                    width: "100%",
                    height: "100%",
                    minWidth: 0,
                    p: { xs: "8px 12px", sm: "9px 16px" },
                    font: "inherit",
                    color: uiColors.text,
                    textAlign: "center",
                    bgcolor: "#262626",
                    border: "1px solid transparent",
                    borderRadius: headerButtonSx.borderRadius,
                    outline: "none",
                    transition:
                        "background-color 120ms ease, border-color 120ms ease",
                    "&::placeholder": { color: uiColors.muted, opacity: 1 },
                    "&:hover": { bgcolor: "#2E2E2E", borderColor: "#484848" },
                    "&:focus": { bgcolor: "#2E2E2E", borderColor: "#707070" },
                }}
            />
        </Box>
    );
}
