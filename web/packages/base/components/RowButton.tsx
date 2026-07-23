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
    /**
     * An optional leading SvgIcon before the title.
     */
    icon?: React.ReactNode;
}

/**
 * A section title, meant to precede a {@link RowButtonGroup}.
 */
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

/**
 * A short description text meant to come after a {@link RowButtonGroup}.
 */
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

/**
 * A divider for buttons in a {@link RowButtonGroup}.
 */
export const RowButtonDivider = () => (
    <Divider sx={{ "&&&": { mttty: 0 }, opacity: 0.4 }} />
);

/**
 * A group of {@link RowButton}s that visually look together as a single
 * section.
 *
 * {@link RowButtonGroupTitle} can be used to provide a title for the entire
 * group, and {@link RowButtonGroupHint} can be used to provide a hint text that
 * follows the group.
 *
 * {@link RowButtonDivider} can be used to to separate the individual buttons in
 * the group.
 *
 * ---
 *
 * Note: {@link RowButtonGroup} is not designed to work with the "secondary"
 * variant of {@link RowButton}.
 */
export const RowButtonGroup = styled("div")(
    ({ theme }) => `
    background-color: ${theme.vars.palette.fill.faint};
    border-radius: 8px;
    /* Modify the RowButton style when it is placed inside a RowButtonGroup. */
    & > button {
        border-radius: 8px;
        background-color: transparent;
    }
    /* Need to retarget the disabled state with increased specificity. */
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
        /* These fills are translucent and additive, and the RowButtonGroup
           already has a background, so pick a (transparent) color that gives us
           a similar outcome of the hover state as for a RowButton that is not
           inside a RowButtonGroup */
        background-color: ${theme.vars.palette.fill.faintHover};
    }
    /* Reset the border radius when showing focus outlines that will be added
       by the styles attached to FocusVisibleButton. */
    & > button.Mui-focusVisible  {
        border-radius: 8px;
    }
    /* Modify the outline offset added by FocusVisibleButton for a visual
       effect that fits better with these row buttons. */
    & > button:active  {
        outline-offset: 0;
    }
`,
);

interface RowButtonProps {
    /**
     * Variants:
     *
     * - "primary" (default): A row button with a filled in background color.
     *
     * - "secondary": A row button without a fill.
     */
    variant?: "primary" | "secondary";
    /**
     * Color of the row button.
     *
     * Semantically, this is similar to the "color" props for a MUI button,
     * except we only support two cases for this row button component:
     *
     * - "primary" (default): A row button that uses "text.base" as the color of
     *   the text (and an appropriate background color, if needed, based on the
     *   value of the {@link variant}).
     *
     * - "critical": A row button that uses "critical.main" as the color of the
     *   text. The background fill, if any, will be the same as what "primary"
     *   would've entailed.
     */
    color?: "primary" | "critical";
    /**
     * Modify the font weight of the {@link label}, when label is a string.
     *
     * Default: "medium".
     */
    fontWeight?: string | number;
    /**
     * If true, then the row button will be disabled.
     */
    disabled?: boolean;
    /**
     * Called when the row button is activated (e.g. by a click).
     */
    onClick: () => void;
    /**
     * Optional icon shown at the leading edge of the row button.
     *
     * This is usually an icon like an {@link SvgIcon}, but it can be any
     * arbitrary component, the row button does not make any assumptions as to
     * what this is.
     *
     * If it is an {@link SvgIcon}, the row button will size it appropriately.
     */
    startIcon?: React.ReactNode;
    /**
     * Optional icon shown at the trailing edge of the row button.
     *
     * Similar to {@link startIcon} this can be any arbitrary component, though
     * usually it is an {@link SvgIcon} whose size the row button will set.
     */
    endIcon?: React.ReactNode;
    /**
     * The label for the component.
     *
     * Usually this is expected to be a string, in which case it is wrapped up
     * in an appropriate {@link Typography} and shown on the row button. But it
     * can be an arbitrary react component too, to allow customizing its
     * appearance or otherwise modifying it in one off cases (it will be used as
     * it is and not wrapped in a {@link Typography} if it is not a string).
     */
    label: React.ReactNode;
    /**
     * The text (or icon) to show alongside {@link label}, separated from it by
     * a bullet.
     *
     * This is usually expected to be a string, in which case it is wrapped in a
     * {@link Typography} component and styled with a muted text color before
     * being rendered.
     *
     * However, it can also be an {@link SvgIcon} (or any an arbitrary
     * component), though in terms of styling, only an {@link SvgIcon} usually
     * makes sense.
     *
     * Similar to {@link label}, it will not be wrapped in a {@link Typography}
     * if it is not a string.
     */
    caption?: React.ReactNode;
}

