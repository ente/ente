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

/**
 * A MUI {@link Drawer} with a standard set of styling that we use for our left
 * and right sidebar panels.
 *
 * It is width limited to 375px, and always at full width. It also has a default
 * padding.
 *
 * It also does some trickery with a sticky opaque bar to ensure that the
 * content scrolls below our inline title bar on desktop.
 */
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
                    // Need to increase specificity to override inherited padding.
                    "&&": { padding: 0 },
                },
            },
        }}
    >
        {isDesktop && <AppTitlebarBackdrop />}
        <Box sx={{ p: 1 }}>{children}</Box>
    </Drawer>
);

/**
 * When running on desktop, we adds a sticky opaque bar at the top of the
 * sidebar with a z-index greater than the expected sidebar contents. This
 * ensures that any title bar overlays added by the system (e.g. the traffic
 * lights on macOS) have a opaque-ish background and the sidebar contents scroll
 * underneath them.
 *
 * See: [Note: Customize the desktop title bar]
 */
const AppTitlebarBackdrop = styled("div")(({ theme }) => ({
    position: "sticky",
    top: 0,
    left: 0,
    width: "100%",
    minHeight: "env(titlebar-area-height, 30px)",
    zIndex: 1,
    backgroundColor: theme.vars.palette.backdrop.muted,
    backdropFilter: "blur(12px)",
}));

/**
 * Common props for a {@link NestedSidebarDrawer} component. In addition to the
 * regular modal visibility controls for opening and closing itself, these also
 * surface an option to close the entire drawer.
 */
export type NestedSidebarDrawerVisibilityProps = ModalVisibilityProps & {
    /**
     * Called when the user wants to close the entire stack of drawers.
     *
     * Note that this does not automatically imply onClose. Each step in the
     * nesting will have to chain their own onCloses to construct a new
     * `onRootClose` suitable for passing to its children.
     */
    onRootClose: () => void;
};

/**
 * A variant of {@link SidebarDrawer} for second level, nested drawers that are
 * shown atop an already visible {@link SidebarDrawer}.
 */
export const NestedSidebarDrawer: React.FC<
    NestedSidebarDrawerVisibilityProps & DrawerProps
> = ({ onClose, onRootClose, ...rest }) => {
    // Intercept backdrop taps and repurpose them to close the entire stack.
    const handleClose: DrawerProps["onClose"] = (_, reason) => {
        if (reason == "backdropClick") {
            onClose();
            onRootClose();
        } else {
            onClose();
        }
    };

    // MUI doesn't (currently, AFAIK) have support for nested drawers, so we
    // emulate that by showing a drawer atop another. To make it fit, we need to
    // modify a few knobs.

    return (
        <SidebarDrawer
            // Disable the transition (otherwise our nested drawer visibly
            // slides in from the wrong direction).
            transitionDuration={0}
            // Make the backdrop transparent (otherwise we end up with two of
            // them - one from the original drawer, and one from this nested
            // one).
            //
            // Note that there is an easy way to hide the backdrop (using the
            // `hideBackdrop` attribute), but that takes away our ability to
            // intercept backdrop clicks to close it.
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
    /** Title for the drawer. */
    title: string;
    /** An optional secondary caption shown below the title. */
    caption?: string;
    /**
     * An optional action button shown alongwith the close button at the
     * trailing edge of the sidebar.
     */
    actionButton?: React.ReactNode;
    /** Whether to show the trailing close button for the root drawer. */
    showRootCloseButton?: boolean;
};

/**
 * A bar with a title and back / close buttons, suitable for being used in
 * tandem with a {@link NestedSidebarDrawer}.
 */
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

/**
 * A variant of {@link NestedSidebarDrawer} that additionally shows a title.
 *
 * {@link NestedSidebarDrawer} is for second level, nested drawers that are
 * shown atop an already visible {@link SidebarDrawer}. This component combines
 * the {@link NestedSidebarDrawer} with a {@link SidebarDrawerTitlebar} and some
 * standard spacing, so that the caller can just provide the content as the
 * children.
 */
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
