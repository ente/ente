import { AccountsPageContents } from "ente-accounts/components/layouts/centered-paper";
import {
    AccountsPageFooterWithHost,
    PasswordHeader,
    VerifyingPasskey,
    type VerifyingPasskeyPresentationProps,
} from "ente-accounts/components/LoginComponents";
import {
    SecondFactorChoice,
    type SecondFactorChoicePresentationProps,
} from "ente-accounts/components/SecondFactorChoice";
import { sessionExpiredDialogAttributes } from "ente-accounts/components/utils/dialog";
import { useSecondFactorChoiceIfNeeded } from "ente-accounts/components/utils/second-factor-choice";
import {
    VerifyMasterPasswordForm,
    type VerifyMasterPasswordFormProps,
    type VerifyMasterPasswordPresentationProps,
} from "ente-accounts/components/VerifyMasterPasswordForm";
import {
    savedIsFirstLogin,
    savedKeyAttributes,
    savedPartialLocalUser,
    savedSRPAttributes,
    saveIsFirstLogin,
    saveKeyAttributes,
    saveSRPAttributes,
    updateSavedLocalUser,
} from "ente-accounts/services/accounts-db";
import { decryptBox } from "ente-accounts/services/crypto";
import {
    openPasskeyVerificationURL,
    passkeyVerificationRedirectURL,
} from "ente-accounts/services/passkey";
import {
    appHomeRoute,
    stashRedirect,
    unstashRedirect,
} from "ente-accounts/services/redirect";
import { checkSessionValidity } from "ente-accounts/services/session";
import {
    masterKeyFromSession,
    saveMasterKeyInSessionAndSafeStore,
    stashKeyEncryptionKeyInSessionStore,
    unstashKeyEncryptionKeyFromSession,
    updateSessionFromElectronSafeStorageIfNeeded,
} from "ente-accounts/services/session-storage";
import type { SRPAttributes } from "ente-accounts/services/srp";
import {
    generateSRPSetupAttributes,
    getAndSaveSRPAttributes,
    getSRPAttributes,
    setupSRP,
    verifySRP,
} from "ente-accounts/services/srp";
import {
    decryptAndStoreTokenIfNeeded,
    generateAndSaveInteractiveKeyAttributes,
    type KeyAttributes,
} from "ente-accounts/services/user";
import { LinkButton } from "ente-base/components/LinkButton";
import { LoadingIndicator } from "ente-base/components/loaders";
import { useBaseContext } from "ente-base/context";
import { isDevBuild } from "ente-base/env";
import { clearLocalStorage } from "ente-base/local-storage";
import log from "ente-base/log";
import { customAPIHost } from "ente-base/origins";
import { saveAuthToken, savedAuthToken } from "ente-base/token";
import { t } from "i18next";
import { useRouter } from "next/router";
import {
    useCallback,
    useEffect,
    useState,
    type ComponentType,
    type ReactNode,
} from "react";

export interface CredentialsPresentationProps {
    userEmail: string;
    host: string | undefined;
    passwordForm: ReactNode;
    onRecover: () => void;
    onChangeEmail: () => void;
}

export interface CredentialsPageProps {
    presentation?: ComponentType<CredentialsPresentationProps>;
    passwordPresentation?: ComponentType<VerifyMasterPasswordPresentationProps>;
    passkeyPresentation?: ComponentType<VerifyingPasskeyPresentationProps>;
    secondFactorChoicePresentation?: ComponentType<SecondFactorChoicePresentationProps>;
}