/**
 * A button that looks like a row in a group of options / choices.
 *
 * It can be used both standalone, or as part of a {@link RowButtonGroup}.
 */
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
                            {/* Don't shrink the main label, instead let the
                                caption grow into two lines if it needs to. */}
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
    // Prefix with "rb" to differentiate this from the "variant" prop of the MUI
    // button that we're styling.
    rbVariant: RowButtonProps["variant"];
};

const RowButtonRoot = styled(FocusVisibleButton, {
    shouldForwardProp: (prop) => prop != "rbVariant",
    // name: "MuiMenuItem",
})<React.PropsWithChildren<RowButtonRootProps>>(({ theme }) => ({
    // Remove button's default padding.
    padding: 0,
    // Set the size of the any icons (SvgIcon instances) provided to us to make
    // them fit with the Typography within the button's content.
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
    /**
     * The state of the contained {@link EnteSwitch}.
     */
    checked?: boolean;
    /**
     * Called when the user activates the contained {@link EnteSwitch}.
     */
    onClick: () => void;
    /**
     * The label for the component.
     *
     * Similar to the {@link label} prop for {@link RowButton}, but can only be
     * a string instead of an arbitrary component.
     */
    label: string;
}

/**
 * A row that visually looks similar to a {@link RowButton}, but instead of a
 * button is a normal {@link Typography} with a {@link EnteSwitch} at its
 * trailing edge.
 *
 * It only works (visually) when placed within a {@link RowButtonGroup} since
 * that is where it gets its background color from.
 */
export const RowSwitch: React.FC<RowSwitchProps> = ({
    checked,
    label,
    onClick,
}) => (
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
        <Typography sx={{ py: "14px", px: "2px", fontWeight: "medium" }}>
            {label}
        </Typography>
        <EnteSwitch {...{ checked, onClick }} />
    </Stack>
);

interface RowLabelProps {
    /**
     * Optional icon shown at the leading edge of the row button.
     *
     * This is usually an icon like an {@link SvgIcon}, but it can be any
     * arbitrary component, the row button does not make any assumptions as to
     * what this is.
     *
     * Unlike a {@link RowButton}, there is not sizing applied to it.
     */
    startIcon?: React.ReactNode;
    /**
     * The label for the component.
     *
     * Similar to the {@link label} prop for {@link RowButton}, but can only be
     * a string instead of an arbitrary component.
     */
    label: string;
}

/**
 * A row that visually looks similar to a {@link RowButton}, but instead of a
 * button is a normal {@link Typography}.
 *
 * This is useful for creating non-interactive, static, labels.
 *
 * It only works (visually) when placed within a {@link RowButtonGroup} since
 * that is where it gets its background color from.
 */
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
                {/* Nb: Unlike the button, this has "regular" fontWeight. */}
                <Typography>{label}</Typography>
            </Box>
        </Stack>
    </Stack>
);

/**
 * A variant of {@link ActivityIndicator} with defaults suitable to be used as the
 * {@link EndIcon} of a {@link RowButton}.
 */
export const RowButtonEndActivityIndicator: React.FC = () => (
    <ActivityIndicator size="20px" sx={{ color: "stroke.muted" }} />
);
