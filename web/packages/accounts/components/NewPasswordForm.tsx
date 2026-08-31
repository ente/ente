import { Input, TextField, Typography } from "@mui/material";
import {
    estimatePasswordStrength,
    type PasswordStrength,
} from "ente-accounts/utils/password";
import { LoadingButton } from "ente-base/components/mui/LoadingButton";
import { ShowHidePasswordInputAdornment } from "ente-base/components/mui/PasswordInputAdornment";
import log from "ente-base/log";
import { useFormik } from "formik";
import { t } from "i18next";
import { useCallback, useMemo, useState, type ComponentType } from "react";
import { Trans } from "react-i18next";
import { PasswordStrengthHint } from "./PasswordStrength";

export interface NewPasswordFormProps {
    userEmail: string;
    submitButtonTitle: string;
    presentation?: ComponentType<NewPasswordPresentationProps>;
    onBack?: () => void;
    onSubmit: (
        password: string,
        setPasswordsFieldError: (message: string) => void,
    ) => Promise<void>;
}

export interface NewPasswordPresentationProps {
    userEmail: string;
    password: string;
    confirmPassword: string;
    passwordError: string | undefined;
    confirmPasswordError: string | undefined;
    passwordStrength: PasswordStrength;
    isSubmitting: boolean;
    isSubmitDisabled: boolean;
    submitButtonTitle: string;
    onBack: (() => void) | undefined;
    onPasswordChange: React.ChangeEventHandler<
        HTMLInputElement | HTMLTextAreaElement
    >;
    onConfirmPasswordChange: React.ChangeEventHandler<
        HTMLInputElement | HTMLTextAreaElement
    >;
    onSubmit: React.SubmitEventHandler<HTMLFormElement>;
}

export const NewPasswordForm: React.FC<NewPasswordFormProps> = ({
    userEmail,
    submitButtonTitle,
    presentation: Presentation,
    onBack,
    onSubmit,
}) => {
    const [showPassword, setShowPassword] = useState(false);
    const [showConfirmPassword, setShowConfirmPassword] = useState(false);

    const handleToggleShowHidePassword = useCallback(
        () => setShowPassword((show) => !show),
        [],
    );
    const handleToggleShowHideConfirmPassword = useCallback(
        () => setShowConfirmPassword((show) => !show),
        [],
    );

    const formik = useFormik({
        initialValues: { password: "", confirmPassword: "" },
        onSubmit: async ({ password, confirmPassword }, { setFieldError }) => {
            const setPasswordsFieldError = (message: string) =>
                setFieldError("confirmPassword", message);

            if (!confirmPassword) {
                setPasswordsFieldError(t("required"));
                return;
            }

            if (password != confirmPassword) {
                setPasswordsFieldError(t("password_mismatch_error"));
                return;
            }

            try {
                await onSubmit(password, setPasswordsFieldError);
            } catch (e) {
                log.error("Could not set password", e);
                setPasswordsFieldError(t("generic_error"));
            }
        },
    });

    const passwordStrength = useMemo(
        () => estimatePasswordStrength(formik.values.password),
        [formik.values.password],
    );

    if (Presentation) {
        return (
            <Presentation
                userEmail={userEmail}
                password={formik.values.password}
                confirmPassword={formik.values.confirmPassword}
                passwordError={formik.errors.password}
                confirmPasswordError={formik.errors.confirmPassword}
                passwordStrength={passwordStrength}
                isSubmitting={formik.isSubmitting}
                isSubmitDisabled={passwordStrength == "weak"}
                submitButtonTitle={submitButtonTitle}
                onBack={onBack}
                onPasswordChange={formik.handleChange}
                onConfirmPasswordChange={formik.handleChange}
                onSubmit={formik.handleSubmit}
            />
        );
    }

    return (
        <form onSubmit={formik.handleSubmit}>
            <Typography variant="small" sx={{ mb: 2, color: "text.muted" }}>
                {t("pick_password_hint")}
            </Typography>

            {/* This hidden email input helps password managers associate the
                new password with the user's email. */}
            <Input
                sx={{ display: "none" }}
                name="email"
                type="email"
                autoComplete="username"
                value={userEmail}
            />
            <TextField
                name="password"
                autoComplete="new-password"
                type={showPassword ? "text" : "password"}
                label={t("password")}
                value={formik.values.password}
                onChange={formik.handleChange}
                disabled={formik.isSubmitting}
                fullWidth
                autoFocus
                slotProps={{
                    input: {
                        endAdornment: (
                            <ShowHidePasswordInputAdornment
                                showPassword={showPassword}
                                onToggle={handleToggleShowHidePassword}
                            />
                        ),
                    },
                }}
            />
            <TextField
                name="confirmPassword"
                autoComplete="new-password"
                type={showConfirmPassword ? "text" : "password"}
                label={t("confirm_password")}
                value={formik.values.confirmPassword}
                onChange={formik.handleChange}
                error={!!formik.errors.confirmPassword}
                helperText={formik.errors.confirmPassword ?? " "}
                disabled={formik.isSubmitting}
                fullWidth
                slotProps={{
                    input: {
                        endAdornment: (
                            <ShowHidePasswordInputAdornment
                                showPassword={showConfirmPassword}
                                onToggle={handleToggleShowHideConfirmPassword}
                            />
                        ),
                    },
                }}
            />
            <PasswordStrengthHint
                password={formik.values.password}
                strength={passwordStrength}
            />

            <Typography
                variant="small"
                sx={{ color: "text.muted", my: 2, mb: 4 }}
            >
                <Trans i18nKey={"pick_password_caution"} />
            </Typography>

            <LoadingButton
                color="accent"
                type="submit"
                loading={formik.isSubmitting}
                disabled={passwordStrength == "weak"}
                fullWidth
            >
                {submitButtonTitle}
            </LoadingButton>
            <Typography
                variant="small"
                sx={(theme) => ({
                    textAlign: "center",
                    mt: 1,
                    color: "text.muted",
                    minHeight: theme.typography.small.lineHeight,
                })}
            >
                {formik.isSubmitting ? t("key_generation_in_progress") : ""}
            </Typography>
        </form>
    );
};
