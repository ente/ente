import InfoOutlinedIcon from "@mui/icons-material/InfoOutlined";
import {
    Checkbox,
    Divider,
    FormControlLabel,
    FormGroup,
    IconButton,
    InputAdornment,
    InputLabel,
    Link,
    Stack,
    TextField,
    Tooltip,
    Typography,
} from "@mui/material";
import {
    replaceSavedLocalUser,
    saveJustSignedUp,
    saveOriginalKeyAttributes,
    stashReferralSource,
    stashSRPSetupAttributes,
} from "ente-accounts/services/accounts-db";
import { deriveKeyInsufficientMemoryErrorMessage } from "ente-accounts/services/crypto";
import { saveMasterKeyInSessionAndSafeStore } from "ente-accounts/services/session-storage";
import { generateSRPSetupAttributes } from "ente-accounts/services/srp";
import {
    generateAndSaveInteractiveKeyAttributes,
    generateKeysAndAttributes,
    sendOTT,
    type GenerateKeysAndAttributesResult,
} from "ente-accounts/services/user";
import {
    estimatePasswordStrength,
    isWeakPassword,
    type PasswordStrength,
} from "ente-accounts/utils/password";
import { LinkButton } from "ente-base/components/LinkButton";
import { LoadingButton } from "ente-base/components/mui/LoadingButton";
import { ShowHidePasswordInputAdornment } from "ente-base/components/mui/PasswordInputAdornment";
import { isMuseumHTTPError } from "ente-base/http";
import { JOIN_ALBUM_CONTEXT_KEY } from "ente-base/join-album";
import log from "ente-base/log";
import { useFormik } from "formik";
import { t } from "i18next";
import type { NextRouter } from "next/router";
import React, { useCallback, useEffect, useMemo, useState } from "react";
import { Trans } from "react-i18next";
import { z } from "zod";
import { PasswordStrengthHint } from "./PasswordStrength";
import {
    AccountsPageFooter,
    AccountsPageTitle,
} from "./layouts/centered-paper";

