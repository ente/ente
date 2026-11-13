import MoreHorizIcon from "@mui/icons-material/MoreHoriz";
import {
    IconButton,
    MenuItem,
    Stack,
    Typography,
    type IconButtonProps,
    type PaperProps,
} from "@mui/material";
import Menu, { type MenuProps } from "@mui/material/Menu";
import React, { createContext, useContext, useMemo, useState } from "react";

interface OverflowMenuContextT {
    close: () => void;
}

const OverflowMenuContext = createContext<OverflowMenuContextT | undefined>(
    undefined,
);

interface OverflowMenuProps {
    ariaID: string;
    triggerButtonIcon?: React.ReactNode;
    triggerButtonSxProps?: IconButtonProps["sx"];
    menuPaperSxProps?: PaperProps["sx"];
}

export const OverflowMenu: React.FC<
    React.PropsWithChildren<OverflowMenuProps>
> = ({
    ariaID,
    triggerButtonIcon,
    triggerButtonSxProps,
    menuPaperSxProps,
    children,
}) => {
    const [anchorEl, setAnchorEl] = useState<MenuProps["anchorEl"]>();
    const context = useMemo(
        () => ({ close: () => setAnchorEl(undefined) }),
        [],
    );
    return (
        <OverflowMenuContext value={context}>
            <IconButton
                onClick={(event) => setAnchorEl(event.currentTarget)}
                aria-controls={anchorEl ? ariaID : undefined}
                aria-haspopup="true"
                aria-expanded={anchorEl ? "true" : undefined}
                sx={triggerButtonSxProps}
            >
                {triggerButtonIcon ?? <MoreHorizIcon />}
            </IconButton>
            <Menu
                id={ariaID}
                {...(anchorEl && { anchorEl })}
                open={!!anchorEl}
                onClose={() => setAnchorEl(undefined)}
                slotProps={{
                    paper: { sx: menuPaperSxProps },
                    list: { disablePadding: true, "aria-labelledby": ariaID },
                }}
                anchorOrigin={{ vertical: "bottom", horizontal: "right" }}
                transformOrigin={{ vertical: "top", horizontal: "right" }}
            >
                {children}
            </Menu>
        </OverflowMenuContext>
    );
};

interface OverflowMenuOptionProps {
    onClick: () => void;
    color?: "primary" | "critical";
    startIcon?: React.ReactNode;
    endIcon?: React.ReactNode;
    selected?: boolean;
    compact?: boolean;
    disabled?: boolean;
}

export const OverflowMenuOption: React.FC<
    React.PropsWithChildren<OverflowMenuOptionProps>
> = ({
    onClick,
    color = "primary",
    startIcon,
    endIcon,
    selected,
    compact,
    disabled,
    children,
}) => {
    const menuContext = useContext(OverflowMenuContext);

    const handleClick = () => {
        onClick();
        // onClick may close the parent and unmount this context first.
        menuContext?.close();
    };

    return (
        <MenuItem
            onClick={handleClick}
            selected={selected}
            disabled={disabled}
            sx={(theme) => ({
                minWidth: compact ? 176 : 220,
                color: disabled
                    ? theme.vars.palette.text.muted
                    : theme.vars.palette[color].main,

                "& .MuiSvgIcon-root": { fontSize: compact ? "18px" : "20px" },
                ...(selected && {
                    backgroundColor: "rgba(255, 255, 255, 0.08)",
                    "&:hover": { backgroundColor: "rgba(255, 255, 255, 0.12)" },
                }),
            })}
        >
            <Stack
                direction="row"
                sx={{
                    gap: compact ? 1 : 1.5,
                    alignItems: "center",
                    width: "100%",
                    py: compact ? 0.5 : 1,
                }}
            >
                {startIcon}
                <Typography
                    sx={{
                        flex: 1,
                        fontWeight: "medium",
                        fontSize: compact ? "0.9rem" : undefined,
                    }}
                >
                    {children}
                </Typography>
                {endIcon}
            </Stack>
        </MenuItem>
    );
};
