import { InformationCircleIcon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { CircularProgress, styled } from "@mui/material";
import { Button } from "ente-accounts/components/auth/Button";
import { FormFooter } from "ente-accounts/components/auth/FormFooter";
import { ScreenHeader } from "ente-accounts/components/auth/ScreenHeader";
import {
    authBodyTypography,
    authMiniTypography,
    authTransientProps,
} from "ente-accounts/components/auth/styles";
import { TextLink } from "ente-accounts/components/auth/TextLink";
import type { VerifyingPasskeyPresentationProps } from "ente-accounts/components/LoginComponents";
import { t } from "i18next";
import type React from "react";
import { Trans } from "react-i18next";

export function PasskeyVerificationForm({
    email,
    host,
    verificationStatus,
    isChecking,
    onRetry,
    onCheckStatus,
    onRecover,
    onChangeEmail,
}: VerifyingPasskeyPresentationProps): React.JSX.Element {
    const stalled = verificationStatus === "pending";

    const checkStatusButton = (
        <Button
            fullWidth
            variant={stalled ? "secondary" : "primary"}
            onClick={onCheckStatus}
            loading={isChecking}
        >
            {t("check_status")}
        </Button>
    );

    const reopenButton = (
        <Button
            fullWidth
            variant={stalled ? "primary" : "secondary"}
            onClick={onRetry}
            disabled={isChecking}
        >
            {t("auth_passkey_reopen")}
        </Button>
    );

    return (
        <>
            <ScreenHeader
                title={t("auth_passkey_verify_title")}
                subtitle={
                    email ? (
                        <Trans
                            i18nKey="auth_passkey_window_opened_for"
                            components={{ a: <Email /> }}
                            values={{ email }}
                        />
                    ) : (
                        t("auth_passkey_window_opened")
                    )
                }
            />
            <StatusCard role="status" $stalled={stalled}>
                {stalled ? (
                    <StatusIcon>
                        <HugeiconsIcon
                            icon={InformationCircleIcon}
                            size={20}
                            strokeWidth={2}
                            aria-hidden="true"
                        />
                    </StatusIcon>
                ) : (
                    <CircularProgress
                        size={20}
                        sx={{ color: "var(--auth-ui-primary)", flexShrink: 0 }}
                    />
                )}
                <StatusText>
                    <StatusTitle>
                        {stalled
                            ? t("auth_passkey_still_waiting")
                            : t("waiting_for_verification")}
                    </StatusTitle>
                    <StatusCaption>
                        {stalled
                            ? t("auth_passkey_stalled_hint")
                            : t("auth_passkey_auto_updates")}
                    </StatusCaption>
                </StatusText>
            </StatusCard>
            <FormFooter>
                {stalled ? (
                    <>
                        {reopenButton}
                        {checkStatusButton}
                    </>
                ) : (
                    <>
                        {checkStatusButton}
                        {reopenButton}
                    </>
                )}
                <FooterLinks>
                    <TextLink onClick={onRecover} disabled={isChecking}>
                        {t("recover_account")}
                    </TextLink>
                    <TextLink onClick={onChangeEmail} disabled={isChecking}>
                        {t("change_email")}
                    </TextLink>
                </FooterLinks>
                <Host>{host ?? ""}</Host>
            </FormFooter>
        </>
    );
}

const Email = styled("strong")({
    color: "var(--auth-ui-text)",
    wordBreak: "break-word",
});

const StatusCard = styled(
    "div",
    authTransientProps,
)<{ $stalled: boolean }>(({ $stalled }) => ({
    padding: "16px",
    borderRadius: "20px",
    display: "flex",
    alignItems: $stalled ? "flex-start" : "center",
    gap: "12px",
    backgroundColor: $stalled
        ? "color-mix(in srgb, var(--auth-ui-caution) 12%, transparent)"
        : "var(--auth-ui-field)",
    boxShadow: `inset 0 0 0 1px ${
        $stalled
            ? "color-mix(in srgb, var(--auth-ui-caution) 32%, transparent)"
            : "var(--auth-ui-stroke)"
    }`,
}));

const StatusIcon = styled("div")({
    flexShrink: 0,
    display: "flex",
    color: "var(--auth-ui-caution)",
});

const StatusText = styled("div")({
    display: "flex",
    flexDirection: "column",
    gap: "2px",
});

const StatusTitle = styled("div")({
    ...authBodyTypography,
    fontWeight: 600,
    color: "var(--auth-ui-text)",
});

const StatusCaption = styled("p")({
    ...authMiniTypography,
    margin: 0,
    textWrap: "pretty",
    color: "var(--auth-ui-text-muted)",
});

const FooterLinks = styled("div")({
    display: "flex",
    justifyContent: "space-between",
    gap: "16px",
});

const Host = styled("div")({
    ...authMiniTypography,
    minHeight: "16px",
    textAlign: "center",
    color: "var(--auth-ui-text-faint)",
});
