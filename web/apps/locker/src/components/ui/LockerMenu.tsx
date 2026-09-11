import CheckRoundedIcon from "@mui/icons-material/CheckRounded";
import MoreHorizIcon from "@mui/icons-material/MoreHoriz";
import {
    Box,
    IconButton,
    MenuItem,
    Typography,
    type IconButtonProps,
} from "@mui/material";
import Menu, { type MenuProps } from "@mui/material/Menu";
import { t } from "i18next";
import React, { createContext, useContext, useMemo, useState } from "react";
import { lockerMenuPaperSx } from "../../styles/dialog";
import {
    lockerColorSx,
    lockerTextBodySx,
    lockerTextMiniSx,
} from "../../styles/tokens";

const LockerMenuContext = createContext<{ close: () => void } | undefined>(
    undefined,
);

export const LockerOverflowMenu: React.FC<
    React.PropsWithChildren<{
        ariaID: string;
        triggerButtonIcon?: React.ReactNode;
        triggerButtonSxProps?: IconButtonProps["sx"];
    }>
> = ({ ariaID, triggerButtonIcon, triggerButtonSxProps, children }) => {
    const [anchorEl, setAnchorEl] = useState<MenuProps["anchorEl"]>();
    const context = useMemo(
        () => ({ close: () => setAnchorEl(undefined) }),
        [],
    );
    return (
        <LockerMenuContext value={context}>
            <IconButton
                aria-label={t("more")}
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
                    paper: { sx: lockerMenuPaperSx },
                    list: { disablePadding: true, "aria-labelledby": ariaID },
                }}
                anchorOrigin={{ vertical: "bottom", horizontal: "right" }}
                transformOrigin={{ vertical: "top", horizontal: "right" }}
            >
                {children}
            </Menu>
        </LockerMenuContext>
    );
};

export const LockerMenuOption: React.FC<
    React.PropsWithChildren<{
        onClick: () => void;
        critical?: boolean;
        disabled?: boolean;
        selected?: boolean;
        startIcon?: React.ReactNode;
        secondary?: string;
    }>
> = ({
    onClick,
    critical,
    disabled,
    selected,
    startIcon,
    secondary,
    children,
    ...rest
}) => {
    const menuContext = useContext(LockerMenuContext);
    return (
        <MenuItem
            {...rest}
            onClick={() => {
                onClick();
                menuContext?.close();
            }}
            disabled={disabled}
            selected={selected}
            sx={(theme) => ({
                height: 44,
                minHeight: 44,
                px: "10px",
                gap: "10px",
                borderRadius: "10px",
                alignItems: "center",
                "&.Mui-disabled": { opacity: 0.5 },
                "&.Mui-selected": lockerColorSx(theme, {
                    backgroundColor: "primaryLight",
                }),
                "&:hover, &.Mui-selected:hover": lockerColorSx(theme, {
                    backgroundColor: critical ? "warningLight" : "fillHover",
                }),
            })}
        >
            {startIcon && (
                <Box
                    sx={(theme) => ({
                        display: "flex",
                        alignItems: "center",
                        flexShrink: 0,
                        ...lockerColorSx(theme, {
                            color: critical ? "warning" : "textLight",
                        }),
                        "& .MuiSvgIcon-root": { fontSize: 18 },
                    })}
                >
                    {startIcon}
                </Box>
            )}
            <Typography
                noWrap
                sx={(theme) => ({
                    ...lockerTextBodySx,
                    flex: 1,
                    minWidth: 0,
                    ...lockerColorSx(theme, {
                        color: critical ? "warning" : "textBase",
                    }),
                })}
            >
                {children}
            </Typography>
            {secondary !== undefined && (
                <Typography
                    sx={(theme) => ({
                        ...lockerTextMiniSx,
                        flexShrink: 0,
                        ...lockerColorSx(theme, { color: "textLight" }),
                    })}
                >
                    · {secondary}
                </Typography>
            )}
            {selected && (
                <CheckRoundedIcon
                    sx={(theme) => ({
                        fontSize: 18,
                        ...lockerColorSx(theme, { color: "primary" }),
                    })}
                />
            )}
        </MenuItem>
    );
};

export const LockerMenuFooter: React.FC<
    React.PropsWithChildren<{ onClick: () => void }>
> = ({ onClick, children, ...rest }) => (
    <MenuItem
        {...rest}
        onClick={onClick}
        sx={(theme) => ({
            ...lockerTextMiniSx,
            height: 44,
            minHeight: 44,
            borderRadius: "10px",
            borderTop: "1px solid",
            width: "100%",
            justifyContent: "center",
            textDecoration: "underline",
            textUnderlineOffset: "3px",
            textTransform: "none",
            ...lockerColorSx(theme, {
                color: "textLight",
                borderColor: "strokeFaint",
            }),
            "&:hover": lockerColorSx(theme, { backgroundColor: "fillHover" }),
        })}
    >
        {children}
    </MenuItem>
);
