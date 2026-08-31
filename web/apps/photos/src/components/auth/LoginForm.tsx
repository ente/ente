import { Input, styled } from "@mui/material";
import type { LoginPresentationProps } from "ente-accounts/components/LoginContents";
import { t } from "i18next";
import type React from "react";
import { Button } from "./Button";
import { Form } from "./Form";
import { FormFields } from "./FormFields";
import { FormFooter } from "./FormFooter";
import { ScreenHeader } from "./ScreenHeader";
import { TextField } from "./TextField";
import { TextLink } from "./TextLink";

export function LoginForm({
    email,
    emailError,
    host,
    isSubmitting,
    isJoinAlbumContext,
    isEnsu,
    onEmailChange,
    onSubmit,
    onSignUp,
    onCancel,
}: LoginPresentationProps): React.JSX.Element {
    return (
        <>
            <ScreenHeader
                title={
                    isJoinAlbumContext
                        ? t("login_to_join_album")
                        : t("auth_welcome_back")
                }
                subtitle={t("auth_login_subtitle")}
            />
            <Form onSubmit={onSubmit}>
                <FormFields>
                    <TextField
                        name="email"
                        value={email}
                        onChange={onEmailChange}
                        type="email"
                        autoComplete="username"
                        label={t("auth_email_label")}
                        placeholder={t("auth_email_placeholder")}
                        autoFocus
                        disabled={isSubmitting}
                        error={Boolean(emailError)}
                        helperText={emailError}
                    />
                    <Input
                        sx={{ display: "none" }}
                        type="password"
                        value=""
                        readOnly
                    />
                </FormFields>
                <FormFooter>
                    <Button fullWidth type="submit" loading={isSubmitting}>
                        {t("login")}
                    </Button>
                    <AccountActions>
                        {isEnsu ? (
                            <TextLink onClick={onCancel}>
                                {t("cancel")}
                            </TextLink>
                        ) : (
                            <AccountPrompt>
                                <span>{t("auth_new_account_prompt")}</span>
                                <TextLink regular onClick={onSignUp}>
                                    {t("sign_up")}
                                </TextLink>
                            </AccountPrompt>
                        )}
                        <Host>{host ?? ""}</Host>
                    </AccountActions>
                </FormFooter>
            </Form>
        </>
    );
}

const AccountActions = styled("div")({
    display: "flex",
    flexDirection: "column",
    alignItems: "center",
    gap: "10px",
    textAlign: "center",
});

const AccountPrompt = styled("div")({
    display: "flex",
    alignItems: "center",
    justifyContent: "center",
    gap: "6px",
    fontSize: "14px",
    fontWeight: 500,
    lineHeight: "20px",
    color: "var(--photos-auth-text-muted)",
});

const Host = styled("div")({
    minHeight: "16px",
    fontSize: "12px",
    fontWeight: 500,
    lineHeight: "16px",
    color: "var(--photos-auth-text-faint)",
});
