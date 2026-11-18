import { accentGreen } from "@/theme/buttons";
import { toolbarColors, toolbarShadow } from "@/theme/colors";
import { Box, Tab, Tabs } from "@mui/material";
import { useLayoutEffect, useRef, type RefObject } from "react";
import {
    EDITOR_PANEL_INSET,
    EDITOR_PANEL_SX,
    EDITOR_SIDEBAR_WIDTH,
} from "./editorLayout";
import PageStrip, { type PageStripProps } from "./PageStrip";
import PhotoGallery, { type PhotoGalleryProps } from "./PhotoGallery";

export type SidebarTab = "pages" | "photos";
export type SidebarScrollPositions = RefObject<Record<SidebarTab, number>>;

export default function BookSidebar({
    open,
    tab = "pages",
    onTabChange,
    scrollPositions,
    gallery,
    ...props
}: PageStripProps & {
    open: boolean;
    tab?: SidebarTab;
    onTabChange?: (tab: SidebarTab) => void;
    scrollPositions: SidebarScrollPositions;
    gallery?: PhotoGalleryProps;
}) {
    const scrollRef = useRef<HTMLDivElement>(null);
    const panelRef = useRef<HTMLDivElement>(null);
    const previousTab = useRef(tab);

    useLayoutEffect(() => {
        if (scrollRef.current) {
            scrollRef.current.scrollTop = scrollPositions.current[tab];
        }
        if (previousTab.current === tab) return;
        previousTab.current = tab;
        if (window.matchMedia("(prefers-reduced-motion: reduce)").matches)
            return;
        const animation = panelRef.current?.animate(
            [
                {
                    opacity: 0,
                    transform: `translateX(${tab === "photos" ? 6 : -6}px)`,
                },
                { opacity: 1, transform: "translateX(0)" },
            ],
            { duration: 180, easing: "ease-out" },
        );
        return () => animation?.cancel();
    }, [scrollPositions, tab]);

    return (
        <Box
            aria-hidden={!open}
            inert={!open}
            sx={{
                display: "flex",
                flexShrink: 0,
                minHeight: 0,
                width: open ? EDITOR_SIDEBAR_WIDTH : 0,
                mr: open ? EDITOR_PANEL_INSET : 0,
                overflow: "hidden",
                transition:
                    "width 240ms cubic-bezier(0.2, 0.8, 0.2, 1), margin-right 240ms cubic-bezier(0.2, 0.8, 0.2, 1)",
                "@media (prefers-reduced-motion: reduce)": {
                    transition: "none",
                },
            }}
        >
            <Box
                component="aside"
                id="book-pages-sidebar"
                aria-label="Book sidebar"
                onScrollCapture={(event) => {
                    const scroller = scrollRef.current;
                    if (scroller && event.target === scroller) {
                        scrollPositions.current[tab] = scroller.scrollTop;
                    }
                }}
                sx={{
                    ...EDITOR_PANEL_SX,
                    borderRadius: "20px",
                    width: EDITOR_SIDEBAR_WIDTH,
                    display: "flex",
                    flexDirection: "column",
                    flexShrink: 0,
                    overflow: "hidden",
                    opacity: open ? 1 : 0,
                    transform: open ? "translateX(0)" : "translateX(-8px)",
                    transition:
                        "opacity 160ms ease, transform 240ms cubic-bezier(0.2, 0.8, 0.2, 1)",
                    "@media (prefers-reduced-motion: reduce)": {
                        transition: "none",
                    },
                }}
            >
                {gallery && (
                    <Tabs
                        value={tab}
                        onChange={(_, value: SidebarTab) =>
                            onTabChange?.(value)
                        }
                        aria-label="Sidebar"
                        variant="fullWidth"
                        sx={{
                            m: 2,
                            minHeight: 52,
                            p: "6px",
                            borderRadius: "20px",
                            bgcolor: toolbarColors.background,
                            boxShadow: toolbarShadow,
                            "& .MuiTabs-indicator": {
                                top: 0,
                                height: "100%",
                                borderRadius: "14px",
                                bgcolor: toolbarColors.control,
                                transition:
                                    "left 200ms cubic-bezier(0.2, 0.8, 0.2, 1), width 200ms cubic-bezier(0.2, 0.8, 0.2, 1)",
                            },
                            "& .MuiTabs-list": {
                                gap: "6px",
                                position: "relative",
                                zIndex: 1,
                            },
                            "& .MuiTab-root": {
                                minWidth: 0,
                                minHeight: 40,
                                p: "10px 8px",
                                borderRadius: "14px",
                                textTransform: "none",
                                fontSize: 14,
                                fontWeight: 600,
                                lineHeight: "20px",
                                color: toolbarColors.muted,
                                transition: "color 160ms ease",
                                "&:hover": { bgcolor: "transparent" },
                                "&.Mui-selected": {
                                    color: toolbarColors.text,
                                    bgcolor: "transparent",
                                    "&:hover": { bgcolor: "transparent" },
                                },
                                "&.Mui-focusVisible": {
                                    outline: `2px solid ${accentGreen}`,
                                    outlineOffset: -2,
                                },
                            },
                            "@media (prefers-reduced-motion: reduce)": {
                                "& .MuiTabs-indicator, & .MuiTab-root": {
                                    transition: "none",
                                },
                            },
                        }}
                    >
                        <Tab
                            disableRipple
                            id="sidebar-pages-tab"
                            aria-controls="sidebar-pages-panel"
                            label="Pages"
                            value="pages"
                        />
                        <Tab
                            disableRipple
                            id="sidebar-photos-tab"
                            aria-controls="sidebar-photos-panel"
                            label="Photos"
                            value="photos"
                        />
                    </Tabs>
                )}
                <Box
                    key={tab}
                    ref={panelRef}
                    role={gallery ? "tabpanel" : undefined}
                    id={gallery ? `sidebar-${tab}-panel` : undefined}
                    aria-labelledby={gallery ? `sidebar-${tab}-tab` : undefined}
                    sx={{
                        display: "flex",
                        flexDirection: "column",
                        flex: 1,
                        minHeight: 0,
                    }}
                >
                    {gallery && tab === "photos" ? (
                        <PhotoGallery {...gallery} scrollRef={scrollRef} />
                    ) : (
                        <PageStrip {...props} scrollRef={scrollRef} />
                    )}
                </Box>
            </Box>
        </Box>
    );
}