const Page: React.FC<CredentialsPageProps> = ({
    presentation: Presentation,
    passwordPresentation,
    passkeyPresentation,
    secondFactorChoicePresentation,
}) => {
    const { logout, showMiniDialog } = useBaseContext();

    const [userEmail, setUserEmail] = useState<string>("");
    const [keyAttributes, setKeyAttributes] = useState<
        KeyAttributes | undefined
    >(undefined);
    const [srpAttributes, setSRPAttributes] = useState<
        SRPAttributes | undefined
    >(undefined);
    const [passkeyVerificationData, setPasskeyVerificationData] = useState<
        { passkeySessionID: string; url: string } | undefined
    >(undefined);
    const [sessionValidityCheck, setSessionValidityCheck] = useState<
        Promise<void> | undefined
    >(undefined);
    const [host, setHost] = useState<string | undefined>();

    const {
        secondFactorChoiceProps,
        userVerificationResultAfterResolvingSecondFactorChoice,
    } = useSecondFactorChoiceIfNeeded();

    const router = useRouter();

    useEffect(() => {
        if (Presentation) void customAPIHost().then(setHost);
    }, [Presentation]);

    const validateSession = useCallback(async () => {
        const showSessionExpiredDialog = () =>
            showMiniDialog(sessionExpiredDialogAttributes(logout));

        try {
            const session = await checkSessionValidity();
            switch (session.status) {
                case "invalid":
                    showSessionExpiredDialog();
                    break;
                case "valid":
                    break;
                case "validButPasswordChanged":
                    saveKeyAttributes(session.updatedKeyAttributes);
                    saveSRPAttributes(session.updatedSRPAttributes);
                    // Set a flag that causes new interactive key attributes to
                    // be generated.
                    saveIsFirstLogin();
                    // This should be rare; instead of updating all the
                    // in-memory state, just reload the page.
                    window.location.reload();
            }
        } catch (e) {
            // Ignore errors; a potentially transient issue must not log the
            // user out.
            log.warn("Ignoring error when determining session validity", e);
        }
    }, [logout, showMiniDialog]);

    const postVerification = useCallback(
        async (
            userEmail: string,
            masterKey: string,
            kek: string,
            keyAttributes: KeyAttributes,
        ) => {
            await saveMasterKeyInSessionAndSafeStore(masterKey);
            await decryptAndStoreTokenIfNeeded(keyAttributes, masterKey);
            try {
                let srpAttributes = savedSRPAttributes();
                if (!srpAttributes) {
                    srpAttributes = await getSRPAttributes(userEmail);
                    if (srpAttributes) {
                        saveSRPAttributes(srpAttributes);
                    } else {
                        await setupSRP(await generateSRPSetupAttributes(kek));
                        await getAndSaveSRPAttributes(userEmail);
                    }
                }
            } catch (e) {
                log.error("SRP migration failed", e);
            }
            void router.push(unstashRedirect() ?? appHomeRoute);
        },
        [router],
    );

    useEffect(() => {
        void (async () => {
            const user = savedPartialLocalUser();
            const userEmail = user?.email;
            if (!userEmail) {
                await router.replace("/");
                return;
            }

            await updateSessionFromElectronSafeStorageIfNeeded();
            if ((await masterKeyFromSession()) && (await savedAuthToken())) {
                await router.replace(appHomeRoute);
                return;
            }

            setUserEmail(userEmail);
            if (user.token) setSessionValidityCheck(validateSession());

            const kek = await unstashKeyEncryptionKeyFromSession();
            const keyAttributes = savedKeyAttributes();

            // Refreshing an existing tab, or the desktop app: the stashed KEK
            // decrypts the master key without asking for the password again.
            if (kek && keyAttributes) {
                const masterKey = await decryptBox(
                    {
                        encryptedData: keyAttributes.encryptedKey,
                        nonce: keyAttributes.keyDecryptionNonce,
                    },
                    kek,
                );
                await postVerification(
                    userEmail,
                    masterKey,
                    kek,
                    keyAttributes,
                );
                return;
            }

            // Reauthentication in a new tab on the web app. Use previously
            // generated interactive key attributes to verify password.
            if (keyAttributes) {
                if (!user.token && !user.encryptedToken) {
                    // TODO: Why? For now, add a dev mode circuit breaker.
                    if (isDevBuild) throw new Error("Unexpected case reached");
                    clearLocalStorage();
                    void router.replace("/");
                    return;
                }
                setKeyAttributes(keyAttributes);
                return;
            }

            // First login on a new client. `getKeyAttributes` from below will
            // be used during password verification to generate interactive key
            // attributes for subsequent reauthentications.
            const srpAttributes = savedSRPAttributes();
            if (srpAttributes) {
                setSRPAttributes(srpAttributes);
                return;
            }

            void router.replace("/");
        })();
    }, [router, validateSession, postVerification]);

    const getKeyAttributes: VerifyMasterPasswordFormProps["getKeyAttributes"] =
        useCallback(
            async (srpAttributes: SRPAttributes, kek: string) => {
                const {
                    id,
                    keyAttributes,
                    token,
                    encryptedToken,
                    twoFactorSessionID,
                    passkeySessionID,
                    accountsUrl,
                } =
                    await userVerificationResultAfterResolvingSecondFactorChoice(
                        await verifySRP(srpAttributes, kek),
                    );

                saveIsFirstLogin();

                if (passkeySessionID) {
                    await stashKeyEncryptionKeyInSessionStore(kek);
                    updateSavedLocalUser({ passkeySessionID });
                    stashRedirect("/");
                    const url = passkeyVerificationRedirectURL(
                        accountsUrl!,
                        passkeySessionID,
                    );
                    setPasskeyVerificationData({ passkeySessionID, url });
                    openPasskeyVerificationURL({ passkeySessionID, url });
                    return "redirecting-second-factor";
                } else if (twoFactorSessionID) {
                    await stashKeyEncryptionKeyInSessionStore(kek);
                    updateSavedLocalUser({
                        isTwoFactorEnabled: true,
                        twoFactorSessionID,
                    });
                    void router.push("/two-factor/verify");
                    return "redirecting-second-factor";
                } else {
                    if (token) await saveAuthToken(token);
                    updateSavedLocalUser({
                        id,
                        token,
                        encryptedToken,
                        isTwoFactorEnabled: undefined,
                        twoFactorSessionID: undefined,
                        passkeySessionID: undefined,
                    });
                    if (keyAttributes) saveKeyAttributes(keyAttributes);
                    return keyAttributes;
                }
            },
            [userVerificationResultAfterResolvingSecondFactorChoice, router],
        );

    const handleVerifyMasterPassword: VerifyMasterPasswordFormProps["onVerify"] =
        useCallback(
            (key, kek, keyAttributes, password) => {
                void (async () => {
                    // The page reloads if any attributes changed, so the KEK
                    // cannot have been generated from stale credentials. The
                    // await only makes sure the check is done before we let
                    // the user in.
                    if (sessionValidityCheck) await sessionValidityCheck;

                    const updatedKeyAttributes = savedIsFirstLogin()
                        ? await generateAndSaveInteractiveKeyAttributes(
                              password,
                              keyAttributes,
                              key,
                          )
                        : keyAttributes;

                    await postVerification(
                        userEmail,
                        key,
                        kek,
                        updatedKeyAttributes,
                    );
                })();
            },
            [postVerification, userEmail, sessionValidityCheck],
        );

    const handlePasskeyRetry = useCallback(() => {
        if (passkeyVerificationData) {
            openPasskeyVerificationURL(passkeyVerificationData);
        }
    }, [passkeyVerificationData]);

    const handleRecover = useCallback(() => {
        void router.push("/recover");
    }, [router]);

    if (!userEmail) {
        return <LoadingIndicator />;
    }

    if (!keyAttributes && !srpAttributes) {
        return <LoadingIndicator />;
    }

    if (passkeyVerificationData) {
        // Only the desktop app needs this UI; the web app is already
        // navigating to the passkey verification URL. Show a spinner on web
        // so that the VerifyingPasskey component does not flash before the
        // redirect completes.
        if (!globalThis.electron) {
            return <LoadingIndicator />;
        }

        return (
            <VerifyingPasskey
                email={userEmail}
                passkeySessionID={passkeyVerificationData.passkeySessionID}
                onRetry={handlePasskeyRetry}
                presentation={passkeyPresentation}
                {...{ logout, showMiniDialog }}
            />
        );
    }

    return (
        <>
            {Presentation ? (
                <Presentation
                    userEmail={userEmail}
                    host={host}
                    passwordForm={
                        <VerifyMasterPasswordForm
                            {...{
                                userEmail,
                                keyAttributes,
                                getKeyAttributes,
                                srpAttributes,
                            }}
                            submitButtonTitle={t("sign_in")}
                            onVerify={handleVerifyMasterPassword}
                            presentation={passwordPresentation}
                        />
                    }
                    onRecover={handleRecover}
                    onChangeEmail={logout}
                />
            ) : (
                <AccountsPageContents>
                    <PasswordHeader caption={userEmail} />
                    <VerifyMasterPasswordForm
                        {...{
                            userEmail,
                            keyAttributes,
                            getKeyAttributes,
                            srpAttributes,
                        }}
                        submitButtonTitle={t("sign_in")}
                        onVerify={handleVerifyMasterPassword}
                    />
                    <AccountsPageFooterWithHost>
                        <LinkButton onClick={handleRecover}>
                            {t("forgot_password")}
                        </LinkButton>
                        <LinkButton onClick={logout}>
                            {t("change_email")}
                        </LinkButton>
                    </AccountsPageFooterWithHost>
                </AccountsPageContents>
            )}
            <SecondFactorChoice
                {...secondFactorChoiceProps}
                presentation={secondFactorChoicePresentation}
            />
        </>
    );
};

export default Page;
