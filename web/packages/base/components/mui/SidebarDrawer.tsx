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
import React from "react";

export const SidebarDrawer: React.FC<DrawerProps> = ({
    slotProps,
    children,
    ...rest
}) => (
    <Drawer
        {...rest}
        slotProps={{
            ...(slotProps ?? {}),
            paper: {
                sx: {
                    maxWidth: "375px",
                    width: "100%",
                    scrollbarWidth: "thin",
                    // Extra specificity overrides inherited padding.
                    "&&": { padding: 0 },
                },
            },
        }}
    >
        {isDesktop && <AppTitlebarBackdrop />}
        <Box sx={{ p: 1 }}>{children}</Box>
    </Drawer>
);

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
    NestedSidebarDrawerVisibilityProps & DrawerProps
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
};

export const SidebarDrawerTitlebar: React.FC<SidebarDrawerTitlebarProps> = ({
    title,
    caption,
    onClose,
    onRootClose,
    actionButton,
    showRootCloseButton = true,
}) => (
    <Stack sx={{ gap: "4px" }}>
        <Stack direction="row" sx={{ justifyContent: "space-between" }}>
            <IconButton onClick={onClose} color="primary">
                <ArrowBackIcon />
            </IconButton>
            <Stack direction="row" sx={{ gap: "4px" }}>
                {actionButton && actionButton}
                {showRootCloseButton && (
                    <IconButton onClick={onRootClose} color="secondary">
                        <CloseIcon />
                    </IconButton>
                )}
            </Stack>
        </Stack>
        <Stack sx={{ px: "16px", gap: "4px" }}>
            <Typography variant="h3">{title}</Typography>
            <Typography
                variant="small"
                sx={{
                    color: "text.muted",
                    wordBreak: "break-all",
                    px: "1px",
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
            Pick<DrawerProps, "anchor"> &
            SidebarDrawerTitlebarProps
    >
> = ({ open, onClose, onRootClose, anchor, children, ...rest }) => (
    <NestedSidebarDrawer {...{ open, onClose, onRootClose, anchor }}>
        <Stack sx={{ gap: "4px", py: "12px" }}>
            <SidebarDrawerTitlebar {...{ onClose, onRootClose }} {...rest} />
            {children}
        </Stack>
    </NestedSidebarDrawer>
);
