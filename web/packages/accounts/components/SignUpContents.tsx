import { SignUpForm } from "ente-accounts/components/auth/SignUpForm";
import {
    replaceSavedLocalUser,
    saveJustSignedUp,
    saveOriginalKeyAttributes,
    stashReferralSource,
    stashSRPSetupAttributes,
} from "ente-accounts/services/accounts-db";
import { saveMasterKeyInSessionAndSafeStore } from "ente-accounts/services/prelogin-session";
import {
    generateAndSaveInteractiveKeyAttributes,
    generateSignupKeys,
    sendOTT,
} from "ente-accounts/services/user";
import {
    estimatePasswordStrength,
    type PasswordStrength,
} from "ente-accounts/utils/password";
import { isNamedError } from "ente-base/error";
import { JOIN_ALBUM_CONTEXT_KEY } from "ente-base/join-album";
import log from "ente-base/log";
import { useFormik } from "formik";
import { t } from "i18next";
import type { NextRouter } from "next/router";
import React, { useEffect, useMemo, useState } from "react";
import { z } from "zod";

interface SignUpContentsProps {
    router: NextRouter;
    onLogin: () => void;
    host: string | undefined;
}

export interface SignUpPresentationProps {
    email: string;
    password: string;
    confirmPassword: string;
    referral: string;
    acceptedTerms: boolean;
    emailError: string | undefined;
    passwordError: string | undefined;
    confirmPasswordError: string | undefined;
    passwordStrength: PasswordStrength | undefined;
    isSubmitting: boolean;
    isSubmitDisabled: boolean;
    isJoinAlbumContext: boolean;
    host: string | undefined;
    onEmailChange: React.ChangeEventHandler<
        HTMLInputElement | HTMLTextAreaElement
    >;
    onPasswordChange: React.ChangeEventHandler<
        HTMLInputElement | HTMLTextAreaElement
    >;
    onConfirmPasswordChange: React.ChangeEventHandler<
        HTMLInputElement | HTMLTextAreaElement
    >;
    onReferralChange: React.ChangeEventHandler<
        HTMLInputElement | HTMLTextAreaElement
    >;
    onAcceptedTermsChange: (acceptedTerms: boolean) => void;
    onSubmit: React.SubmitEventHandler<HTMLFormElement>;
    onLogin: () => void;
}

export const SignUpContents: React.FC<SignUpContentsProps> = ({
    router,
    onLogin,
    host,
}) => {
    const [isJoinAlbumContext, setIsJoinAlbumContext] = useState(false);

    useEffect(() => {
        const joinAlbumContext = sessionStorage.getItem(JOIN_ALBUM_CONTEXT_KEY);
        setIsJoinAlbumContext(!!joinAlbumContext);
    }, []);

    const formik = useFormik({
        initialValues: {
            email: "",
            password: "",
            confirmPassword: "",
            referral: "",
            acceptedTerms: false,
        },
        onSubmit: async (
            { email, password, confirmPassword, referral },
            { setFieldError },
        ) => {
            if (!email) {
                setFieldError("email", t("required"));
                return;
            }

            if (!z.email().safeParse(email).success) {
                setFieldError("email", t("invalid_email_error"));
                return;
            }

            if (!password) {
                setFieldError("password", t("required"));
                return;
            }

            if (!confirmPassword) {
                setFieldError("confirmPassword", t("required"));
                return;
            }

            if (password != confirmPassword) {
                setFieldError("confirmPassword", t("password_mismatch_error"));
                return;
            }

            try {
                const cleanedReferral = referral.trim();
                if (cleanedReferral) stashReferralSource(cleanedReferral);

                await sendOTT(email, "signup");
                replaceSavedLocalUser({ email });
                const { masterKey, keyAttributes, srp } =
                    await generateSignupKeys(password);
                saveOriginalKeyAttributes(keyAttributes);
                stashSRPSetupAttributes(srp);
                await generateAndSaveInteractiveKeyAttributes(
                    password,
                    keyAttributes,
                    masterKey,
                );
                await saveMasterKeyInSessionAndSafeStore(masterKey);

                saveJustSignedUp();
                void router.push("/verify");
            } catch (e) {
                if (isNamedError(e, "already_registered")) {
                    setFieldError("email", t("email_already_registered"));
                } else if (isNamedError(e, "insufficient_memory")) {
                    setFieldError(
                        "confirmPassword",
                        t("password_generation_failed"),
                    );
                } else {
                    log.error("Signup failed", e);
                    setFieldError("confirmPassword", t("generic_error"));
                }
            }
        },
    });

    const passwordStrength = useMemo(
        () =>
            formik.values.password
                ? estimatePasswordStrength(formik.values.password)
                : undefined,
        [formik.values.password],
    );

    function handleAcceptedTermsChange(acceptedTerms: boolean) {
        void formik.setFieldValue("acceptedTerms", acceptedTerms);
    }

    return (
        <SignUpForm
            email={formik.values.email}
            password={formik.values.password}
            confirmPassword={formik.values.confirmPassword}
            referral={formik.values.referral}
            acceptedTerms={formik.values.acceptedTerms}
            emailError={formik.errors.email}
            passwordError={formik.errors.password}
            confirmPasswordError={formik.errors.confirmPassword}
            passwordStrength={passwordStrength}
            isSubmitting={formik.isSubmitting}
            isSubmitDisabled={
                !formik.values.acceptedTerms ||
                !passwordStrength ||
                passwordStrength === "weak"
            }
            isJoinAlbumContext={isJoinAlbumContext}
            host={host}
            onEmailChange={formik.handleChange}
            onPasswordChange={formik.handleChange}
            onConfirmPasswordChange={formik.handleChange}
            onReferralChange={formik.handleChange}
            onAcceptedTermsChange={handleAcceptedTermsChange}
            onSubmit={formik.handleSubmit}
            onLogin={onLogin}
        />
    );
};
