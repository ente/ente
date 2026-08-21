import { styled } from "@mui/material";
import type { RecoverAccountPresentationProps } from "ente-accounts/pages/recover";
import type { TwoFactorRecoverPresentationProps } from "ente-accounts/pages/two-factor/recover";
import log from "ente-base/log";
import { useFormik } from "formik";
import { t } from "i18next";
import React, { useState } from "react";
import {
    AuthDialog,
    AuthDialogHeader,
    AuthDialogText,
    AuthDialogTitle,
} from "./AuthDialog";
import { Button } from "./Button";
import { Form } from "./Form";
import { FormFields } from "./FormFields";
import { FormFooter } from "./FormFooter";
import { ScreenHeader } from "./ScreenHeader";
import { authDialogContentLayout } from "./styles";
import { TextField } from "./TextField";
import { TextLink } from "./TextLink";

export function RecoverAccountForm(
    props: RecoverAccountPresentationProps,
): React.JSX.Element {
    const [showNoRecoveryKey, setShowNoRecoveryKey] = useState(false);

    return (
        <>
            <RecoveryForm
                {...props}
                onNoRecoveryKey={() => setShowNoRecoveryKey(true)}
                title={t("recover_account")}
                subtitle={t("auth_recover_account_subtitle")}
            />
            <AuthDialog
                open={showNoRecoveryKey}
                onClose={() => setShowNoRecoveryKey(false)}
                ariaLabelledby="no-recovery-key-title"
            >
                <DialogContent>
                    <AuthDialogHeader>
                        <AuthDialogTitle id="no-recovery-key-title">
                            {t("sorry")}
                        </AuthDialogTitle>
                        <AuthDialogText>
                            {t("no_recovery_key_message")}
                        </AuthDialogText>
                    </AuthDialogHeader>
                    <Button
                        variant="secondary"
                        fullWidth
                        autoFocus
                        onClick={() => setShowNoRecoveryKey(false)}
                    >
                        {t("ok")}
                    </Button>
                </DialogContent>
            </AuthDialog>
        </>
    );
}

const DialogContent = styled("div")(authDialogContentLayout);

export function RecoverTwoFactorForm(
    props: TwoFactorRecoverPresentationProps,
): React.JSX.Element {
    return (
        <RecoveryForm
            {...props}
            title={t("recover_two_factor")}
            subtitle={t("auth_recover_two_factor_subtitle")}
        />
    );
}

interface RecoveryFormProps extends RecoverAccountPresentationProps {
    title: React.ReactNode;
    subtitle: React.ReactNode;
}

function RecoveryForm({
    title,
    subtitle,
    onSubmit,
    onNoRecoveryKey,
    onBack,
}: RecoveryFormProps): React.JSX.Element {
    const formik = useFormik({
        initialValues: { recoveryKey: "" },
        onSubmit: async ({ recoveryKey }, { setFieldError }) => {
            function setRecoveryKeyError(message: string) {
                setFieldError("recoveryKey", message);
            }

            if (!recoveryKey) {
                setRecoveryKeyError(t("required"));
                return;
            }

            try {
                await onSubmit(recoveryKey, setRecoveryKeyError);
            } catch (error) {
                log.error("Failed to submit recovery key", error);
                setRecoveryKeyError(t("generic_error"));
            }
        },
    });

    function handleRecoveryKeyDown(
        event: React.KeyboardEvent<HTMLInputElement | HTMLTextAreaElement>,
    ) {
        if (
            event.key === "Enter" &&
            !event.shiftKey &&
            !event.nativeEvent.isComposing
        ) {
            event.preventDefault();
            void formik.submitForm();
        }
    }

    return (
        <>
            <ScreenHeader title={title} subtitle={subtitle} />
            <Form onSubmit={formik.handleSubmit}>
                <FormFields>
                    <TextField
                        name="recoveryKey"
                        label={t("recovery_key")}
                        placeholder={t("auth_recovery_key_placeholder")}
                        value={formik.values.recoveryKey}
                        onChange={formik.handleChange}
                        onKeyDown={handleRecoveryKeyDown}
                        autoComplete="off"
                        multiline
                        rows={5}
                        autoFocus
                        disabled={formik.isSubmitting}
                        error={Boolean(formik.errors.recoveryKey)}
                        helperText={formik.errors.recoveryKey}
                    />
                </FormFields>
                <FormFooter>
                    <Button
                        fullWidth
                        type="submit"
                        loading={formik.isSubmitting}
                    >
                        {t("recover")}
                    </Button>
                    <FooterLinks>
                        <TextLink
                            onClick={onNoRecoveryKey}
                            disabled={formik.isSubmitting}
                        >
                            {t("no_recovery_key_title")}
                        </TextLink>
                        <TextLink
                            onClick={onBack}
                            disabled={formik.isSubmitting}
                        >
                            {t("go_back")}
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
