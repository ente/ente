import InfoOutlinedIcon from "@mui/icons-material/InfoOutlined";
import { styled, Tooltip } from "@mui/material";
import type { SignUpPresentationProps } from "ente-accounts/components/SignUpContents";
import { t } from "i18next";
import type React from "react";
import { Trans } from "react-i18next";
import { Button } from "./Button";
import { Checkbox } from "./Checkbox";
import { Form } from "./Form";
import { FormFields } from "./FormFields";
import { FormFooter } from "./FormFooter";
import { PasswordStrengthMessage } from "./PasswordStrengthMessage";
import { ScreenHeader } from "./ScreenHeader";
import { TextField } from "./TextField";
import { TextLink } from "./TextLink";

export function SignUpForm({
    email,
    password,
    confirmPassword,
    referral,
    acceptedTerms,
    emailError,
    passwordError,
    confirmPasswordError,
    passwordStrength,
    isSubmitting,
    isSubmitDisabled,
    isJoinAlbumContext,
    host,
    onEmailChange,
    onPasswordChange,
    onConfirmPasswordChange,
    onReferralChange,
    onAcceptedTermsChange,
    onSubmit,
    onLogin,
}: SignUpPresentationProps): React.JSX.Element {
    return (
        <>
            <ScreenHeader
                title={
                    isJoinAlbumContext
                        ? t("signup_to_join_album")
                        : t("auth_create_account")
                }
                subtitle={t("auth_signup_subtitle")}
            />
            <Form onSubmit={onSubmit}>
                <FormFields>
                    <TextField
                        name="email"
                        label={t("auth_email_label")}
                        placeholder={t("auth_email_placeholder")}
                        type="email"
                        autoComplete="username"
                        value={email}
                        onChange={onEmailChange}
                        autoFocus
                        error={Boolean(emailError)}
                        helperText={emailError}
                        disabled={isSubmitting}
                    />
                    <PasswordField>
                        <TextField
                            name="password"
                            label={t("password")}
                            placeholder={t("auth_password_placeholder")}
                            autoComplete="new-password"
                            showPasswordToggle
                            value={password}
                            onChange={onPasswordChange}
                            error={Boolean(passwordError)}
                            helperText={passwordError}
                            disabled={isSubmitting}
                        />
                        <PasswordStrengthMessage
                            strength={passwordStrength}
                            visible={Boolean(passwordStrength)}
                        />
                    </PasswordField>
                    <TextField
                        name="confirmPassword"
                        label={t("confirm_password")}
                        placeholder={t("auth_confirm_password_placeholder")}
                        autoComplete="new-password"
                        showPasswordToggle
                        value={confirmPassword}
                        onChange={onConfirmPasswordChange}
                        error={Boolean(confirmPasswordError)}
                        helperText={confirmPasswordError}
                        disabled={isSubmitting}
                    />
                    <TextField
                        name="referral"
                        label={
                            <ReferralLabel>
                                {t("referral_source_hint")}
                                <Tooltip title={t("referral_source_info")}>
                                    <InfoOutlinedIcon
                                        fontSize="inherit"
                                        tabIndex={0}
                                        aria-label={t("referral_source_info")}
                                    />
                                </Tooltip>
                            </ReferralLabel>
                        }
                        placeholder={t("auth_optional")}
                        value={referral}
                        onChange={onReferralChange}
                        disabled={isSubmitting}
                    />
                </FormFields>
                <Checkbox
                    name="acceptedTerms"
                    checked={acceptedTerms}
                    onChange={onAcceptedTermsChange}
                    disabled={isSubmitting}
                    label={
                        <TermsText>
                            <Trans
                                i18nKey="terms_and_conditions"
                                components={{
                                    a: (
                                        <TermsLink
                                            href="https://ente.com/terms"
                                            target="_blank"
                                        />
                                    ),
                                    b: (
                                        <TermsLink
                                            href="https://ente.com/privacy"
                                            target="_blank"
                                        />
                                    ),
                                }}
                            />
                        </TermsText>
                    }
                />
                <FormFooter>
                    <Button
                        fullWidth
                        type="submit"
                        loading={isSubmitting}
                        loadingMessage={t("key_generation_in_progress")}
                        disabled={isSubmitDisabled}
                    >
                        {t("create_account")}
                    </Button>
                    <AccountPrompt>
                        <span>{t("auth_existing_account_prompt")}</span>
                        <TextLink regular onClick={onLogin}>
                            {t("login")}
                        </TextLink>
                    </AccountPrompt>
                    {host ? <Host>{host}</Host> : null}
                </FormFooter>
            </Form>
        </>
    );
}

const PasswordField = styled("div")({
    "--locker-auth-message-gap": "8px",
    display: "flex",
    flexDirection: "column",
    gap: "8px",
});

const ReferralLabel = styled("span")({
    display: "inline-flex",
    alignItems: "center",
    gap: "4px",
    "& > svg": { fontSize: "14px" },
});

const TermsText = styled("span")({
    fontSize: "14px",
    fontWeight: 500,
    lineHeight: "20px",
    color: "var(--locker-auth-text)",
});

const TermsLink = styled("a")({
    color: "var(--locker-auth-primary)",
    textDecoration: "none",
    "&:hover": { textDecoration: "underline" },
    "&:focus-visible": {
        borderRadius: "4px",
        outline: "2px solid var(--locker-auth-primary)",
        outlineOffset: "2px",
    },
});

const AccountPrompt = styled("div")({
    display: "flex",
    alignItems: "center",
    justifyContent: "center",
    gap: "6px",
    fontSize: "14px",
    fontWeight: 500,
    lineHeight: "20px",
    textAlign: "center",
    color: "var(--locker-auth-text-muted)",
});

const Host = styled("div")({
    minHeight: "16px",
    fontSize: "12px",
    fontWeight: 500,
    lineHeight: "16px",
    textAlign: "center",
    color: "var(--locker-auth-text-faint)",
});
