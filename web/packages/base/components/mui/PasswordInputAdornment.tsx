import VisibilityIcon from "@mui/icons-material/Visibility";
import VisibilityOffIcon from "@mui/icons-material/VisibilityOff";
import { IconButton, InputAdornment } from "@mui/material";
import { t } from "i18next";
import React from "react";

interface ShowHidePasswordInputAdornmentProps {
    showPassword: boolean;
    onToggle: () => void;
}

export const ShowHidePasswordInputAdornment: React.FC<
    ShowHidePasswordInputAdornmentProps
> = ({ showPassword, onToggle }) => {
    // Prevent the visibility button from blurring the password field.
    const preventDefault = (event: React.MouseEvent<HTMLButtonElement>) => {
        event.preventDefault();
    };

    return (
        <InputAdornment position="end">
            <IconButton
                tabIndex={-1}
                color="secondary"
                aria-label={t("show_or_hide_password")}
                onClick={onToggle}
                onMouseUp={preventDefault}
                onMouseDown={preventDefault}
                edge="end"
            >
                {showPassword ? <VisibilityOffIcon /> : <VisibilityIcon />}
            </IconButton>
        </InputAdornment>
    );
};
