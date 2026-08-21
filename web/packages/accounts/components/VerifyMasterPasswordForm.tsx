import { Input, TextField } from "@mui/material";
import { decryptBox, deriveKey } from "ente-accounts/services/crypto";
import {
    srpVerificationUnauthorizedErrorMessage,
    type SRPAttributes,
} from "ente-accounts/services/srp";
import type { KeyAttributes } from "ente-accounts/services/user";
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

export interface VerifyMasterPasswordFormProps {
    userEmail: string;
    srpAttributes?: SRPAttributes;
    keyAttributes: KeyAttributes | undefined;
    getKeyAttributes?: (
        srpAttributes: SRPAttributes,
        kek: string,
    ) => Promise<KeyAttributes | "redirecting-second-factor" | undefined>;
    submitButtonTitle: string;
    onVerify: (
        key: string,
        kek: string,
        keyAttributes: KeyAttributes,
        password: string,
    ) => void;
    presentation?: ComponentType<VerifyMasterPasswordPresentationProps>;
}

export const VerifyMasterPasswordForm: React.FC<
    VerifyMasterPasswordFormProps
> = ({
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
                await verifyPassword(password, setPasswordFieldError);
            } catch (e) {
                log.error("Failed to verify password", e);
                setPasswordFieldError(t("generic_error"));
            }
        },
    });

    const verifyPassword = async (
        password: string,
        setFieldError: (message: string) => void,
    ) => {
        let kek: string;
        if (srpAttributes) {
            try {
                kek = await deriveKey(
                    password,
                    srpAttributes.kekSalt,
                    srpAttributes.opsLimit,
                    srpAttributes.memLimit,
                );
            } catch (e) {
                log.error("Failed to derive kek", e);
                setFieldError(t("weak_device_hint"));
                return;
            }
        } else if (keyAttributes) {
            try {
                kek = await deriveKey(
                    password,
                    keyAttributes.kekSalt,
                    keyAttributes.opsLimit,
                    keyAttributes.memLimit,
                );
            } catch (e) {
                log.error("Failed to derive kek", e);
                setFieldError(t("weak_device_hint"));
                return;
            }
        } else throw new Error("Both SRP and key attributes are missing");

        if (!keyAttributes && getKeyAttributes && srpAttributes) {
            try {
                const result = await getKeyAttributes(srpAttributes, kek);
                if (result == "redirecting-second-factor") {
                    return;
                } else {
                    keyAttributes = result;
                }
            } catch (e) {
                if (
                    e instanceof Error &&
                    e.message == srpVerificationUnauthorizedErrorMessage
                ) {
                    log.error("Incorrect password or no account", e);
                    setFieldError(t("incorrect_password_or_no_account"));
                    return;
                }
                throw e;
            }
        }

        if (!keyAttributes) throw Error("Couldn't get key attributes");

        let key: string;
        try {
            key = await decryptBox(
                {
                    encryptedData: keyAttributes.encryptedKey,
                    nonce: keyAttributes.keyDecryptionNonce,
                },
                kek,
            );
        } catch {
            setFieldError(t("incorrect_password"));
            return;
        }

        onVerify(key, kek, keyAttributes, password);
    };

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
