import { Box } from "@mui/material";
import { EDITOR_PANEL_SX, EDITOR_SIDEBAR_WIDTH } from "./editorLayout";
import PageStrip, { type PageStripProps } from "./PageStrip";

export default function BookSidebar(props: PageStripProps) {
    return (
        <Box
            component="aside"
            id="book-pages-sidebar"
            aria-label="Book pages"
            sx={{
                ...EDITOR_PANEL_SX,
                borderRadius: "20px",
                width: EDITOR_SIDEBAR_WIDTH,
                display: "flex",
                flexDirection: "column",
                flexShrink: 0,
                overflow: "hidden",
            }}
        >
            <PageStrip {...props} />
        </Box>
    );
}
