import { Link } from "@mui/material";
import {
    AccountsPageContents,
    AccountsPageFooter,
    AccountsPageTitle,
} from "ente-accounts/components/layouts/centered-paper";
import { savedPartialLocalUser } from "ente-accounts/services/accounts-db";
import {
    getRecoverTwoFactor,
    recoverTwoFactorFinish,
    type TwoFactorRecoveryResponse,
    type TwoFactorType,
} from "ente-accounts/services/user";
import { LinkButton } from "ente-base/components/LinkButton";
import { LoadingIndicator } from "ente-base/components/loaders";
import type { MiniDialogAttributes } from "ente-base/components/MiniDialog";
import {
    SingleInputForm,
    type SingleInputFormProps,
} from "ente-base/components/SingleInputForm";
import { useBaseContext } from "ente-base/context";
import { isHTTP4xxError, isHTTPErrorWithStatus } from "ente-base/http";
import log from "ente-base/log";
import { t } from "i18next";
import { useRouter } from "next/router";
import {
    useCallback,
    useEffect,
    useMemo,
    useState,
    type ComponentType,
} from "react";
import { Trans } from "react-i18next";

export interface TwoFactorRecoverPresentationProps {
    onSubmit: SingleInputFormProps["onSubmit"];
    onNoRecoveryKey: () => void;
    onBack: () => void;
}

export interface RecoverPageProps {
    twoFactorType: TwoFactorType;
    presentation?: ComponentType<TwoFactorRecoverPresentationProps>;
}

const Page: React.FC<RecoverPageProps> = ({
    twoFactorType,
    presentation: Presentation,
}) => {
    const { logout, showMiniDialog, onGenericError } = useBaseContext();

    const [sessionID, setSessionID] = useState<string | undefined>(undefined);
    const [recoveryResponse, setRecoveryResponse] = useState<
        TwoFactorRecoveryResponse | undefined
    >(undefined);

    const router = useRouter();

    const showContactSupportDialog = useCallback(
        (dialogContinue?: MiniDialogAttributes["continue"]) =>
            showMiniDialog({
                title: t("contact_support"),
                message: (
                    <Trans
                        i18nKey={"no_two_factor_recovery_key_message"}
                        components={{
                            a: <Link href="mailto:support@ente.com" />,
                        }}
                        values={{ emailID: "support@ente.com" }}
                    />
                ),
                continue: { color: "secondary", ...(dialogContinue ?? {}) },
                cancel: false,
            }),
        [showMiniDialog],
    );

    function handleNoRecoveryKey() {
        showContactSupportDialog();
    }

    useEffect(() => {
        void (async () => {
            const user = savedPartialLocalUser();
            const sessionID =
                twoFactorType == "passkey"
                    ? user?.passkeySessionID
                    : user?.twoFactorSessionID;
            if (!user?.email || !sessionID) {
                await router.replace("/");
            } else if (user.encryptedToken || user.token) {
                await router.replace("/generate");
            } else {
                setSessionID(sessionID);
                try {
                    setRecoveryResponse(
                        await getRecoverTwoFactor(twoFactorType, sessionID),
                    );
                } catch (e) {
                    log.error("Second factor recovery page setup failed", e);
                    if (isHTTPErrorWithStatus(e, 404)) {
                        logout();
                    } else if (isHTTP4xxError(e)) {
                        showContactSupportDialog({ action: router.back });
                    } else {
                        onGenericError(e);
                    }
                }
            }
        })();
    }, [
        twoFactorType,
        logout,
        showContactSupportDialog,
        onGenericError,
        router,
    ]);

    const handleSubmit: SingleInputFormProps["onSubmit"] | undefined = useMemo(
        () =>
            sessionID && recoveryResponse
                ? (recoveryKeyMnemonic, setFieldError) =>
                      recoverTwoFactorFinish(
                          twoFactorType,
                          sessionID,
                          recoveryResponse,
                          recoveryKeyMnemonic,
                      )
                          .then(() => router.push("/credentials"))
                          .catch((e: unknown) => {
                              log.error("Second factor recovery failed", e);
                              setFieldError(t("incorrect_recovery_key"));
                          })
                : undefined,
        [twoFactorType, router, sessionID, recoveryResponse],
    );

    if (!handleSubmit) {
        return <LoadingIndicator />;
    }

    if (Presentation) {
        return (
            <Presentation
                onSubmit={handleSubmit}
                onNoRecoveryKey={handleNoRecoveryKey}
                onBack={router.back}
            />
        );
    }

    return (
        <AccountsPageContents>
            <AccountsPageTitle>{t("recover_two_factor")}</AccountsPageTitle>
            <SingleInputForm
                autoComplete="off"
                label={t("recovery_key")}
                submitButtonTitle={t("recover")}
                onSubmit={handleSubmit}
            />
            <AccountsPageFooter>
                <LinkButton onClick={() => showContactSupportDialog()}>
                    {t("no_recovery_key_title")}
                </LinkButton>
                <LinkButton onClick={router.back}>{t("go_back")}</LinkButton>
            </AccountsPageFooter>
        </AccountsPageContents>
    );
};

export default Page;
