import { ViewIcon, ViewOffSlashIcon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { styled } from "@mui/material";
import { t } from "i18next";
import type React from "react";
import { useId, useState } from "react";
import { Message } from "./Message";
import {
    authBodyTypography,
    authFocusRing,
    authMiniTypography,
    authTransientProps,
} from "./styles";

export interface TextFieldProps {
    id?: string;
    label?: React.ReactNode;
    value: string;
    onChange: (
        event: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>,
    ) => void;
    onKeyDown?: (
        event: React.KeyboardEvent<HTMLInputElement | HTMLTextAreaElement>,
    ) => void;
    onBlur?: (
        event: React.FocusEvent<HTMLInputElement | HTMLTextAreaElement>,
    ) => void;
    type?: React.HTMLInputTypeAttribute;
    placeholder?: string;
    required?: boolean;
    disabled?: boolean;
    error?: boolean;
    helperText?: React.ReactNode;
    autoFocus?: boolean;
    autoComplete?: string;
    name?: string;
    showPasswordToggle?: boolean;
    multiline?: boolean;
    rows?: number;
    inputMode?: React.HTMLAttributes<HTMLInputElement>["inputMode"];
    ariaLabel?: string;
    trailing?: React.ReactNode;
}

export function TextField({
    id,
    label,
    value,
    onChange,
    onKeyDown,
    onBlur,
    type = "text",
    placeholder,
    required,
    disabled,
    error,
    helperText,
    autoFocus,
    autoComplete,
    name,
    showPasswordToggle,
    multiline,
    rows = 5,
    inputMode,
    ariaLabel,
    trailing,
}: TextFieldProps): React.JSX.Element {
    const generatedID = useId();
    const inputID = id ?? generatedID;
    const helperID = `${inputID}-helper`;
    const hasHelper = Boolean(helperText);
    const [isPasswordVisible, setIsPasswordVisible] = useState(false);
    const inputType = showPasswordToggle
        ? isPasswordVisible
            ? "text"
            : "password"
        : type;

    function handleInputChange(event: React.ChangeEvent<HTMLInputElement>) {
        onChange(event);
    }

    function handleTextAreaChange(
        event: React.ChangeEvent<HTMLTextAreaElement>,
    ) {
        onChange(event);
    }

    function handlePasswordToggle() {
        setIsPasswordVisible((isVisible) => !isVisible);
    }

    function handlePasswordToggleMouseDown(
        event: React.MouseEvent<HTMLButtonElement>,
    ) {
        event.preventDefault();
    }

    const sharedControlProps = {
        id: inputID,
        value,
        placeholder,
        required,
        disabled,
        autoFocus,
        autoComplete,
        name,
        onBlur,
        "aria-label": ariaLabel,
        "aria-invalid": error || undefined,
        "aria-describedby": hasHelper ? helperID : undefined,
    };

    return (
        <FieldRoot>
            {label && (
                <FieldLabel htmlFor={inputID}>
                    {label}
                    {required && (
                        <RequiredMark aria-hidden="true"> *</RequiredMark>
                    )}
                </FieldLabel>
            )}
            <FieldBox
                $error={Boolean(error)}
                $disabled={Boolean(disabled)}
                $multiline={Boolean(multiline)}
            >
                {multiline ? (
                    <TextAreaControl
                        {...sharedControlProps}
                        rows={rows}
                        onChange={handleTextAreaChange}
                        onKeyDown={onKeyDown}
                    />
                ) : (
                    <TextInputControl
                        {...sharedControlProps}
                        type={inputType}
                        inputMode={inputMode}
                        onChange={handleInputChange}
                        onKeyDown={onKeyDown}
                    />
                )}
                {showPasswordToggle && !multiline && (
                    <PasswordToggle
                        type="button"
                        tabIndex={-1}
                        aria-label={t("show_or_hide_password")}
                        aria-controls={inputID}
                        aria-pressed={isPasswordVisible}
                        disabled={disabled}
                        onClick={handlePasswordToggle}
                        onMouseDown={handlePasswordToggleMouseDown}
                    >
                        <HugeiconsIcon
                            icon={
                                isPasswordVisible ? ViewOffSlashIcon : ViewIcon
                            }
                            size={20}
                            strokeWidth={2}
                            aria-hidden="true"
                        />
                    </PasswordToggle>
                )}
                {trailing}
            </FieldBox>
            <Message
                id={helperID}
                kind={error ? "error" : "info"}
                visible={hasHelper}
            >
                {helperText}
            </Message>
        </FieldRoot>
    );
}

const FieldRoot = styled("div")({
    "--photos-auth-message-gap": "9px",
    width: "100%",
    display: "flex",
    flexDirection: "column",
    gap: "9px",
    "&:focus-within > label": { color: "var(--photos-auth-text)" },
});

const FieldLabel = styled("label")({
    ...authMiniTypography,
    color: "var(--photos-auth-text-muted)",
    transition: "color 100ms ease-in",
    "@media (prefers-reduced-motion: reduce)": { transition: "none" },
});

const RequiredMark = styled("span")({ color: "var(--photos-auth-warning)" });

interface FieldBoxProps {
    $error: boolean;
    $disabled: boolean;
    $multiline: boolean;
}

const FieldBox = styled(
    "div",
    authTransientProps,
)<FieldBoxProps>(({ $error, $disabled, $multiline }) => ({
    width: "100%",
    height: $multiline ? "auto" : "52px",
    minHeight: $multiline ? "112px" : undefined,
    padding: $multiline ? "16px" : "0 16px",
    borderRadius: "16px",
    display: "flex",
    alignItems: $multiline ? "flex-start" : "center",
    gap: "8px",
    boxSizing: "border-box",
    backgroundColor: $disabled
        ? "var(--photos-auth-fill-hover)"
        : "var(--photos-auth-field)",
    boxShadow: $disabled
        ? "none"
        : `inset 0 0 0 1px ${
              $error
                  ? "var(--photos-auth-warning)"
                  : "var(--photos-auth-stroke)"
          }`,
    "&:focus-within": $disabled
        ? undefined
        : {
              boxShadow: `inset 0 0 0 1px ${
                  $error
                      ? "var(--photos-auth-warning)"
                      : "var(--photos-auth-primary)"
              }`,
          },
}));

const controlStyles = {
    ...authBodyTypography,
    width: "100%",
    minWidth: 0,
    flex: 1,
    padding: 0,
    border: 0,
    outline: 0,
    background: "transparent",
    fontFamily: "inherit",
    color: "var(--photos-auth-text)",
    "&::placeholder": { color: "var(--photos-auth-text-faint)", opacity: 1 },
    "&:disabled": {
        color: "var(--photos-auth-text-disabled)",
        WebkitTextFillColor: "var(--photos-auth-text-disabled)",
        cursor: "not-allowed",
    },
};

const TextInputControl = styled("input")({ ...controlStyles });

const TextAreaControl = styled("textarea")({
    ...controlStyles,
    minHeight: "80px",
    resize: "none",
});

const PasswordToggle = styled("button")({
    width: "20px",
    height: "20px",
    flex: "0 0 20px",
    padding: 0,
    border: 0,
    borderRadius: "4px",
    display: "inline-flex",
    alignItems: "center",
    justifyContent: "center",
    background: "transparent",
    color: "var(--photos-auth-text-faint)",
    cursor: "pointer",
    "&:focus-visible": authFocusRing,
    "&:disabled": {
        color: "var(--photos-auth-text-disabled)",
        cursor: "not-allowed",
    },
});
