import ArrowBackOutlinedIcon from "@mui/icons-material/ArrowBackOutlined";
import {
    Box,
    Drawer,
    IconButton,
    Stack,
    Typography,
    type DrawerProps,
} from "@mui/material";
import type { ModalVisibilityProps } from "ente-base/components/utils/modal";
import { t } from "i18next";
import React from "react";
import {
    display2Sx,
    sidebarBackgroundSx,
    textBaseSx,
} from "./locker-sidebar-styles";

export const LockerSidebarDrawer: React.FC<DrawerProps> = ({
    slotProps,
    children,
    ...rest
}) => {
    const paperSlotProps =
        typeof slotProps?.paper === "function" ? undefined : slotProps?.paper;

    return (
        <Drawer
            {...rest}
            closeAfterTransition={false}
            slotProps={{
                backdrop: {
                    sx: (theme) => ({
                        [theme.breakpoints.down("sm")]: {
                            "&&&": { backgroundColor: "transparent" },
                        },
                    }),
                },
                ...(slotProps ?? {}),
                paper: {
                    ...(paperSlotProps ?? {}),
                    sx: [
                        {
                            width: { xs: "100%", sm: 375 },
                            scrollbarWidth: "thin",
                            "&&": { padding: 0 },
                        },
                        sidebarBackgroundSx,
                        paperSlotProps?.sx as never,
                    ],
                },
            }}
        >
            {children}
        </Drawer>
    );
};

export type LockerNestedSidebarDrawerVisibilityProps = ModalVisibilityProps & {
    onRootClose: () => void;
};

const LockerNestedSidebarDrawer: React.FC<
    LockerNestedSidebarDrawerVisibilityProps & DrawerProps
> = ({ onClose, onRootClose, ...rest }) => {
    const handleClose: DrawerProps["onClose"] = (_, reason) => {
        if (reason == "backdropClick") {
            onClose();
            onRootClose();
        } else {
            onClose();
        }
    };

    return (
        <LockerSidebarDrawer
            transitionDuration={0}
            slotProps={{
                backdrop: { sx: { "&&&": { backgroundColor: "transparent" } } },
            }}
            onClose={handleClose}
            {...rest}
        />
    );
};

interface LockerSidebarTitlebarProps {
    onClose: () => void;
    title: string;
    actionButton?: React.ReactNode;
    closeLabel?: string;
    tooltip?: string;
}

export const LockerSidebarTitlebar: React.FC<LockerSidebarTitlebarProps> = ({
    title,
    onClose,
    actionButton,
    closeLabel,
    tooltip,
}) => (
    <Box sx={{ position: "relative", height: 92, flexShrink: 0 }}>
        <IconButton
            aria-label={closeLabel ?? t("go_back")}
            onClick={onClose}
            sx={[
                textBaseSx,
                {
                    position: "absolute",
                    left: 8,
                    top: 8,
                    p: 1,
                    borderRadius: "12px",
                },
            ]}
        >
            <ArrowBackOutlinedIcon sx={{ fontSize: 24 }} />
        </IconButton>
        <Typography
            noWrap
            title={tooltip}
            sx={[
                display2Sx,
                textBaseSx,
                {
                    position: "absolute",
                    left: 16,
                    right: actionButton ? 70 : 16,
                    top: 48,
                },
            ]}
        >
            {title}
        </Typography>
        {actionButton && (
            <Box sx={{ position: "absolute", right: 16, top: 45 }}>
                {actionButton}
            </Box>
        )}
    </Box>
);

type LockerTitledNestedSidebarDrawerProps = React.PropsWithChildren<
    LockerNestedSidebarDrawerVisibilityProps &
        Pick<DrawerProps, "anchor" | "slotProps"> &
        LockerSidebarTitlebarProps
>;

export const LockerTitledNestedSidebarDrawer: React.FC<
    LockerTitledNestedSidebarDrawerProps
> = ({ open, onClose, onRootClose, anchor, slotProps, children, ...rest }) => (
    <LockerNestedSidebarDrawer
        {...{ open, onClose, onRootClose, anchor, slotProps }}
    >
        <LockerSidebarTitlebar onClose={onClose} {...rest} />
        <Stack sx={{ flex: 1, p: "0 16px 16px", gap: 1 }}>{children}</Stack>
    </LockerNestedSidebarDrawer>
);
