import { styled } from "@mui/material";
import { t } from "i18next";
import type React from "react";
import { useEffect, useRef } from "react";
import {
    authDisplayFontFamily,
    authMiniTypography,
    authTransientProps,
} from "./styles";

export interface OTPFieldProps {
    id?: string;
    name?: string;
    label?: React.ReactNode;
    value: string;
    onChange: (value: string) => void;
    length?: number;
    error?: boolean;
    disabled?: boolean;
    autoFocus?: boolean;
    ariaLabel?: string;
    ariaDescribedBy?: string;
}

export function OTPField({
    id,
    name,
    label,
    value,
    onChange,
    length = 6,
    error = false,
    disabled = false,
    autoFocus,
    ariaLabel,
    ariaDescribedBy,
}: OTPFieldProps): React.JSX.Element {
    const inputRefs = useRef<(HTMLInputElement | null)[]>([]);
    const wasDisabled = useRef(disabled);
    const hadError = useRef(error);

    useEffect(() => {
        if (autoFocus && value.length === 0) inputRefs.current[0]?.focus();
    }, [autoFocus, value]);

    function isInputValueValid(input: string) {
        return !isNaN(Number(input)) && input.trim().length === 1;
    }

    function focusInput(index: number) {
        const nextIndex = Math.max(Math.min(length - 1, index), 0);
        const input = inputRefs.current[nextIndex];
        if (input) {
            input.focus();
            input.select();
        }
    }

    useEffect(() => {
        const shouldRestoreFocus =
            error && !disabled && (wasDisabled.current || !hadError.current);

        wasDisabled.current = disabled;
        hadError.current = error;

        if (shouldRestoreFocus) {
            const index = Math.max(
                Math.min(value.trimEnd().length - 1, length - 1),
                0,
            );
            const input = inputRefs.current[index];
            input?.focus();
            input?.select();
        }
    }, [disabled, error, length, value]);

    function updateDigit(index: number, digit: string) {
        const otp = value.padEnd(length, " ").slice(0, length).split("");
        otp[index] = digit || " ";
        onChange(otp.join(""));
    }

    function handleChange(
        index: number,
        event: React.ChangeEvent<HTMLInputElement>,
    ) {
        const input = event.currentTarget.value;
        if (isInputValueValid(input)) {
            updateDigit(index, input);
            focusInput(index + 1);
        }
    }

    function handleInput(
        index: number,
        event: React.SyntheticEvent<HTMLInputElement, InputEvent>,
    ) {
        const nativeEvent = event.nativeEvent;
        const input = event.currentTarget.value;
        if (!isInputValueValid(input)) {
            if (
                input.length === length &&
                !input.split("").some((digit) => !isInputValueValid(digit))
            ) {
                onChange(input);
                focusInput(length - 1);
            }

            if (
                nativeEvent.data === null &&
                nativeEvent.inputType === "deleteContentBackward"
            ) {
                event.preventDefault();
                updateDigit(index, "");
                focusInput(index - 1);
            }

            event.currentTarget.value = "";
        }
    }

    function handleKeyDown(
        index: number,
        event: React.KeyboardEvent<HTMLInputElement>,
    ) {
        const otp = value.padEnd(length, " ").slice(0, length).split("");
        if ([event.code, event.key].includes("Backspace")) {
            event.preventDefault();
            updateDigit(index, "");
            focusInput(index - 1);
        } else if (event.code === "Delete") {
            event.preventDefault();
            updateDigit(index, "");
        } else if (event.code === "ArrowLeft") {
            event.preventDefault();
            focusInput(index - 1);
        } else if (event.code === "ArrowRight") {
            event.preventDefault();
            focusInput(index + 1);
        } else if (event.code === "Spacebar" || event.code === "Space") {
            event.preventDefault();
        } else if (event.key === otp[index]) {
            event.preventDefault();
            focusInput(index + 1);
        } else if (event.code === "ArrowUp" || event.code === "ArrowDown") {
            event.preventDefault();
        }
    }

    function handlePaste(
        index: number,
        event: React.ClipboardEvent<HTMLInputElement>,
    ) {
        event.preventDefault();
        const otp = value.padEnd(length, " ").slice(0, length).split("");
        const pastedData = event.clipboardData
            .getData("text/plain")
            .slice(0, length - index)
            .split("");

        if (pastedData.some((digit) => !isInputValueValid(digit))) return;

        pastedData.forEach((digit, offset) => {
            otp[index + offset] = digit;
        });

        focusInput(index + pastedData.length);
        onChange(otp.join(""));
    }

    const inputAriaLabel = ariaLabel ?? t("verification_code");

    return (
        <OTPFieldRoot>
            {label && <OTPLabel>{label}</OTPLabel>}
            <OTPRoot $disabled={disabled}>
                {Array.from({ length }, (_, index) => (
                    <OTPInput
                        key={index}
                        ref={(element) => {
                            inputRefs.current[index] = element;
                        }}
                        id={index === 0 ? id : undefined}
                        name={index === 0 ? name : undefined}
                        type="tel"
                        value={value[index]?.trim() ?? ""}
                        onChange={(event) => handleChange(index, event)}
                        onFocus={(event) => event.currentTarget.select()}
                        onInput={(event) => handleInput(index, event)}
                        onKeyDown={(event) => handleKeyDown(index, event)}
                        onPaste={(event) => handlePaste(index, event)}
                        disabled={disabled}
                        autoFocus={autoFocus && index === 0}
                        inputMode="numeric"
                        pattern="[0-9]*"
                        autoComplete={index === 0 ? "one-time-code" : "off"}
                        aria-label={`${inputAriaLabel} ${index + 1}`}
                        aria-describedby={ariaDescribedBy}
                        aria-invalid={error || undefined}
                        $error={error}
                    />
                ))}
            </OTPRoot>
        </OTPFieldRoot>
    );
}

