import { Link } from "@mui/material";
import { useAuthPageConfig } from "ente-accounts/components/auth/AuthPageProvider";
import { RecoverTwoFactorForm } from "ente-accounts/components/auth/RecoveryForm";
import { savedPartialLocalUser } from "ente-accounts/services/accounts-db";
import {
    getRecoverTwoFactor,
    recoverTwoFactorFinish,
    type TwoFactorRecovery,
    type TwoFactorType,
} from "ente-accounts/services/user";
import { LoadingIndicator } from "ente-base/components/loaders";
import type { MiniDialogAttributes } from "ente-base/components/MiniDialog";
import type { SingleInputFormProps } from "ente-base/components/SingleInputForm";
import { useBaseContext } from "ente-base/context";
import { isNamedError } from "ente-base/error";
import log from "ente-base/log";
import { t } from "i18next";
import { useRouter } from "next/router";
import { useCallback, useEffect, useMemo, useState } from "react";
import { Trans } from "react-i18next";

export interface TwoFactorRecoverPresentationProps {
    onSubmit: SingleInputFormProps["onSubmit"];
    onNoRecoveryKey: () => void;
    onBack: () => void;
}

interface RecoverPageProps {
    twoFactorType?: TwoFactorType;
}

const Page: React.FC<RecoverPageProps> = ({ twoFactorType = "totp" }) => {
    const { Shell } = useAuthPageConfig();
    const { logout, showMiniDialog, onGenericError } = useBaseContext();

    const [sessionID, setSessionID] = useState<string | undefined>(undefined);
    const [recovery, setRecovery] = useState<TwoFactorRecovery | undefined>(
        undefined,
    );

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
                    setRecovery(
                        await getRecoverTwoFactor(twoFactorType, sessionID),
                    );
                } catch (e) {
                    log.error("Second factor recovery page setup failed", e);
                    if (isNamedError(e, "session_expired")) {
                        logout();
                    } else if (
                        isNamedError(e, "two_factor_recovery_not_configured")
                    ) {
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
            sessionID && recovery
                ? (recoveryKeyMnemonic, setFieldError) =>
                      recoverTwoFactorFinish(
                          twoFactorType,
                          sessionID,
                          recovery,
                          recoveryKeyMnemonic,
                      )
                          .then(() => router.push("/credentials"))
                          .catch((e: unknown) => {
                              log.error("Second factor recovery failed", e);
                              if (isNamedError(e, "session_expired")) {
                                  logout();
                              } else {
                                  setFieldError(t("incorrect_recovery_key"));
                              }
                          })
                : undefined,
        [twoFactorType, router, sessionID, recovery, logout],
    );

    if (!handleSubmit) {
        return <LoadingIndicator />;
    }

    return (
        <Shell contentWidth={420}>
            <RecoverTwoFactorForm
                onSubmit={handleSubmit}
                onNoRecoveryKey={handleNoRecoveryKey}
                onBack={router.back}
            />
        </Shell>
    );
};

export default Page;
