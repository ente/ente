import { useAuthPageConfig } from "ente-accounts/components/auth/AuthPageProvider";
import { RecoveryKeyForm } from "ente-accounts/components/auth/RecoveryKeyForm";
import { SetPasswordForm } from "ente-accounts/components/auth/SetPasswordForm";
import { RecoveryKeyContents } from "ente-accounts/components/RecoveryKey";
import {
    savedJustSignedUp,
    savedOriginalKeyAttributes,
    savedPartialLocalUser,
    saveIsFirstLogin,
    saveJustSignedUp,
    saveKeyAttributes,
    saveOriginalKeyAttributes,
    stashSRPSetupAttributes,
} from "ente-accounts/services/accounts-db";
import { deriveKey } from "ente-accounts/services/crypto";
import { saveMasterKeyInSessionAndSafeStore } from "ente-accounts/services/prelogin-session";
import { getPreloginRecoveryKeyMnemonic } from "ente-accounts/services/recovery-key";
import { appHomeRoute } from "ente-accounts/services/redirect";
import { completePendingSignup } from "ente-accounts/services/srp";
import {
    generateAndSaveInteractiveKeyAttributes,
    generateSignupKeys,
    unlockAccountWithKEK,
} from "ente-accounts/services/user";
import { LoadingIndicator } from "ente-base/components/loaders";
import { useBaseContext } from "ente-base/context";
import { isNamedError } from "ente-base/error";
import log from "ente-base/log";
import { haveMasterKeyInSession } from "ente-base/session-storage";
import { ensureAuthToken } from "ente-base/token";
import { t } from "i18next";
import { useRouter } from "next/router";
import { useCallback, useEffect, useState } from "react";
import {
    NewPasswordForm,
    type NewPasswordFormProps,
} from "../components/NewPasswordForm";

const Page: React.FC = () => {
    const { Shell, recoveryKeyCloseDestination } = useAuthPageConfig();
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
                let keyAttributes = savedOriginalKeyAttributes();
                let masterKey: string;
                if (keyAttributes) {
                    const kek = await deriveKey(
                        password,
                        keyAttributes.kekSalt,
                        keyAttributes.opsLimit,
                        keyAttributes.memLimit,
                    );
                    ({ masterKey } = await unlockAccountWithKEK(
                        {
                            id: savedPartialLocalUser()!.id!,
                            token: await ensureAuthToken(),
                            keyAttributes,
                        },
                        kek,
                    ));
                } else {
                    const generated = await generateSignupKeys(password);
                    ({ masterKey, keyAttributes } = generated);
                    saveOriginalKeyAttributes(keyAttributes);
                    saveKeyAttributes(keyAttributes);
                    stashSRPSetupAttributes(generated.srp);
                    saveIsFirstLogin();
                }
                await completePendingSignup(userEmail, await ensureAuthToken());
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
                    isNamedError(e, "insufficient_memory")
                        ? t("password_generation_failed")
                        : t("generic_error"),
                );
            }
        },
        [userEmail],
    );

    function handleRecoveryKeyClose() {
        void router.push(recoveryKeyCloseDestination ?? appHomeRoute);
    }

    if (openRecoveryKey) {
        return (
            <Shell key="recovery-key">
                <RecoveryKeyContents
                    open
                    onClose={handleRecoveryKeyClose}
                    getRecoveryKeyMnemonic={getPreloginRecoveryKeyMnemonic}
                    showMiniDialog={showMiniDialog}
                    presentation={RecoveryKeyForm}
                />
            </Shell>
        );
    }

    return userEmail ? (
        <Shell>
            <NewPasswordForm
                userEmail={userEmail}
                submitButtonTitle={t("set_password")}
                onSubmit={handleSubmit}
                onBack={logout}
                presentation={SetPasswordForm}
            />
        </Shell>
    ) : (
        <LoadingIndicator />
    );
};

export default Page;
