import { Tick02Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { styled } from "@mui/material";
import type React from "react";
import {
    authBodyTypography,
    authFocusRing,
    authTransientProps,
} from "./styles";

export interface CheckboxProps extends Omit<
    React.InputHTMLAttributes<HTMLInputElement>,
    "checked" | "children" | "onChange" | "type"
> {
    checked: boolean;
    onChange: (checked: boolean) => void;
    label?: React.ReactNode;
}

export function Checkbox({
    checked,
    onChange,
    disabled,
    label,
    ...inputProps
}: CheckboxProps): React.JSX.Element {
    function handleChange(event: React.ChangeEvent<HTMLInputElement>) {
        onChange(event.target.checked);
    }

    return (
        <CheckboxRoot $disabled={Boolean(disabled)}>
            <CheckboxInput
                type="checkbox"
                checked={checked}
                onChange={handleChange}
                disabled={disabled}
                {...inputProps}
            />
            <CheckboxMark aria-hidden="true">
                {checked && (
                    <HugeiconsIcon
                        icon={Tick02Icon}
                        size={11}
                        strokeWidth={3}
                    />
                )}
            </CheckboxMark>
            {label && <CheckboxLabelText>{label}</CheckboxLabelText>}
        </CheckboxRoot>
    );
}

const CheckboxRoot = styled(
    "label",
    authTransientProps,
)<{ $disabled: boolean }>(({ $disabled }) => ({
    display: "inline-flex",
    alignItems: "flex-start",
    gap: "8px",
    position: "relative",
    cursor: $disabled ? "not-allowed" : "pointer",
}));

const CheckboxInput = styled("input")({
    width: "1px",
    height: "1px",
    margin: 0,
    padding: 0,
    position: "absolute",
    overflow: "hidden",
    clip: "rect(0 0 0 0)",
    clipPath: "inset(50%)",
    whiteSpace: "nowrap",
});

const CheckboxMark = styled("span")({
    width: "16px",
    height: "16px",
    flex: "0 0 16px",
    marginTop: "2px",
    borderRadius: "4px",
    display: "inline-flex",
    alignItems: "center",
    justifyContent: "center",
    boxSizing: "border-box",
    color: "#fff",
    backgroundColor: "var(--locker-auth-primary)",
    "input:disabled + &": {
        backgroundColor: "var(--locker-auth-text-disabled)",
    },
    "input:not(:checked) + &": {
        backgroundColor: "transparent",
        boxShadow: "inset 0 0 0 1px var(--locker-auth-text-faint)",
    },
    "input:not(:checked):disabled + &": {
        boxShadow: "inset 0 0 0 1px var(--locker-auth-text-disabled)",
    },
    "input:focus-visible + &": authFocusRing,
});

const CheckboxLabelText = styled("span")({
    ...authBodyTypography,
    color: "var(--locker-auth-text)",
});