interface SignUpContentsProps {
    router: NextRouter;
    onLogin: () => void;
    host: string | undefined;
    presentation?: React.ComponentType<SignUpPresentationProps>;
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
    presentation: Presentation,
}) => {
    const [showPassword, setShowPassword] = useState(false);
    const [isJoinAlbumContext, setIsJoinAlbumContext] = useState(false);

    useEffect(() => {
        const joinAlbumContext = sessionStorage.getItem(JOIN_ALBUM_CONTEXT_KEY);
        setIsJoinAlbumContext(!!joinAlbumContext);
    }, []);

    const handleToggleShowHidePassword = useCallback(
        () => setShowPassword((show) => !show),
        [],
    );

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

                try {
                    await sendOTT(email, "signup");
                } catch (e) {
                    if (
                        await isMuseumHTTPError(
                            e,
                            409,
                            "USER_ALREADY_REGISTERED",
                        )
                    ) {
                        setFieldError("email", t("email_already_registered"));
                        return;
                    }
                    throw e;
                }

                replaceSavedLocalUser({ email });

                let gkResult: GenerateKeysAndAttributesResult;
                try {
                    gkResult = await generateKeysAndAttributes(password);
                } catch (e) {
                    if (
                        e instanceof Error &&
                        e.message == deriveKeyInsufficientMemoryErrorMessage
                    ) {
                        setFieldError(
                            "confirmPassword",
                            t("password_generation_failed"),
                        );
                        return;
                    }
                    throw e;
                }

                const { masterKey, kek, keyAttributes } = gkResult;
                saveOriginalKeyAttributes(keyAttributes);
                stashSRPSetupAttributes(await generateSRPSetupAttributes(kek));
                await generateAndSaveInteractiveKeyAttributes(
                    password,
                    keyAttributes,
                    masterKey,
                );
                await saveMasterKeyInSessionAndSafeStore(masterKey);

                saveJustSignedUp();
                void router.push("/verify");
            } catch (e) {
                log.error("Signup failed", e);
                setFieldError("confirmPassword", t("generic_error"));
            }
        },
    });

    const passwordStrength = useMemo(
        () =>
            Presentation && formik.values.password
                ? estimatePasswordStrength(formik.values.password)
                : undefined,
        [Presentation, formik.values.password],
    );

    function handleAcceptedTermsChange(acceptedTerms: boolean) {
        void formik.setFieldValue("acceptedTerms", acceptedTerms);
    }

    if (Presentation) {
        return (
            <Presentation
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
    }

    const form = (
        <form onSubmit={formik.handleSubmit}>
            <TextField
                name="email"
                type="email"
                autoComplete="username"
                label={t("enter_email")}
                value={formik.values.email}
                onChange={formik.handleChange}
                error={!!formik.errors.email}
                helperText={formik.errors.email}
                disabled={formik.isSubmitting}
                fullWidth
                autoFocus
            />
            <TextField
                name="password"
                autoComplete="new-password"
                type={showPassword ? "text" : "password"}
                label={t("password")}
                value={formik.values.password}
                onChange={formik.handleChange}
                error={!!formik.errors.password}
                helperText={formik.errors.password}
                disabled={formik.isSubmitting}
                fullWidth
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
                type="password"
                label={t("confirm_password")}
                value={formik.values.confirmPassword}
                onChange={formik.handleChange}
                error={!!formik.errors.confirmPassword}
                helperText={formik.errors.confirmPassword}
                disabled={formik.isSubmitting}
                fullWidth
            />
            <PasswordStrengthHint password={formik.values.password} />
            <InputLabel
                htmlFor="referral"
                sx={{ color: "text.muted", mt: "24px", mx: "2px" }}
            >
                {t("referral_source_hint")}
            </InputLabel>
            <TextField
                hiddenLabel
                id="referral"
                type="text"
                value={formik.values.referral}
                onChange={formik.handleChange}
                error={!!formik.errors.referral}
                disabled={formik.isSubmitting}
                fullWidth
                slotProps={{
                    input: {
                        endAdornment: (
                            <InputAdornment position="end">
                                <Tooltip title={t("referral_source_info")}>
                                    <IconButton
                                        tabIndex={-1}
                                        color="secondary"
                                        edge={"end"}
                                    >
                                        <InfoOutlinedIcon />
                                    </IconButton>
                                </Tooltip>
                            </InputAdornment>
                        ),
                    },
                }}
            />
            <FormGroup sx={{ color: "text.muted", mt: 2, mb: 2.5, mx: "4px" }}>
                <FormControlLabel
                    control={
                        <Checkbox
                            name="acceptedTerms"
                            size="small"
                            color="accent"
                            checked={formik.values.acceptedTerms}
                            onChange={formik.handleChange}
                            disabled={formik.isSubmitting}
                        />
                    }
                    label={
                        <Typography variant="small">
                            <Trans
                                i18nKey={"terms_and_conditions"}
                                components={{
                                    a: (
                                        <Link
                                            href="https://ente.com/terms"
                                            target="_blank"
                                        />
                                    ),
                                    b: (
                                        <Link
                                            href="https://ente.com/privacy"
                                            target="_blank"
                                        />
                                    ),
                                }}
                            />
                        </Typography>
                    }
                />
            </FormGroup>
            <LoadingButton
                fullWidth
                color="accent"
                type="submit"
                loading={formik.isSubmitting}
                disabled={
                    !formik.values.acceptedTerms ||
                    isWeakPassword(formik.values.password)
                }
            >
                {t("create_account")}
            </LoadingButton>
            <Typography
                variant="small"
                sx={(theme) => ({
                    mt: 1,
                    textAlign: "center",
                    color: "text.muted",
                    // The minHeight, equal to the lineHeight of the eventual
                    // content, prevents layout shift.
                    minHeight: theme.typography.small.lineHeight,
                })}
            >
                {formik.isSubmitting ? t("key_generation_in_progress") : ""}
            </Typography>
        </form>
    );

    return (
        <>
            <AccountsPageTitle>
                {isJoinAlbumContext ? t("signup_to_join_album") : t("sign_up")}
            </AccountsPageTitle>
            {form}
            <Divider sx={{ mt: 1 }} />
            <AccountsPageFooter>
                <Stack sx={{ gap: 3, textAlign: "center" }}>
                    <LinkButton onClick={onLogin}>
                        {t("existing_account")}
                    </LinkButton>
                    {host && (
                        <Typography variant="mini" sx={{ color: "text.faint" }}>
                            {host}
                        </Typography>
                    )}
                </Stack>
            </AccountsPageFooter>
        </>
    );
};