const OTPFieldRoot = styled("div")({
    width: "100%",
    display: "flex",
    flexDirection: "column",
    gap: "16px",
    "&:focus-within > span": { color: "var(--auth-app-text)" },
});

const OTPLabel = styled("span")({
    ...authMiniTypography,
    color: "var(--auth-app-text-muted)",
    transition: "color 100ms ease-in",
    "@media (prefers-reduced-motion: reduce)": { transition: "none" },
});

const OTPRoot = styled(
    "div",
    authTransientProps,
)<{ $disabled: boolean }>(({ $disabled }) => ({
    width: "100%",
    display: "flex",
    gap: "8px",
    position: "relative",
    containerType: "inline-size",
    cursor: $disabled ? "not-allowed" : "text",
}));

const OTPInput = styled(
    "input",
    authTransientProps,
)<{ $error: boolean }>(({ $error }) => ({
    aspectRatio: "44 / 52",
    minWidth: 0,
    flex: "1 1 0",
    padding: 0,
    border: 0,
    borderRadius: "16px",
    boxSizing: "border-box",
    fontFamily: authDisplayFontFamily,
    fontSize: "clamp(20px, 6.6cqi, 30px)",
    fontWeight: 600,
    lineHeight: 1,
    textAlign: "center",
    color: "var(--auth-app-text)",
    backgroundColor: "var(--auth-app-field)",
    boxShadow: `inset 0 0 0 1px ${
        $error ? "var(--auth-app-warning)" : "var(--auth-app-stroke)"
    }`,
    outline: 0,
    cursor: "text",
    transition: "box-shadow 0.2s ease",
    "&:focus": {
        boxShadow: `inset 0 0 0 1px ${
            $error ? "var(--auth-app-warning)" : "var(--auth-app-primary)"
        }`,
    },
    "&:disabled": { cursor: "not-allowed" },
}));
