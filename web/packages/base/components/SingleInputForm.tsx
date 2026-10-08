import {
    ButtonBase,
    CircularProgress,
    InputBase,
    Stack,
    TextField,
    Typography,
    type ButtonProps,
    type TextFieldProps,
} from "@mui/material";
import { FocusVisibleButton } from "ente-base/components/mui/FocusVisibleButton";
import { LoadingButton } from "ente-base/components/mui/LoadingButton";
import log from "ente-base/log";
import { useFormik } from "formik";
import { t } from "i18next";
import React, { useCallback, useId, useState } from "react";
import {
    peopleActionFocusSx,
    v2CancelButtonSx,
    v2HelperSx,
    v2InputSx,
    v2LabelSx,
    v2SubmitButtonSx,
} from "./SingleInput.styles";
import { ShowHidePasswordInputAdornment } from "./mui/PasswordInputAdornment";

export type SingleInputFormProps = Pick<
    TextFieldProps,
    "label" | "placeholder" | "autoComplete" | "autoFocus" | "slotProps"
> & {
    variant?: "default" | "v2" | "people";
    inputType?: TextFieldProps["type"];
    initialValue?: string;
    submitButtonColor?: ButtonProps["color"];
    submitButtonTitle: string;
    onCancel?: () => void;
    // Do not throw after setFieldError; the catch replaces it with a generic error.
    onSubmit:
        | ((name: string, setFieldError: (message: string) => void) => void)
        | ((
              name: string,
              setFieldError: (message: string) => void,
          ) => Promise<void>);
};

export const SingleInputForm: React.FC<SingleInputFormProps> = ({
    variant = "default",
    inputType,
    initialValue,
    autoFocus,
    submitButtonTitle,
    submitButtonColor,
    onCancel,
    onSubmit,
    ...rest
}) => {
    const inputID = useId();
    const helperID = useId();
    const [showPassword, setShowPassword] = useState(false);

    const handleToggleShowHidePassword = useCallback(
        () => setShowPassword((show) => !show),
        [],
    );

    const formik = useFormik({
        initialValues: { value: initialValue ?? "" },
        enableReinitialize: variant !== "default",
        onSubmit: async (values, { setFieldError }) => {
            const value = values.value;
            const setValueFieldError = (message: string) =>
                setFieldError("value", message);

            if (!value) {
                setValueFieldError(t("required"));
                return;
            }
            try {
                await onSubmit(value, setValueFieldError);
            } catch (e) {
                log.error(`Failed to submit input ${value}`, e);
                setValueFieldError(t("generic_error"));
            }
        },
    });

    if (variant !== "default") {
        const error = formik.errors.value;
        return (
            <Stack
                component="form"
                onSubmit={formik.handleSubmit}
                sx={{ gap: "20px" }}
            >
                <Stack sx={{ gap: "8px" }}>
                    {rest.label && (
                        <Typography
                            component={variant === "people" ? "label" : "p"}
                            htmlFor={variant === "people" ? inputID : undefined}
                            sx={v2LabelSx}
                        >
                            {rest.label}
                        </Typography>
                    )}
                    <InputBase
                        id={variant === "people" ? inputID : undefined}
                        aria-describedby={
                            variant === "people" && error ? helperID : undefined
                        }
                        name="value"
                        value={formik.values.value}
                        onChange={formik.handleChange}
                        type={inputType ?? "text"}
                        placeholder={rest.placeholder}
                        autoComplete={rest.autoComplete}
                        autoFocus={autoFocus ?? true}
                        disabled={formik.isSubmitting}
                        error={!!error}
                        sx={v2InputSx}
                    />
                    <Typography
                        id={variant === "people" ? helperID : undefined}
                        aria-live={variant === "people" ? "polite" : undefined}
                        sx={v2HelperSx(!!error)}
                    >
                        {error ?? ""}
                    </Typography>
                </Stack>
                <Stack direction="row" sx={{ gap: "12px" }}>
                    {onCancel && (
                        <ButtonBase
                            onClick={onCancel}
                            disabled={formik.isSubmitting}
                            sx={[
                                v2CancelButtonSx,
                                variant === "people" && peopleActionFocusSx,
                            ]}
                        >
                            {t("cancel")}
                        </ButtonBase>
                    )}
                    <ButtonBase
                        type="submit"
                        disabled={formik.isSubmitting}
                        sx={[
                            v2SubmitButtonSx,
                            variant === "people" && peopleActionFocusSx,
                        ]}
                    >
                        {formik.isSubmitting ? (
                            <CircularProgress
                                size={20}
                                sx={{ color: "#fff" }}
                            />
                        ) : (
                            submitButtonTitle
                        )}
                    </ButtonBase>
                </Stack>
            </Stack>
        );
    }

    const submitButton = (
        <LoadingButton
            fullWidth
            type="submit"
            loading={formik.isSubmitting}
            color={submitButtonColor ?? "accent"}
        >
            {submitButtonTitle}
        </LoadingButton>
    );

    return (
        <form onSubmit={formik.handleSubmit}>
            <TextField
                name="value"
                value={formik.values.value}
                onChange={formik.handleChange}
                type={showPassword ? "text" : (inputType ?? "text")}
                fullWidth
                autoFocus={autoFocus ?? true}
                margin="normal"
                disabled={formik.isSubmitting}
                error={!!formik.errors.value}
                // The space reserves helper-text height before an error appears.
                helperText={formik.errors.value ?? " "}
                slotProps={{
                    input:
                        inputType == "password"
                            ? {
                                  endAdornment: (
                                      <ShowHidePasswordInputAdornment
                                          showPassword={showPassword}
                                          onToggle={
                                              handleToggleShowHidePassword
                                          }
                                      />
                                  ),
                              }
                            : {},
                }}
                {...rest}
            />
            {onCancel ? (
                <Stack direction="row" sx={{ gap: "12px" }}>
                    <FocusVisibleButton
                        fullWidth
                        color="secondary"
                        onClick={onCancel}
                    >
                        {t("cancel")}
                    </FocusVisibleButton>
                    {submitButton}
                </Stack>
            ) : (
                submitButton
            )}
        </form>
    );
};
