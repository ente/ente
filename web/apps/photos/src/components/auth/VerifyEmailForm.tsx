import { styled } from "@mui/material";
import type { VerifyEmailPresentationProps } from "ente-accounts/pages/verify";
import { pt } from "ente-base/i18n";
import log from "ente-base/log";
import { useFormik } from "formik";
import { t } from "i18next";
import type React from "react";
import { Button } from "./Button";
import { Form } from "./Form";
import { FormFields } from "./FormFields";
import { FormFooter } from "./FormFooter";
import { Message } from "./Message";
import { OTPField } from "./OTPField";
import { ScreenHeader } from "./ScreenHeader";
import { TextLink } from "./TextLink";

const completeCodePattern = /^\d{6}$/;

export function VerifyEmailForm({
    email,
    resend,
    onSubmit,
    onResend,
    onChangeEmail,
}: VerifyEmailPresentationProps): React.JSX.Element {
    const formik = useFormik({
        initialValues: { code: "" },
        onSubmit: async ({ code }, { setFieldError }) => {
            function setCodeError(message: string) {
                setFieldError("code", message);
            }

            if (!completeCodePattern.test(code)) {
                setCodeError(t("required"));
                return;
            }

            try {
                await onSubmit(code, setCodeError);
            } catch (error) {
                log.error("Failed to submit email verification code", error);
                setCodeError(t("generic_error"));
            }
        },
    });

    function handleCodeChange(code: string) {
        const shouldAutoSubmit =
            !completeCodePattern.test(formik.values.code) &&
            completeCodePattern.test(code);

        void formik.setFieldValue("code", code).then(() => {
            if (shouldAutoSubmit && !formik.isSubmitting) {
                void formik.submitForm();
            }
        });
    }

    const resendLabel =
        resend === "sending"
            ? t("status_sending")
            : resend === "sent"
              ? t("status_sent")
              : t("resend_code");

    return (
        <>
            <ScreenHeader
                title={pt("Check your inbox")}
                subtitle={
                    <>
                        {pt("We sent a verification code to ")}
                        <Email>{email}</Email>
                    </>
                }
            />
            <Form onSubmit={formik.handleSubmit}>
                <FormFields>
                    <FieldLabel>{t("verification_code")}</FieldLabel>
                    <OTPField
                        name="code"
                        value={formik.values.code}
                        onChange={handleCodeChange}
                        error={Boolean(formik.errors.code)}
                        disabled={formik.isSubmitting}
                        autoFocus
                    />
                    {formik.errors.code ? (
                        <Message kind="error">{formik.errors.code}</Message>
                    ) : null}
                </FormFields>
                <FormFooter>
                    <Button
                        fullWidth
                        type="submit"
                        loading={formik.isSubmitting}
                    >
                        {t("verify")}
                    </Button>
                    <FooterLinks>
                        <TextLink
                            onClick={onResend}
                            disabled={resend !== "enable"}
                        >
                            {resendLabel}
                        </TextLink>
                        <TextLink onClick={onChangeEmail}>
                            {t("change_email")}
                        </TextLink>
                    </FooterLinks>
                </FormFooter>
            </Form>
        </>
    );
}

const Email = styled("strong")({
    color: "var(--photos-auth-text)",
    wordBreak: "break-word",
});

const FieldLabel = styled("span")({
    fontSize: "12px",
    fontWeight: 500,
    lineHeight: "16px",
    color: "var(--photos-auth-text-muted)",
});

const FooterLinks = styled("div")({
    display: "flex",
    justifyContent: "space-between",
    gap: "16px",
});
