import {
    ButtonBase,
    CircularProgress,
    InputBase,
    Stack,
    Typography,
    type InputBaseProps,
    type TextFieldProps,
} from "@mui/material";
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
    "label" | "placeholder" | "autoComplete" | "autoFocus" | "disabled"
> & {
    inputProps?: InputBaseProps["inputProps"];
    endAdornment?: React.ReactNode;
    selectOnFocus?: boolean;
    inputType?: TextFieldProps["type"];
    initialValue?: string;
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
    inputType,
    initialValue,
    autoFocus,
    disabled,
    endAdornment,
    selectOnFocus,
    submitButtonTitle,
    inputProps,
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
        enableReinitialize: true,
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
                        component="label"
                        htmlFor={inputID}
                        sx={v2LabelSx}
                    >
                        {rest.label}
                    </Typography>
                )}
                <InputBase
                    id={inputID}
                    inputProps={{
                        ...inputProps,
                        "aria-invalid": !!error,
                        "aria-describedby":
                            [
                                inputProps?.["aria-describedby"],
                                error ? helperID : undefined,
                            ]
                                .filter(Boolean)
                                .join(" ") || undefined,
                    }}
                    name="value"
                    value={formik.values.value}
                    onChange={formik.handleChange}
                    onFocus={
                        selectOnFocus
                            ? (event) => event.target.select()
                            : undefined
                    }
                    type={showPassword ? "text" : (inputType ?? "text")}
                    placeholder={rest.placeholder}
                    autoComplete={rest.autoComplete}
                    autoFocus={autoFocus ?? true}
                    disabled={disabled || formik.isSubmitting}
                    error={!!error}
                    sx={v2InputSx}
                    endAdornment={
                        inputType == "password" ? (
                            <ShowHidePasswordInputAdornment
                                showPassword={showPassword}
                                onToggle={handleToggleShowHidePassword}
                            />
                        ) : (
                            endAdornment
                        )
                    }
                />
                <Typography
                    id={helperID}
                    aria-live="polite"
                    sx={v2HelperSx(!!error)}
                >
                    {error ?? ""}
                </Typography>
            </Stack>
            <Stack direction="row" sx={{ gap: "12px" }}>
                {onCancel && (
                    <ButtonBase
                        onClick={onCancel}
                        disabled={disabled || formik.isSubmitting}
                        sx={[v2CancelButtonSx, peopleActionFocusSx]}
                    >
                        {t("cancel")}
                    </ButtonBase>
                )}
                <ButtonBase
                    type="submit"
                    disabled={disabled || formik.isSubmitting}
                    sx={[v2SubmitButtonSx, peopleActionFocusSx]}
                >
                    {formik.isSubmitting ? (
                        <CircularProgress size={20} sx={{ color: "#fff" }} />
                    ) : (
                        submitButtonTitle
                    )}
                </ButtonBase>
            </Stack>
        </Stack>
    );
};
