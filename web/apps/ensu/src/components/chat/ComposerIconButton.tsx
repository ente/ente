import { HugeiconsIcon, type IconSvgElement } from "@hugeicons/react";
import { IconButton, styled, type IconButtonProps } from "@mui/material";
import { alpha } from "@mui/material/styles";

const primaryColor = "#E66A28";

const StyledIconButton = styled(IconButton)(({ theme }) => ({
    width: 44,
    height: 44,
    padding: 0,
    flexShrink: 0,
    borderRadius: `calc(${theme.vars.shape.borderRadius} * 2)`,
    backgroundColor: "transparent",
    color: theme.vars.palette.text.base,
    "& svg": { flexShrink: 0 },
    "&:hover": { backgroundColor: theme.vars.palette.fill.faint },
    "&.Mui-disabled": { color: theme.vars.palette.text.faint },
    variants: [
        {
            props: { size: "small" },
            style: {
                width: 32,
                height: 32,
                borderRadius: theme.shape.borderRadius,
            },
        },
        {
            props: { color: "primary" },
            style: {
                color: primaryColor,
                "&.Mui-disabled": { color: alpha(primaryColor, 0.45) },
            },
        },
    ],
}));

export function ComposerIconButton({
    icon,
    ...props
}: Omit<IconButtonProps, "children"> & { icon: IconSvgElement }) {
    return (
        <StyledIconButton {...props}>
            <HugeiconsIcon
                icon={icon}
                size={props.size === "small" ? 18 : 24}
                strokeWidth={2}
                absoluteStrokeWidth
            />
        </StyledIconButton>
    );
}
