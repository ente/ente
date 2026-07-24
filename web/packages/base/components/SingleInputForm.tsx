import {
    ButtonBase,
    CircularProgress,
    InputBase,
    Stack,
    TextField,
    Typography,
    type ButtonProps,
    type SxProps,
    type TextFieldProps,
    type Theme,
} from "@mui/material";
import { FocusVisibleButton } from "ente-base/components/mui/FocusVisibleButton";
import { LoadingButton } from "ente-base/components/mui/LoadingButton";
import log from "ente-base/log";
import { useFormik } from "formik";
import { t } from "i18next";
import React, { useCallback, useState } from "react";
import { ShowHidePasswordInputAdornment } from "./mui/PasswordInputAdornment";

export type SingleInputFormProps = Pick<
    TextFieldProps,
    "label" | "placeholder" | "autoComplete" | "autoFocus" | "slotProps"
> & {
    /** Visual treatment for the form. */
    variant?: "default" | "v2";
    /**
     * The type attribute of the HTML input element that will be used.
     *
     * Default is "text".
     *
     * In addition to changing the behaviour of the HTML input element, the
     * {@link SingleInputForm} component also has special casing for type
     * "password", wherein it'll show an adornment at the end of the text field
     * allowing the user to show or hide the password.
     */
    inputType?: TextFieldProps["type"];
    /**
     * The initial value, if any, to prefill in the input.
     */
    initialValue?: string;
    /**
     * Color of the submit button.
     *
     * Default: "accent".
     */
    submitButtonColor?: ButtonProps["color"];
    /**
     * Title for the submit button.
     */
    submitButtonTitle: string;
    /**
     * Cancellation handler.
     *
     * This function is called when the user activates the cancel button in the
     * form.
     *
     * If this is not provided, then only a full width submit button will be
     * shown in the form (below the input).
     */
    onCancel?: () => void;
    /**
     * Submission handler. A callback invoked when the submit button is pressed.
     *
     * During submission, the text input and the submit button are disabled, and
     * an indeterminate progress indicator is shown.
     *
     * If this function rejects then a generic error helper text is shown below
     * the text input, and the input (/ buttons) reenabled.
     *
     * This function is also passed an function that can be used to explicitly
     * set the error message that as shown below the text input when a specific
     * problem occurs during submission.
     *
     * @param name The current value of the text input.
     *
     * @param setFieldError A function that can be called to set the error message
     * shown below the text input if submission fails.
     *
     * Note that if {@link setFieldError} is called, then the {@link onSubmit}
     * function should not throw, otherwise the error message shown by
     * {@link setFieldError} will get overwritten by the generic error message.
     */
    onSubmit:
        | ((name: string, setFieldError: (message: string) => void) => void)
        | ((
              name: string,
              setFieldError: (message: string) => void,
          ) => Promise<void>);
};

/**
 * A TextField and cancel/submit buttons.
 *
 * A common requirement is taking a single textual input from the user. This is
 * a form suitable for that purpose. It contains a single MUI {@link TextField}
 * and two accompanying buttons; one to submit, and one to cancel.
 *
 * Submission is handled as an async function, during which the input is
 * disabled and a loading indicator is shown. Errors during submission are shown
 * as the helper text associated with the text field.
 *
 * The input field in the form takes autoFocus automatically on mount. Turn off
 * the {@link autoFocus} to disable this behaviour if needed.
 */
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
    const [showPassword, setShowPassword] = useState(false);

    const handleToggleShowHidePassword = useCallback(
        () => setShowPassword((show) => !show),
        [],
    );

    const formik = useFormik({
        initialValues: { value: initialValue ?? "" },
        enableReinitialize: variant === "v2",
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

    if (variant === "v2") {
        const error = formik.errors.value;
        return (
            <Stack
                component="form"
                onSubmit={formik.handleSubmit}
                sx={{ gap: "20px" }}
            >
                <Stack sx={{ gap: "8px" }}>
                    {rest.label && (
                        <Typography sx={v2LabelSx}>{rest.label}</Typography>
                    )}
                    <InputBase
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
                    <Typography sx={v2HelperSx(!!error)}>
                        {error ?? ""}
                    </Typography>
                </Stack>
                <Stack direction="row" sx={{ gap: "12px" }}>
                    {onCancel && (
                        <ButtonBase
                            onClick={onCancel}
                            disabled={formik.isSubmitting}
                            sx={v2CancelButtonSx}
                        >
                            {t("cancel")}
                        </ButtonBase>
                    )}
                    <ButtonBase
                        type="submit"
                        disabled={formik.isSubmitting}
                        sx={v2SubmitButtonSx}
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

    // [Note: Use space as default TextField helperText]
    //
    // For MUI text fields that use a conditional helperText, e.g. in case of
    // errors, use an space as the default helperText in the other cases to
    // avoid a layout shift when the helperText is conditionally shown.

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

const greenAccent = "#08c225";
const greenAccentHover = "#07ad21";
const errorColor = "#fa1336";

const v2LabelSx = {
    fontSize: 14,
    lineHeight: "20px",
    fontWeight: 500,
    color: "text.muted",
};
const v2InputSx: SxProps<Theme> = (theme) => ({
    height: 52,
    boxSizing: "content-box",
    display: "flex",
    alignItems: "center",
    borderRadius: "16px",
    border: "1px solid transparent",
    backgroundColor: "background.paper",
    px: "16px",
    fontSize: 14,
    fontWeight: 500,
    color: "text.base",
    "&.Mui-focused": { borderColor: "rgba(0 0 0 / 0.08)" },
    "& input": { padding: 0, height: "auto" },
    "& input::placeholder": { color: "text.muted", opacity: 1 },
    ...theme.applyStyles("dark", {
        backgroundColor: "#282828",
        "&.Mui-focused": { borderColor: "rgba(255 255 255 / 0.18)" },
    }),
    "&.Mui-error": { borderColor: errorColor },
});
const v2HelperSx = (isError: boolean) => (theme: Theme) => ({
    fontSize: 12,
    lineHeight: "16px",
    fontWeight: 500,
    color: isError ? errorColor : "rgba(0 0 0 / 0.45)",
    ...(isError
        ? {}
        : theme.applyStyles("dark", { color: "rgba(255 255 255 / 0.45)" })),
});
const v2BaseActionSx = {
    flex: 1,
    height: 52,
    borderRadius: "20px",
    fontSize: 14,
    lineHeight: "20px",
    fontWeight: 500,
    "&.Mui-disabled": { opacity: 0.7 },
};
const v2CancelButtonSx = (theme: Theme) => ({
    ...v2BaseActionSx,
    color: "text.base",
    backgroundColor: "#eaeaea",
    "&:hover": { backgroundColor: "#dedede" },
    ...theme.applyStyles("dark", {
        backgroundColor: "rgba(255 255 255 / 0.12)",
        "&:hover": { backgroundColor: "rgba(255 255 255 / 0.18)" },
    }),
});
const v2SubmitButtonSx = {
    ...v2BaseActionSx,
    color: "#fff",
    backgroundColor: greenAccent,
    "&:hover": { backgroundColor: greenAccentHover },
    "&.Mui-disabled": {
        color: "#fff",
        backgroundColor: greenAccent,
        opacity: 0.7,
    },
};
