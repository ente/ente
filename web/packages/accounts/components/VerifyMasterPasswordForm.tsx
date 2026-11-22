import { Input, TextField } from "@mui/material";
import {
    verifyMasterPassword,
    type MasterPasswordVerificationOptions,
} from "ente-accounts/services/verify-master-password";
import { LoadingButton } from "ente-base/components/mui/LoadingButton";
import { ShowHidePasswordInputAdornment } from "ente-base/components/mui/PasswordInputAdornment";
import log from "ente-base/log";
import { useFormik } from "formik";
import { t } from "i18next";
import { useCallback, useState, type ComponentType } from "react";

export interface VerifyMasterPasswordPresentationProps {
    userEmail: string;
    password: string;
    passwordError: string | undefined;
    isSubmitting: boolean;
    submitButtonTitle: string;
    onPasswordChange: React.ChangeEventHandler<
        HTMLInputElement | HTMLTextAreaElement
    >;
    onSubmit: React.SubmitEventHandler<HTMLFormElement>;
}

export interface VerifyMasterPasswordFormProps extends MasterPasswordVerificationOptions {
    userEmail: string;
    submitButtonTitle: string;
    presentation?: ComponentType<VerifyMasterPasswordPresentationProps>;
}

export const VerifyMasterPasswordForm: React.FC<
    VerifyMasterPasswordFormProps
> = ({
    decryptBox,
    userEmail,
    keyAttributes,
    srpAttributes,
    getKeyAttributes,
    onVerify,
    submitButtonTitle,
    presentation: Presentation,
}) => {
    const [showPassword, setShowPassword] = useState(false);

    const handleToggleShowHidePassword = useCallback(
        () => setShowPassword((show) => !show),
        [],
    );

    const formik = useFormik({
        initialValues: { password: "" },
        onSubmit: async ({ password }, { setFieldError }) => {
            const setPasswordFieldError = (message: string) =>
                setFieldError("password", message);

            if (!password) {
                setPasswordFieldError(t("required"));
                return;
            }

            try {
                await verifyMasterPassword(
                    {
                        decryptBox,
                        keyAttributes,
                        srpAttributes,
                        getKeyAttributes,
                        onVerify,
                    },
                    password,
                    setPasswordFieldError,
                );
            } catch (e) {
                log.error("Failed to verify password", e);
                setPasswordFieldError(t("generic_error"));
            }
        },
    });

    if (Presentation) {
        return (
            <Presentation
                userEmail={userEmail}
                password={formik.values.password}
                passwordError={formik.errors.password}
                isSubmitting={formik.isSubmitting}
                submitButtonTitle={submitButtonTitle}
                onPasswordChange={formik.handleChange}
                onSubmit={formik.handleSubmit}
            />
        );
    }

    return (
        <form onSubmit={formik.handleSubmit}>
            <Input
                sx={{ display: "none" }}
                name="email"
                autoComplete="username"
                type="email"
                value={userEmail}
            />
            <TextField
                name="password"
                value={formik.values.password}
                onChange={formik.handleChange}
                type={showPassword ? "text" : "password"}
                autoComplete="current-password"
                label={t("password")}
                fullWidth
                autoFocus
                margin="normal"
                disabled={formik.isSubmitting}
                error={!!formik.errors.password}
                helperText={formik.errors.password ?? " "}
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
            <LoadingButton
                fullWidth
                type="submit"
                loading={formik.isSubmitting}
                color={"accent"}
            >
                {submitButtonTitle}
            </LoadingButton>
        </form>
    );
};
