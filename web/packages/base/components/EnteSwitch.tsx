import { Switch, styled, type SwitchProps } from "@mui/material";
import React from "react";

export const EnteSwitch: React.FC<SwitchProps> = styled((props) => (
    <Switch disableRipple {...props} />
))(({ theme }) => ({
    width: 40,
    height: 24,
    padding: 0,
    "& .MuiSwitch-switchBase": {
        padding: 0,
        margin: 2,
        transitionDuration: "300ms",
        "&.Mui-checked": {
            transform: "translateX(16px)",
            color: "white",
            "& + .MuiSwitch-track": {
                opacity: 1,
                border: 0,
                backgroundColor: theme.vars.palette.fixed.switchOn,
            },
            "&.Mui-disabled + .MuiSwitch-track": { opacity: 0.5 },
        },
        "&.Mui-disabled .MuiSwitch-thumb": {
            color: theme.vars.palette.grey[600],
            ...theme.applyStyles("light", {
                color: theme.vars.palette.grey[100],
            }),
        },
        "&.Mui-disabled + .MuiSwitch-track": { opacity: 0.3 },
    },
    "& .MuiSwitch-thumb": { boxSizing: "border-box", width: 20, height: 20 },
    "& .MuiSwitch-track": {
        borderRadius: 22 / 2,
        backgroundColor: theme.vars.palette.fill.muted,
        opacity: 1,
        transition: theme.transitions.create(["background-color"], {
            duration: 500,
        }),
    },
    ".MuiSwitch-switchBase.Mui-focusVisible + .MuiSwitch-track": {
        outline: `2px solid ${theme.vars.palette.stroke.muted}`,
        outlineOffset: "-2px",
    },
    ".MuiSwitch-switchBase:active + .MuiSwitch-track": {
        outline: `1px solid ${theme.vars.palette.stroke.faint}`,
        outlineOffset: "-1px",
    },
}));
