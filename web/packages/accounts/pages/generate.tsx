import { Divider } from "@mui/material";
import {
    AccountsPageContents,
    AccountsPageFooter,
    AccountsPageTitle,
} from "ente-accounts/components/layouts/centered-paper";
import {
    RecoveryKey,
    RecoveryKeyContents,
    type RecoveryKeyPresentationProps,
} from "ente-accounts/components/RecoveryKey";
import {
    savedJustSignedUp,
    savedOriginalKeyAttributes,
    savedPartialLocalUser,
    saveJustSignedUp,
} from "ente-accounts/services/accounts-db";
import { deriveKeyInsufficientMemoryErrorMessage } from "ente-accounts/services/crypto";
import { appHomeRoute } from "ente-accounts/services/redirect";
import {
    haveMasterKeyInSession,
    saveMasterKeyInSessionAndSafeStore,
} from "ente-accounts/services/session-storage";
import {
    generateSRPSetupAttributes,
    getAndSaveSRPAttributes,
    setupSRP,
} from "ente-accounts/services/srp";
import {
    generateAndSaveInteractiveKeyAttributes,
    generateKeysAndAttributes,
    putUserKeyAttributes,
} from "ente-accounts/services/user";
import { LinkButton } from "ente-base/components/LinkButton";
import { LoadingIndicator } from "ente-base/components/loaders";
import { useBaseContext } from "ente-base/context";
import log from "ente-base/log";
import { t } from "i18next";
import { useRouter } from "next/router";
import { useCallback, useEffect, useState, type ComponentType } from "react";
import {
    NewPasswordForm,
    type NewPasswordFormProps,
    type NewPasswordPresentationProps,
} from "../components/NewPasswordForm";

export interface GeneratePageProps {
    passwordPresentation?: ComponentType<NewPasswordPresentationProps>;
    recoveryKeyPresentation?: ComponentType<RecoveryKeyPresentationProps>;
}

const Page: React.FC<GeneratePageProps> = ({
    passwordPresentation,
    recoveryKeyPresentation,
}) => {
    const { logout, showMiniDialog } = useBaseContext();

    const [userEmail, setUserEmail] = useState("");
    const [openRecoveryKey, setOpenRecoveryKey] = useState(false);

    const router = useRouter();

    useEffect(() => {
        const user = savedPartialLocalUser();
        if (!user?.email || !user.token) {
            void router.replace("/");
        } else if (haveMasterKeyInSession()) {
            if (savedJustSignedUp()) {
                setOpenRecoveryKey(true);
            } else {
                void router.replace(appHomeRoute);
            }
        } else if (savedOriginalKeyAttributes()) {
            void router.replace("/credentials");
        } else {
            setUserEmail(user.email);
        }
    }, [router]);

    const handleSubmit: NewPasswordFormProps["onSubmit"] = useCallback(
        async (password, setPasswordsFieldError) => {
            try {
                const { masterKey, kek, keyAttributes } =
                    await generateKeysAndAttributes(password);
                await putUserKeyAttributes(keyAttributes);
                await setupSRP(await generateSRPSetupAttributes(kek));
                await getAndSaveSRPAttributes(userEmail);
                await generateAndSaveInteractiveKeyAttributes(
                    password,
                    keyAttributes,
                    masterKey,
                );
                await saveMasterKeyInSessionAndSafeStore(masterKey);
                saveJustSignedUp();
                setOpenRecoveryKey(true);
            } catch (e) {
                log.error("Could not generate key attributes from password", e);
                setPasswordsFieldError(
                    e instanceof Error &&
                        e.message == deriveKeyInsufficientMemoryErrorMessage
                        ? t("password_generation_failed")
                        : t("generic_error"),
                );
            }
        },
        [userEmail],
    );

    function handleRecoveryKeyClose() {
        void router.push(appHomeRoute);
    }

    if (openRecoveryKey && recoveryKeyPresentation) {
        return (
            <RecoveryKeyContents
                open
                onClose={handleRecoveryKeyClose}
                showMiniDialog={showMiniDialog}
                presentation={recoveryKeyPresentation}
            />
        );
    }

    return openRecoveryKey ? (
        <RecoveryKey
            open
            onClose={handleRecoveryKeyClose}
            showMiniDialog={showMiniDialog}
        />
    ) : userEmail && passwordPresentation ? (
        <NewPasswordForm
            userEmail={userEmail}
            submitButtonTitle={t("set_password")}
            onSubmit={handleSubmit}
            onBack={logout}
            presentation={passwordPresentation}
        />
    ) : userEmail ? (
        <AccountsPageContents>
            <AccountsPageTitle>{t("set_password")}</AccountsPageTitle>
            <NewPasswordForm
                userEmail={userEmail}
                submitButtonTitle={t("set_password")}
                onSubmit={handleSubmit}
            />
            <Divider sx={{ mt: 1 }} />
            <AccountsPageFooter>
                <LinkButton onClick={logout}>{t("go_back")}</LinkButton>
            </AccountsPageFooter>
        </AccountsPageContents>
    ) : (
        <LoadingIndicator />
    );
};

export default Page;
