import { Typography, useTheme } from "@mui/material";
import { t } from "i18next";
import React, { useMemo } from "react";
import { estimatePasswordStrength } from "../utils/password";

interface PasswordStrengthHintProps {
    password: string;
}

export const PasswordStrengthHint: React.FC<PasswordStrengthHintProps> = ({
    password,
}) => {
    const passwordStrength = useMemo(
        () => estimatePasswordStrength(password),
        [password],
    );

    const theme = useTheme();
    const color =
        passwordStrength == "weak"
            ? theme.vars.palette.critical.main
            : passwordStrength == "moderate"
              ? theme.vars.palette.warning.main
              : theme.vars.palette.accent.main;

    return (
        <Typography
            variant="small"
            sx={{
                mt: "8px",
                mx: "2px",
                alignSelf: "flex-start",
                whiteSpace: "pre",
                color: "var(--et-color)",
            }}
            style={{ "--et-color": color } as React.CSSProperties}
        >
            {password
                ? t("password_strength", { context: passwordStrength })
                : /* empty space + white-space: pre to prevent layout shift. */
                  " "}
        </Typography>
    );
};
