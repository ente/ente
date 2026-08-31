import { Stack, styled, Typography } from "@mui/material";
import { LoadingButton } from "ente-base/components/mui/LoadingButton";
import { isHTTP401Error } from "ente-base/http";
import log from "ente-base/log";
import { useFormik } from "formik";
import { t } from "i18next";
import React, { useEffect, useRef } from "react";

const otpLength = 6;

interface OTPInputProps {
    onChange: (value: string) => void;
    value: string;
}

const OTPInput: React.FC<OTPInputProps> = ({ onChange, value }) => {
    const inputRefs = useRef<(HTMLInputElement | null)[]>([]);

    useEffect(() => {
        if (value.length === 0) inputRefs.current[0]?.focus();
    }, [value]);

    const isInputValueValid = (input: string) =>
        !isNaN(Number(input)) && input.trim().length === 1;

    const focusInput = (index: number) => {
        const nextIndex = Math.max(Math.min(otpLength - 1, index), 0);
        const input = inputRefs.current[nextIndex];
        if (input) {
            input.focus();
            input.select();
        }
    };

    const updateDigit = (index: number, digit: string) => {
        const otp = value.split("");
        otp[index] = digit;
        onChange(otp.join(""));
    };

    const handleChange = (
        index: number,
        event: React.ChangeEvent<HTMLInputElement>,
    ) => {
        const input = event.currentTarget.value;
        if (isInputValueValid(input)) {
            updateDigit(index, input);
            focusInput(index + 1);
        }
    };

    const handleInput = (
        index: number,
        event: React.SyntheticEvent<HTMLInputElement, InputEvent>,
    ) => {
        const nativeEvent = event.nativeEvent;
        const input = event.currentTarget.value;
        if (!isInputValueValid(input)) {
            if (
                input.length === otpLength &&
                !input.split("").some((digit) => !isInputValueValid(digit))
            ) {
                onChange(input);
                focusInput(otpLength - 1);
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
    };

    const handleKeyDown = (
        index: number,
        event: React.KeyboardEvent<HTMLInputElement>,
    ) => {
        const otp = value.split("");
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
        } else if (event.key === otp[index]) {
            event.preventDefault();
            focusInput(index + 1);
        } else if (
            event.code === "Spacebar" ||
            event.code === "Space" ||
            event.code === "ArrowUp" ||
            event.code === "ArrowDown"
        ) {
            event.preventDefault();
        }
    };

    const handlePaste = (
        index: number,
        event: React.ClipboardEvent<HTMLInputElement>,
    ) => {
        event.preventDefault();
        const otp = value.split("");
        const pastedData = event.clipboardData
            .getData("text/plain")
            .slice(0, otpLength - index)
            .split("");

        if (pastedData.some((digit) => !isInputValueValid(digit))) return;

        pastedData.forEach((digit, offset) => {
            otp[index + offset] = digit;
        });

        focusInput(index + pastedData.length);
        onChange(otp.join(""));
    };

    return (
        <Stack
            direction="row"
            sx={{ alignItems: "center", justifyContent: "center" }}
        >
            {Array.from({ length: otpLength }, (_, index) => (
                <React.Fragment key={index}>
                    {index > 0 && <span>-</span>}
                    <IndividualInput
                        ref={(element) => {
                            inputRefs.current[index] = element;
                        }}
                        aria-label={`Please enter OTP character ${index + 1}`}
                        autoComplete={index === 0 ? "one-time-code" : "off"}
                        inputMode="numeric"
                        name={index === 0 ? "otp" : undefined}
                        onChange={(event) => handleChange(index, event)}
                        onFocus={(event) => event.currentTarget.select()}
                        onInput={(event) => handleInput(index, event)}
                        onKeyDown={(event) => handleKeyDown(index, event)}
                        onPaste={(event) => handlePaste(index, event)}
                        pattern="[0-9]*"
                        type="tel"
                        value={value[index] ?? ""}
                    />
                </React.Fragment>
            ))}
        </Stack>
    );
};

interface Verify2FACodeFormProps {
    onSubmit: (otp: string) => Promise<void>;
    submitButtonText: string;
}

export const Verify2FACodeForm: React.FC<Verify2FACodeFormProps> = ({
    onSubmit,
    submitButtonText,
}) => {
    const {
        values,
        errors,
        handleChange,
        handleSubmit,
        submitForm,
        isSubmitting,
    } = useFormik<{ otp: string }>({
        initialValues: { otp: "" },
        validateOnBlur: false,
        validateOnChange: false,
        onSubmit: async ({ otp }, { setFieldError, resetForm }) => {
            try {
                await onSubmit(otp);
                // Reset the form, otherwise the auto-submit effect below
                // resubmits.
                resetForm();
            } catch (e) {
                log.error("Failed to submit 2FA code", e);
                resetForm();
                setFieldError(
                    "otp",
                    isHTTP401Error(e)
                        ? t("incorrect_code")
                        : t("generic_error"),
                );
            }
        },
    });

    useEffect(() => {
        if (values.otp.length == 6 && !isSubmitting) void submitForm();
    }, [values, isSubmitting, submitForm]);

    return (
        <form onSubmit={handleSubmit}>
            <Stack sx={{ gap: 3, textAlign: "center" }}>
                <Typography variant="small" sx={{ color: "text.muted" }}>
                    {t("enter_two_factor_otp")}
                </Typography>
                <OTPInput value={values.otp} onChange={handleChange("otp")} />
                {errors.otp && (
                    <Typography variant="mini" sx={{ color: "critical.main" }}>
                        {errors.otp}
                    </Typography>
                )}
                <LoadingButton
                    type="submit"
                    color="accent"
                    fullWidth
                    loading={isSubmitting}
                    disabled={values.otp.length < 6}
                >
                    {submitButtonText}
                </LoadingButton>
            </Stack>
        </form>
    );
};

const IndividualInput = styled("input")(
    ({ theme }) => `
    box-sizing: border-box;
    font-size: 1.5rem;
    text-align: center;
    padding: 4px;
    width: 40px !important;
    aspect-ratio: 1;
    margin-inline: 6px;
    border: 1px solid ${theme.vars.palette.accent.main};
    border-radius: 1px;
    outline-color: ${theme.vars.palette.accent.light};
    transition: 0.5s;
    ${theme.breakpoints.down("sm")} {
        font-size: 1rem;
        padding: 4px;
        width: 32px !important;
    }
`,
);
