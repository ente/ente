import { accentGreen } from "@/theme/buttons";
import { toolbarColors, toolbarShadow } from "@/theme/colors";
import { Box, Tab, Tabs } from "@mui/material";
import { useLayoutEffect, useRef, useState, type RefObject } from "react";
import {
    EDITOR_PANEL_INSET,
    EDITOR_PANEL_SX,
    EDITOR_SIDEBAR_WIDTH,
} from "./editorLayout";
import PageStrip, { type PageStripProps } from "./PageStrip";
import PhotoGallery, { type PhotoGalleryProps } from "./PhotoGallery";

export type SidebarTab = "pages" | "photos";
export type SidebarScrollPositions = RefObject<Record<SidebarTab, number>>;
export type SidebarTabsState = RefObject<{
    preview: boolean;
    tab: SidebarTab;
} | null>;

export default function BookSidebar({
    open,
    tab = "pages",
    onTabChange,
    scrollPositions,
    tabsState,
    gallery,
    preview = false,
    ...props
}: PageStripProps & {
    open: boolean;
    tab?: SidebarTab;
    onTabChange?: (tab: SidebarTab) => void;
    scrollPositions: SidebarScrollPositions;
    tabsState: SidebarTabsState;
    gallery?: PhotoGalleryProps;
    preview?: boolean;
}) {
    const scrollRef = useRef<HTMLDivElement>(null);
    const panelRef = useRef<HTMLDivElement>(null);
    const indicatorRef = useRef<HTMLDivElement>(null);
    const pagesTabRef = useRef<HTMLButtonElement>(null);
    const photosTabRef = useRef<HTMLButtonElement>(null);
    const previousTab = useRef(tab);
    const [tabsTransition] = useState(() => ({
        from: tabsState.current,
        to: { preview, tab },
    }));

    useLayoutEffect(() => {
        tabsState.current = { preview, tab };
    }, [preview, tab, tabsState]);

    useLayoutEffect(() => {
        const { from, to } = tabsTransition;
        if (
            !from ||
            from.preview === to.preview ||
            window.matchMedia("(prefers-reduced-motion: reduce)").matches
        )
            return;
        const options = {
            duration: 240,
            easing: "cubic-bezier(0.2, 0.8, 0.2, 1)",
        };
        const animations = [
            indicatorRef.current?.animate(
                [from, to].map((state) => ({
                    left:
                        !state.preview && state.tab === "photos"
                            ? "calc(50% + 3px)"
                            : "6px",
                    width: state.preview
                        ? "calc(100% - 12px)"
                        : "calc(50% - 9px)",
                })),
                options,
            ),
            pagesTabRef.current?.animate(
                [from.preview, to.preview].map((single) => ({
                    width: single ? "100%" : "calc(50% - 3px)",
                })),
                options,
            ),
            photosTabRef.current?.animate(
                [from.preview, to.preview].map((single) => ({
                    opacity: single ? 0 : 1,
                    transform: `translateX(${single ? 8 : 0}px)`,
                    visibility: "visible",
                })),
                options,
            ),
        ];
        return () => animations.forEach((animation) => animation?.cancel());
    }, [tabsTransition]);

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
                position: "relative",
                display: "flex",
                flexShrink: 0,
                minHeight: 0,
                width: open ? EDITOR_SIDEBAR_WIDTH : 0,
                mr: open ? EDITOR_PANEL_INSET : 0,
                overflow: "hidden",
                "&:has([data-previewing='true'])": {
                    zIndex: (theme) => theme.zIndex.tooltip,
                },
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
                    <Box
                        sx={{
                            m: 2,
                            p: "6px",
                            flexShrink: 0,
                            position: "relative",
                            borderRadius: "20px",
                            bgcolor: toolbarColors.background,
                            boxShadow: toolbarShadow,
                        }}
                    >
                        <Box
                            ref={indicatorRef}
                            sx={{
                                position: "absolute",
                                top: 6,
                                height: 40,
                                left:
                                    !preview && tab === "photos"
                                        ? "calc(50% + 3px)"
                                        : 6,
                                width: preview
                                    ? "calc(100% - 12px)"
                                    : "calc(50% - 9px)",
                                borderRadius: "14px",
                                bgcolor: toolbarColors.control,
                                transition:
                                    "left 200ms cubic-bezier(0.2, 0.8, 0.2, 1), width 200ms cubic-bezier(0.2, 0.8, 0.2, 1)",
                                "@media (prefers-reduced-motion: reduce)": {
                                    transition: "none",
                                },
                            }}
                        />
                        <Tabs
                            value={tab}
                            onChange={(_, value: SidebarTab) =>
                                onTabChange?.(value)
                            }
                            aria-label="Sidebar"
                            sx={{
                                minHeight: 40,
                                "& .MuiTabs-indicator": { display: "none" },
                                "& .MuiTabs-list": {
                                    position: "relative",
                                    zIndex: 1,
                                },
                                "& .MuiTab-root": {
                                    flexShrink: 0,
                                    maxWidth: "none",
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
                                    "& .MuiTab-root": { transition: "none" },
                                },
                            }}
                        >
                            <Tab
                                component="button"
                                ref={pagesTabRef}
                                disableRipple
                                id="sidebar-pages-tab"
                                aria-controls="sidebar-pages-panel"
                                label="Pages"
                                value="pages"
                                sx={{
                                    width: preview ? "100%" : "calc(50% - 3px)",
                                }}
                            />
                            <Tab
                                component="button"
                                ref={photosTabRef}
                                disableRipple
                                disabled={preview}
                                aria-hidden={preview}
                                id="sidebar-photos-tab"
                                aria-controls="sidebar-photos-panel"
                                label="Photos"
                                value="photos"
                                sx={{
                                    position: "absolute",
                                    right: 0,
                                    width: "calc(50% - 3px)",
                                    opacity: preview ? 0 : 1,
                                    visibility: preview ? "hidden" : "visible",
                                }}
                            />
                        </Tabs>
                    </Box>
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
