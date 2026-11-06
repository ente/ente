import { headerButtonSx } from "@/theme/buttons";
import { toolbarColors, toolbarShadow } from "@/theme/colors";
import { Box, IconButton } from "@mui/material";
import type { ReactNode } from "react";
import BookBindingSelect from "./BookBindingSelect";
import BookTitleInput from "./BookTitleInput";
import { EDITOR_HEADER_HEIGHT } from "./editorLayout";
import { CloseSidebarIcon, OpenSidebarIcon } from "./icons";

export default function BookHeader({
    children,
    center,
    showBookControls = true,
    showBindingSelect = false,
    titleDisabled = false,
    sidebarOpen,
    onToggleSidebar,
}: {
    children: ReactNode;
    center?: ReactNode;
    showBookControls?: boolean;
    showBindingSelect?: boolean;
    titleDisabled?: boolean;
    sidebarOpen?: boolean;
    onToggleSidebar?: () => void;
}) {
    return (
        <Box
            component="header"
            sx={{
                display: "grid",
                gridTemplateColumns: {
                    xs: "minmax(0, 1fr) minmax(0, max-content)",
                    md: center
                        ? "minmax(0, 1fr) auto minmax(0, 1fr)"
                        : "minmax(0, 1fr) auto",
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
            {showBookControls && (
                <Box
                    sx={{
                        gridColumn: 1,
                        gridRow: 1,
                        display: "flex",
                        alignItems: "center",
                        gap: 1,
                        minWidth: 0,
                    }}
                >
                    {onToggleSidebar && (
                        <IconButton
                            aria-label={
                                sidebarOpen ? "Close sidebar" : "Open sidebar"
                            }
                            aria-expanded={sidebarOpen}
                            aria-controls="book-pages-sidebar"
                            onClick={onToggleSidebar}
                            sx={{
                                height: headerButtonSx.height,
                                width: headerButtonSx.height,
                                borderRadius: headerButtonSx.borderRadius,
                                flexShrink: 0,
                                color: toolbarColors.text,
                                bgcolor: toolbarColors.background,
                                boxShadow: toolbarShadow,
                                "&:hover": { bgcolor: toolbarColors.hover },
                                "&:active": { bgcolor: toolbarColors.active },
                            }}
                        >
                            {sidebarOpen ? (
                                <OpenSidebarIcon />
                            ) : (
                                <CloseSidebarIcon />
                            )}
                        </IconButton>
                    )}
                    <BookTitleInput disabled={titleDisabled} />
                </Box>
            )}
            {showBookControls && center && (
                <Box
                    sx={{
                        gridColumn: 2,
                        gridRow: 1,
                        justifySelf: "center",
                        minWidth: 0,
                    }}
                >
                    {center}
                </Box>
            )}
            <Box
                sx={{
                    gridColumn: center ? 3 : 2,
                    gridRow: 1,
                    justifySelf: "end",
                    display: showBookControls
                        ? { xs: "contents", md: "flex" }
                        : "none",
                    alignItems: "center",
                    gap: 1,
                }}
            >
                {showBindingSelect && (
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
                )}
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
