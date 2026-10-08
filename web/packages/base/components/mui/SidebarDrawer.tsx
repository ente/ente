import ArrowBackIcon from "@mui/icons-material/ArrowBack";
import CloseIcon from "@mui/icons-material/Close";
import {
    Box,
    Drawer,
    IconButton,
    Stack,
    styled,
    Typography,
    type DrawerProps,
} from "@mui/material";
import { isDesktop } from "ente-base/app";
import type { ModalVisibilityProps } from "ente-base/components/utils/modal";
import React, { useContext } from "react";
import {
    SidebarDrawerDepthContext,
    SidebarPanelContext,
} from "./SidebarDrawerContext";

type SidebarDrawerProps = DrawerProps & { maxWidth?: string };

export const SidebarDrawer: React.FC<SidebarDrawerProps> = ({
    slotProps,
    children,
    maxWidth = "375px",
    ...rest
}) => {
    const container = useContext(SidebarPanelContext);
    const inShell = !!container;
    return (
        <Drawer
            {...rest}
            {...(inShell && {
                variant: "temporary",
                container,
                disableEnforceFocus: true,
                disableScrollLock: true,
                sx: { position: "absolute", inset: 0 },
            })}
            slotProps={{
                ...(slotProps ?? {}),
                ...(inShell && {
                    backdrop: {
                        sx: {
                            position: "absolute",
                            backgroundColor: "transparent",
                        },
                    },
                }),
                paper: {
                    sx: {
                        maxWidth: inShell ? "none" : maxWidth,
                        width: "100%",
                        ...(inShell && {
                            position: "absolute",
                            boxSizing: "border-box",
                            bgcolor: "background.paper2",
                            boxShadow: "none",
                            border: 0,
                        }),
                        scrollbarWidth: "thin",
                        // Extra specificity overrides inherited padding.
                        "&&": { padding: 0 },
                    },
                },
            }}
        >
            {isDesktop && !inShell && <AppTitlebarBackdrop />}
            <Box sx={{ p: 1 }}>{children}</Box>
        </Drawer>
    );
};

// Keep scrolling content behind the desktop titlebar and traffic lights.
const AppTitlebarBackdrop = styled("div")(({ theme }) => ({
    position: "sticky",
    top: 0,
    left: 0,
    width: "100%",
    minHeight: "env(titlebar-area-height, 0px)",
    zIndex: 1,
    backgroundColor: theme.vars.palette.backdrop.muted,
    backdropFilter: "blur(12px)",
}));

export type NestedSidebarDrawerVisibilityProps = ModalVisibilityProps & {
    // Each nesting level must chain its own onClose into this callback.
    onRootClose: () => void;
};

const NestedSidebarDrawer: React.FC<
    NestedSidebarDrawerVisibilityProps & SidebarDrawerProps
> = ({ onClose, onRootClose, ...rest }) => {
    // Backdrop taps close the entire stack.
    const handleClose: DrawerProps["onClose"] = (_, reason) => {
        if (reason == "backdropClick") {
            onClose();
            onRootClose();
        } else {
            onClose();
        }
    };

    return (
        <SidebarDrawer
            // A stacked drawer would slide in from the wrong direction.
            transitionDuration={0}
            // Keep the backdrop clickable but invisible over the root backdrop.
            slotProps={{
                backdrop: { sx: { "&&&": { backgroundColor: "transparent" } } },
            }}
            onClose={handleClose}
            {...rest}
        />
    );
};

type SidebarDrawerTitlebarProps = Pick<
    NestedSidebarDrawerVisibilityProps,
    "onClose" | "onRootClose"
> & {
    title: string;
    caption?: string;
    actionButton?: React.ReactNode;
    showRootCloseButton?: boolean;
    showBackButton?: boolean;
};

export const SidebarDrawerTitlebar: React.FC<SidebarDrawerTitlebarProps> = ({
    title,
    caption,
    onClose,
    onRootClose,
    actionButton,
    showRootCloseButton = true,
    showBackButton = true,
}) => (
    <Stack sx={{ gap: "4px" }}>
        <Stack
            direction="row"
            sx={{
                justifyContent: showBackButton ? "space-between" : "flex-end",
            }}
        >
            {showBackButton && (
                <IconButton
                    aria-label="Back"
                    onClick={onClose}
                    color="primary"
                    sx={{ ml: "0.5rem" }}
                >
                    <ArrowBackIcon />
                </IconButton>
            )}
            <Stack direction="row" sx={{ gap: "4px" }}>
                {actionButton && actionButton}
                {showRootCloseButton && (
                    <IconButton
                        aria-label="Close"
                        onClick={onRootClose}
                        color="secondary"
                    >
                        <CloseIcon />
                    </IconButton>
                )}
            </Stack>
        </Stack>
        <Stack sx={{ pl: "calc(16px + 0.5rem)", pr: "16px", gap: "4px" }}>
            <Typography variant="h3" sx={{ fontSize: "22px" }}>
                {title}
            </Typography>
            <Typography
                variant="small"
                sx={{
                    color: "text.muted",
                    wordBreak: "break-all",
                    minHeight: "17px",
                }}
            >
                {caption}
            </Typography>
        </Stack>
    </Stack>
);

export const TitledNestedSidebarDrawer: React.FC<
    React.PropsWithChildren<
        NestedSidebarDrawerVisibilityProps &
            Pick<SidebarDrawerProps, "anchor" | "maxWidth"> &
            SidebarDrawerTitlebarProps
    >
> = ({ open, onClose, onRootClose, anchor, maxWidth, children, ...rest }) => {
    const container = useContext(SidebarPanelContext);
    const depth = useContext(SidebarDrawerDepthContext);
    return (
        <NestedSidebarDrawer
            {...{ open, onClose, onRootClose, anchor, maxWidth }}
        >
            <Stack sx={{ gap: "4px", py: "12px" }}>
                <SidebarDrawerTitlebar
                    {...{ onClose, onRootClose }}
                    {...rest}
                    showRootCloseButton={
                        !container && (rest.showRootCloseButton ?? true)
                    }
                    showBackButton={
                        rest.showBackButton ?? (!container || depth > 0)
                    }
                />
                <SidebarDrawerDepthContext.Provider value={depth + 1}>
                    {children}
                </SidebarDrawerDepthContext.Provider>
            </Stack>
        </NestedSidebarDrawer>
    );
};
