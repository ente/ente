import CheckIcon from "@mui/icons-material/Check";
import { Alert, Box, TextField } from "@mui/material";
import {
    AccountsPageContents,
    AccountsPageFooter,
    AccountsPageTitle,
} from "ente-accounts/components/layouts/centered-paper";
import { useRedirectIfNeedsCredentials } from "ente-accounts/components/utils/use-redirect";
import { appHomeRoute } from "ente-accounts/services/redirect";
import { changeEmail, sendOTT } from "ente-accounts/services/user";
import { LinkButton } from "ente-base/components/LinkButton";
import { LoadingButton } from "ente-base/components/mui/LoadingButton";
import { isHTTPErrorWithStatus } from "ente-base/http";
import log from "ente-base/log";
import { useFormik } from "formik";
import { t } from "i18next";
import { useRouter } from "next/router";
import { useCallback, useState } from "react";
import { Trans } from "react-i18next";
import { z } from "zod";

const Page: React.FC = () => {
    useRedirectIfNeedsCredentials("/change-email");

    return (
        <AccountsPageContents>
            <AccountsPageTitle>{t("change_email")}</AccountsPageTitle>
            <ChangeEmailForm />
        </AccountsPageContents>
    );
};

export default Page;

const ChangeEmailForm: React.FC = () => {
    const [requestedEmail, setRequestedEmail] = useState("");
    const [showSentConfirmation, setShowSentConfirmation] = useState(false);

    const router = useRouter();

    const redirectToAppHome = useCallback(() => {
        void router.push(appHomeRoute);
    }, [router]);

    const formik = useFormik({
        initialValues: { email: "", ott: "" },
        onSubmit: async ({ email, ott }, { setFieldError }) => {
            if (!email) {
                setFieldError("email", t("required"));
                return;
            }

            if (!z.email().safeParse(email).success) {
                setFieldError("email", t("invalid_email_error"));
                return;
            }

            if (!requestedEmail) {
                try {
                    await sendOTT(email, "change");
                } catch (e) {
                    log.error("Could not send OTT for email change", e);
                    setFieldError(
                        "email",
                        isHTTPErrorWithStatus(e, 403)
                            ? t("email_already_taken")
                            : t("generic_error"),
                    );
                    return;
                }

                setRequestedEmail(email);
                setShowSentConfirmation(true);
            } else {
                if (!ott) {
                    setFieldError("ott", t("required"));
                    return;
                }

                try {
                    await changeEmail(email, ott);
                } catch (e) {
                    log.error("Could not change email", e);
                    setFieldError(
                        "ott",
                        isHTTPErrorWithStatus(e, 401)
                            ? t("incorrect_code")
                            : isHTTPErrorWithStatus(e, 410)
                              ? t("expired_code_error")
                              : t("generic_error"),
                    );
                    return;
                }

                redirectToAppHome();
            }
        },
    });

    return (
        <>
            {requestedEmail && showSentConfirmation && (
                <Alert
                    icon={<CheckIcon fontSize="inherit" />}
                    severity="success"
                    onClose={() => setShowSentConfirmation(false)}
                >
                    <Trans
                        i18nKey="email_sent"
                        components={{
                            a: (
                                <Box
                                    component={"span"}
                                    sx={{ color: "text.muted" }}
                                />
                            ),
                        }}
                        values={{ email: requestedEmail }}
                    />
                </Alert>
            )}
            <form onSubmit={formik.handleSubmit}>
                <TextField
                    name="email"
                    type="email"
                    label={t("enter_email")}
                    value={formik.values.email}
                    onChange={formik.handleChange}
                    error={!!formik.errors.email}
                    helperText={
                        formik.errors.email ?? (requestedEmail ? "" : " ")
                    }
                    disabled={formik.isSubmitting}
                    autoFocus
                    fullWidth
                    slotProps={{ input: { readOnly: !!requestedEmail } }}
                />
                {requestedEmail && (
                    <TextField
                        name="ott"
                        type="text"
                        label={t("verification_code")}
                        value={formik.values.ott}
                        onChange={formik.handleChange}
                        error={!!formik.errors.ott}
                        helperText={formik.errors.ott ?? " "}
                        disabled={formik.isSubmitting}
                        fullWidth
                    />
                )}
                <LoadingButton
                    type="submit"
                    color="accent"
                    fullWidth
                    loading={formik.isSubmitting}
                    sx={{ mt: 1, mb: 3 }}
                >
                    {!requestedEmail ? t("send_otp") : t("verify")}
                </LoadingButton>
            </form>
            <AccountsPageFooter>
                {requestedEmail && (
                    <LinkButton onClick={() => setRequestedEmail("")}>
                        {t("change_email")}?
                    </LinkButton>
                )}
                <LinkButton onClick={redirectToAppHome}>
                    {t("go_back")}
                </LinkButton>
            </AccountsPageFooter>
        </>
    );
};
