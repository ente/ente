import { CircularProgress, Stack, Typography, styled } from "@mui/material";
import { sessionExpiredDialogAttributes } from "ente-accounts/components/utils/dialog";
import {
    checkPasskeyVerificationStatus,
    saveCredentialsAndNavigateTo,
} from "ente-accounts/services/passkey";
import { LinkButton } from "ente-base/components/LinkButton";
import type { MiniDialogAttributes } from "ente-base/components/MiniDialog";
import { FocusVisibleButton } from "ente-base/components/mui/FocusVisibleButton";
import { genericErrorDialogAttributes } from "ente-base/components/utils/dialog";
import { isNamedError } from "ente-base/error";
import log from "ente-base/log";
import { customAPIHost } from "ente-base/origins";
import { t } from "i18next";
import { useRouter } from "next/router";
import React, { useEffect, useState } from "react";
import {
    AccountsPageContents,
    AccountsPageFooter,
} from "./layouts/centered-paper";

interface HeaderCaptionProps {
    caption?: string;
}

export const PasswordHeader: React.FC<HeaderCaptionProps> = (props) => (
    <AccountsPageTitleWithCaption {...props}>
        {t("password")}
    </AccountsPageTitleWithCaption>
);

const PasskeyHeader: React.FC<HeaderCaptionProps> = (props) => (
    <AccountsPageTitleWithCaption {...props}>
        {t("passkey")}
    </AccountsPageTitleWithCaption>
);

export const AccountsPageTitleWithCaption: React.FC<
    React.PropsWithChildren<HeaderCaptionProps>
> = ({ caption, children }) => {
    return (
        <Header_>
            <Typography variant="h3">{children}</Typography>
            <Typography sx={{ color: "text.faint" }}>
                {caption ?? ""}
            </Typography>
        </Header_>
    );
};

const Header_ = styled("div")`
    margin-block-end: 24px;
    display: flex;
    flex-direction: column;
    gap: 8px;
`;

export const AccountsPageFooterWithHost: React.FC<React.PropsWithChildren> = ({
    children,
}) => {
    const [host, setHost] = useState<string | undefined>();

    useEffect(() => void customAPIHost().then(setHost), []);

    return (
        <Stack sx={{ gap: 3 }}>
            <AccountsPageFooter>{children}</AccountsPageFooter>
            {host && (
                <Typography
                    variant="small"
                    sx={{ mx: "4px", color: "text.faint" }}
                >
                    {host}
                </Typography>
            )}
        </Stack>
    );
};

export type PasskeyVerificationStatus = "waiting" | "checking" | "pending";

export interface VerifyingPasskeyPresentationProps {
    email: string | undefined;
    host: string | undefined;
    verificationStatus: PasskeyVerificationStatus;
    isChecking: boolean;
    onRetry: () => void;
    onCheckStatus: () => void;
    onRecover: () => void;
    onChangeEmail: () => void;
}

interface VerifyingPasskeyProps {
    passkeySessionID: string;
    email: string | undefined;
    onRetry: () => void;
    logout: () => void;
    showMiniDialog: (attrs: MiniDialogAttributes) => void;
    presentation?: React.ComponentType<VerifyingPasskeyPresentationProps>;
}

export const VerifyingPasskey: React.FC<VerifyingPasskeyProps> = ({
    passkeySessionID,
    email,
    onRetry,
    logout,
    showMiniDialog,
    presentation: Presentation,
}) => {
    const [verificationStatus, setVerificationStatus] =
        useState<PasskeyVerificationStatus>("waiting");
    const [host, setHost] = useState<string | undefined>();

    const router = useRouter();

    useEffect(() => {
        if (Presentation) void customAPIHost().then(setHost);
    }, [Presentation]);

    const handleRetry = () => {
        setVerificationStatus("waiting");
        onRetry();
    };

    const handleCheckStatus = async () => {
        setVerificationStatus("checking");
        try {
            const response =
                await checkPasskeyVerificationStatus(passkeySessionID);
            if (!response) setVerificationStatus("pending");
            else void router.push(await saveCredentialsAndNavigateTo(response));
        } catch (e) {
            log.error("Passkey verification status check failed", e);
            showMiniDialog(
                isNamedError(e, "passkey_session_expired")
                    ? sessionExpiredDialogAttributes(logout)
                    : genericErrorDialogAttributes(),
            );
            setVerificationStatus("waiting");
        }
    };

    const handleRecover = () => {
        void router.push("/passkeys/recover");
    };

    const handleCheckStatusClick = () => {
        void handleCheckStatus();
    };

    if (Presentation) {
        return (
            <Presentation
                email={email}
                host={host}
                verificationStatus={verificationStatus}
                isChecking={verificationStatus === "checking"}
                onRetry={handleRetry}
                onCheckStatus={handleCheckStatusClick}
                onRecover={handleRecover}
                onChangeEmail={logout}
            />
        );
    }

    return (
        <AccountsPageContents>
            <PasskeyHeader caption={email} />

            <VerifyingPasskeyMiddle>
                <VerifyingPasskeyStatus>
                    {verificationStatus == "checking" ? (
                        <Typography>
                            <CircularProgress color="accent" size="1.5em" />
                        </Typography>
                    ) : (
                        <Typography sx={{ color: "text.muted" }}>
                            {verificationStatus == "waiting"
                                ? t("waiting_for_verification")
                                : t("verification_still_pending")}
                        </Typography>
                    )}
                </VerifyingPasskeyStatus>

                <ButtonStack>
                    <FocusVisibleButton
                        onClick={handleRetry}
                        fullWidth
                        color="secondary"
                    >
                        {t("try_again")}
                    </FocusVisibleButton>

                    <FocusVisibleButton
                        onClick={handleCheckStatus}
                        fullWidth
                        color="accent"
                    >
                        {t("check_status")}
                    </FocusVisibleButton>
                </ButtonStack>
            </VerifyingPasskeyMiddle>

            <AccountsPageFooterWithHost>
                <LinkButton onClick={handleRecover}>
                    {t("recover_account")}
                </LinkButton>
                <LinkButton onClick={logout}>{t("change_email")}</LinkButton>
            </AccountsPageFooterWithHost>
        </AccountsPageContents>
    );
};

const VerifyingPasskeyMiddle = styled("div")`
    display: flex;
    flex-direction: column;

    padding-block: 1rem;
    gap: 4rem;
`;

const VerifyingPasskeyStatus = styled("div")`
    text-align: center;
    /* Size of the CircularProgress (+ some margin) so that there is no layout
       shift when it is shown */
    min-height: 2em;
`;

const ButtonStack = styled("div")`
    display: flex;
    flex-direction: column;
    gap: 1rem;
`;
