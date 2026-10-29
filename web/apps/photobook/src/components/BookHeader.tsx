import { Box } from "@mui/material";
import type { ReactNode } from "react";
import BookBindingSelect from "./BookBindingSelect";
import BookBrand from "./BookBrand";
import BookTitleInput from "./BookTitleInput";
import { EDITOR_HEADER_HEIGHT } from "./editorLayout";

export default function BookHeader({
    children,
    showBookControls = true,
    titleDisabled = false,
}: {
    children: ReactNode;
    showBookControls?: boolean;
    titleDisabled?: boolean;
}) {
    return (
        <Box
            component="header"
            sx={{
                display: "grid",
                gridTemplateColumns: {
                    xs: "minmax(0, 1fr) minmax(0, max-content)",
                    md: "minmax(max-content, 1fr) minmax(0, max-content) minmax(max-content, 1fr)",
                },
                alignItems: "center",
                minHeight: showBookControls
                    ? { xs: 104, sm: 116, md: 76 }
                    : EDITOR_HEADER_HEIGHT,
                gap: 1,
                px: 1,
                flexShrink: 0,
            }}
        >
            <Box sx={{ gridColumn: 1, gridRow: 1, justifySelf: "start" }}>
                <BookBrand />
            </Box>
            {showBookControls && <BookTitleInput disabled={titleDisabled} />}
            <Box
                sx={{
                    gridColumn: 3,
                    gridRow: 1,
                    justifySelf: "end",
                    display: showBookControls
                        ? { xs: "contents", md: "flex" }
                        : "none",
                    alignItems: "center",
                    gap: 1,
                }}
            >
                <Box
                    sx={{
                        gridColumn: 2,
                        gridRow: 2,
                        justifySelf: "end",
                        display: "flex",
                    }}
                >
                    <BookBindingSelect disabled={titleDisabled} />
                </Box>
                <Box
                    sx={{
                        gridColumn: 2,
                        gridRow: 1,
                        justifySelf: "end",
                        display: "flex",
                        alignItems: "center",
                        gap: 1,
                    }}
                >
                    {children}
                </Box>
            </Box>
        </Box>
    );
}
