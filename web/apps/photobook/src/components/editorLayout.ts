import { uiColors } from "@/theme/colors";

export const EDITOR_SIDEBAR_WIDTH = { xs: 156, sm: 366 };
export const EDITOR_CANVAS_PADDING = 16;
export const EDITOR_HEADER_HEIGHT = { xs: 60, sm: 76 };
export const EDITOR_PANEL_INSET = { xs: "8px", sm: "12px" };
export const EDITOR_PANEL_BOTTOM_INSET = { xs: "8px", sm: "11px" };
export const EDITOR_PANEL_SX = {
    bgcolor: uiColors.surface,
    borderRadius: "24px",
} as const;

export const EDITOR_SCROLLBAR_SX = {
    "&::-webkit-scrollbar": { width: "4px", height: "4px" },
    "&::-webkit-scrollbar-track": { bgcolor: "transparent" },
    "&::-webkit-scrollbar-thumb": { bgcolor: "#484848", borderRadius: "2px" },
    "&::-webkit-scrollbar-thumb:hover": { bgcolor: "#666666" },
    "@supports not selector(::-webkit-scrollbar)": {
        scrollbarWidth: "thin",
        scrollbarColor: "#484848 transparent",
    },
} as const;
