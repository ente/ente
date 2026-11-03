import {
    Box,
    Divider,
    Stack,
    styled,
    Typography,
    type ButtonProps,
} from "@mui/material";
import { EnteSwitch } from "ente-base/components/EnteSwitch";
import { FocusVisibleButton } from "ente-base/components/mui/FocusVisibleButton";
import React from "react";
import { ActivityIndicator } from "./mui/ActivityIndicator";

interface RowButtonGroupTitleProps {
    icon?: React.ReactNode;
}

export const RowButtonGroupTitle: React.FC<
    React.PropsWithChildren<RowButtonGroupTitleProps>
> = ({ children, icon }) => (
    <Stack
        direction="row"
        sx={{
            px: "8px",
            py: "6px",
            gap: "8px",
            "& > svg": { fontSize: "17px", color: "stroke.muted" },
        }}
    >
        {icon && icon}
        <Typography variant="small" sx={{ color: "text.muted" }}>
            {children}
        </Typography>
    </Stack>
);

export const RowButtonGroupHint: React.FC<React.PropsWithChildren> = ({
    children,
}) => (
    <Typography
        variant="small"
        sx={{ color: "text.faint", px: "16px", py: "6px" }}
    >
        {children}
    </Typography>
);

export const RowButtonDivider = () => <Divider sx={{ opacity: 0.4 }} />;

// Group styling only supports primary RowButtons.
export const RowButtonGroup = styled("div")(
    ({ theme }) => `
    background-color: ${theme.vars.palette.fill.faint};
    border-radius: 8px;
    & > button {
        border-radius: 8px;
        background-color: transparent;
    }
    & > button.Mui-disabled {
        background-color: transparent;
    }
    & > button:not(:last-of-type) {
        border-bottom-left-radius: 0;
        border-bottom-right-radius: 0;
    }
    & > button:not(:first-of-type) {
        border-top-left-radius: 0;
        border-top-right-radius: 0;
    }
    & > button:hover {
        background-color: ${theme.vars.palette.fill.faintHover};
    }
    & > button.Mui-focusVisible  {
        border-radius: 8px;
    }
    & > button:active  {
        outline-offset: 0;
    }
`,
);

interface RowButtonProps {
    variant?: "primary" | "secondary";
    color?: "primary" | "critical";
    fontWeight?: string | number;
    disabled?: boolean;
    onClick: () => void;
    startIcon?: React.ReactNode;
    endIcon?: React.ReactNode;
    label: React.ReactNode;
    caption?: React.ReactNode;
}

export const RowButton: React.FC<RowButtonProps> = ({
    variant = "primary",
    color = "primary",
    fontWeight = "medium",
    disabled = false,
    startIcon,
    endIcon,
    label,
    caption,
    onClick,
}) => (
    <RowButtonRoot rbVariant={variant} fullWidth {...{ disabled, onClick }}>
        <Stack
            direction="row"
            sx={[
                {
                    flex: 1,
                    justifyContent: "space-between",
                    alignItems: "center",
                    px: "16px",
                    pr: "12px",
                    color: "text.base",
                },
                color == "critical" && { color: "critical.main" },
                disabled && { color: "text.muted" },
            ]}
        >
            <Stack
                direction="row"
                sx={{ py: "14px", gap: "10px", alignItems: "center" }}
            >
                {startIcon && startIcon}
                <Box sx={{ px: "2px" }}>
                    {typeof label != "string" ? (
                        label
                    ) : caption ? (
                        <Stack
                            direction="row"
                            sx={{ gap: "4px", alignItems: "center" }}
                        >
                            <Typography sx={{ flexShrink: 0 }}>
                                {label}
                            </Typography>
                            <CaptionTypography color={color}>
                                {"•"}
                            </CaptionTypography>
                            <CaptionTypography color={color}>
                                {caption}
                            </CaptionTypography>
                        </Stack>
                    ) : (
                        <Typography sx={{ fontWeight }}>{label}</Typography>
                    )}
                </Box>
            </Stack>
            {endIcon && endIcon}
        </Stack>
    </RowButtonRoot>
);

type RowButtonRootProps = ButtonProps & {
    rbVariant: RowButtonProps["variant"];
};

const RowButtonRoot = styled(FocusVisibleButton, {
    shouldForwardProp: (prop) => prop != "rbVariant",
})<React.PropsWithChildren<RowButtonRootProps>>(({ theme }) => ({
    padding: 0,
    "& .MuiSvgIcon-root": { fontSize: "20px" },
    variants: [
        {
            props: { rbVariant: "primary" },
            style: {
                backgroundColor: theme.vars.palette.fill.faint,
                "&:hover": { backgroundColor: theme.vars.palette.fill.muted },
            },
        },
        {
            props: { rbVariant: "secondary" },
            style: {
                backgroundColor: "transparent",
                color: "white",
                "&:hover": { backgroundColor: theme.vars.palette.fill.faint },
            },
        },
    ],
}));

const CaptionTypography: React.FC<
    React.PropsWithChildren<{ color: RowButtonProps["color"] }>
> = ({ color, children }) => (
    <Typography
        variant="small"
        sx={[
            color == "critical"
                ? { color: "critical.main" }
                : { color: "text.faint" },
        ]}
    >
        {children}
    </Typography>
);

interface RowSwitchProps {
    checked?: boolean;
    onClick: () => void;
    label: string;
}

export const RowSwitch: React.FC<RowSwitchProps> = ({
    checked,
    label,
    onClick,
}) => (
    <Stack
        component="label"
        direction="row"
        sx={(theme) => ({
            flex: 1,
            justifyContent: "space-between",
            alignItems: "center",
            p: "14px 16px",
            gap: 1,
            cursor: "pointer",
            borderRadius: "8px",
            "&:hover": { bgcolor: "fill.faintHover" },
            "&:has(:focus-visible)": {
                outline: `1px solid ${theme.vars.palette.stroke.base}`,
                outlineOffset: "2px",
            },
        })}
    >
        <Typography component="span" sx={{ fontWeight: "medium" }}>
            {label}
        </Typography>
        <EnteSwitch
            checked={checked}
            onChange={onClick}
            sx={{ flexShrink: 0 }}
        />
    </Stack>
);

interface RowLabelProps {
    startIcon?: React.ReactNode;
    label: string;
}

export const RowLabel: React.FC<RowLabelProps> = ({ startIcon, label }) => (
    <Stack
        direction="row"
        sx={{
            flex: 1,
            justifyContent: "space-between",
            alignItems: "center",
            px: "16px",
            pr: "12px",
        }}
    >
        <Stack direction="row" sx={{ py: "14px", gap: "10px" }}>
            {startIcon && startIcon}
            <Box sx={{ px: "2px" }}>
                <Typography>{label}</Typography>
            </Box>
        </Stack>
    </Stack>
);

export const RowButtonEndActivityIndicator: React.FC = () => (
    <ActivityIndicator size="20px" sx={{ color: "stroke.muted" }} />
);
