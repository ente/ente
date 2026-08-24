import { styled } from "@mui/material";
import type { TwoFactorVerifyPresentationProps } from "ente-accounts/pages/two-factor/verify";
import { isHTTP401Error } from "ente-base/http";
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

export function TwoFactorForm({
    onSubmit,
    onRecover,
    onChangeEmail,
}: TwoFactorVerifyPresentationProps): React.JSX.Element {
    const formik = useFormik({
        initialValues: { otp: "" },
        validateOnBlur: false,
        validateOnChange: false,
        onSubmit: async ({ otp }, { setFieldError, resetForm }) => {
            if (!completeCodePattern.test(otp)) {
                setFieldError("otp", t("required"));
                return;
            }

            try {
                await onSubmit(otp);
                resetForm();
            } catch (error) {
                log.error("Failed to submit 2FA code", error);
                resetForm();
                setFieldError(
                    "otp",
                    isHTTP401Error(error)
                        ? t("incorrect_code")
                        : t("generic_error"),
                );
            }
        },
    });

    function handleCodeChange(otp: string) {
        const shouldAutoSubmit =
            !completeCodePattern.test(formik.values.otp) &&
            completeCodePattern.test(otp);

        void formik.setFieldValue("otp", otp).then(() => {
            if (shouldAutoSubmit && !formik.isSubmitting) {
                void formik.submitForm();
            }
        });
    }

    return (
        <>
            <ScreenHeader
                title={t("two_factor")}
                subtitle={t("enter_two_factor_otp")}
            />
            <Form onSubmit={formik.handleSubmit}>
                <FormFields>
                    <OTPField
                        name="otp"
                        value={formik.values.otp}
                        onChange={handleCodeChange}
                        error={Boolean(formik.errors.otp)}
                        disabled={formik.isSubmitting}
                        autoFocus
                    />
                    <Message kind="error" visible={Boolean(formik.errors.otp)}>
                        {formik.errors.otp}
                    </Message>
                </FormFields>
                <FormFooter>
                    <Button
                        fullWidth
                        type="submit"
                        loading={formik.isSubmitting}
                        disabled={!completeCodePattern.test(formik.values.otp)}
                    >
                        {t("verify")}
                    </Button>
                    <FooterLinks>
                        <TextLink
                            onClick={onRecover}
                            disabled={formik.isSubmitting}
                        >
                            {t("lost_2fa_device")}
                        </TextLink>
                        <TextLink
                            onClick={onChangeEmail}
                            disabled={formik.isSubmitting}
                        >
                            {t("change_email")}
                        </TextLink>
                    </FooterLinks>
                </FormFooter>
            </Form>
        </>
    );
}

const FooterLinks = styled("div")({
    display: "flex",
    justifyContent: "space-between",
    gap: "16px",
});
