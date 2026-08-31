import { styled } from "@mui/material";
import type { VerifyMasterPasswordPresentationProps } from "ente-accounts/components/VerifyMasterPasswordForm";
import type { CredentialsPresentationProps } from "ente-accounts/pages/credentials";
import { t } from "i18next";
import type React from "react";
import { Trans } from "react-i18next";
import { Button } from "./Button";
import { Form } from "./Form";
import { FormFields } from "./FormFields";
import { FormFooter } from "./FormFooter";
import { ScreenHeader } from "./ScreenHeader";
import { TextField } from "./TextField";
import { TextLink } from "./TextLink";

export function CredentialsForm({
    userEmail,
    host,
    passwordForm,
    onRecover,
    onChangeEmail,
}: CredentialsPresentationProps): React.JSX.Element {
    return (
        <>
            <ScreenHeader
                title={t("enter_password")}
                subtitle={
                    <Trans
                        i18nKey="auth_signing_in_as"
                        components={{ a: <Email /> }}
                        values={{ email: userEmail }}
                    />
                }
            />
            {passwordForm}
            <FormFooter>
                <FooterLinks>
                    <TextLink onClick={onRecover}>
                        {t("forgot_password")}
                    </TextLink>
                    <TextLink onClick={onChangeEmail}>
                        {t("change_email")}
                    </TextLink>
                </FooterLinks>
                <Host>{host ?? ""}</Host>
            </FormFooter>
        </>
    );
}

export function PasswordForm({
    userEmail,
    password,
    passwordError,
    isSubmitting,
    submitButtonTitle,
    onPasswordChange,
    onSubmit,
}: VerifyMasterPasswordPresentationProps): React.JSX.Element {
    return (
        <Form onSubmit={onSubmit}>
            <HiddenEmail
                name="email"
                type="email"
                autoComplete="username"
                value={userEmail}
                readOnly
                tabIndex={-1}
            />
            <FormFields>
                <TextField
                    name="password"
                    value={password}
                    onChange={onPasswordChange}
                    type="password"
                    autoComplete="current-password"
                    label={t("password")}
                    showPasswordToggle
                    autoFocus
                    disabled={isSubmitting}
                    error={Boolean(passwordError)}
                    helperText={passwordError}
                />
            </FormFields>
            <FormFooter>
                <Button fullWidth type="submit" loading={isSubmitting}>
                    {submitButtonTitle}
                </Button>
            </FormFooter>
        </Form>
    );
}

const HiddenEmail = styled("input")({ display: "none" });

const Email = styled("strong")({
    color: "var(--auth-app-text)",
    wordBreak: "break-word",
});

const FooterLinks = styled("div")({
    display: "flex",
    justifyContent: "space-between",
    gap: "16px",
});

const Host = styled("div")({
    minHeight: "16px",
    textAlign: "center",
    fontSize: "12px",
    fontWeight: 500,
    lineHeight: "16px",
    color: "var(--auth-app-text-faint)",
});
