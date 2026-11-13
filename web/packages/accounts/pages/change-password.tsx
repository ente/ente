import { Divider } from "@mui/material";
import { useAuthPageConfig } from "ente-accounts/components/auth/AuthPageProvider";
import { SetPasswordForm } from "ente-accounts/components/auth/SetPasswordForm";
import {
    AccountsPageContents,
    AccountsPageFooter,
    AccountsPageTitle,
} from "ente-accounts/components/layouts/centered-paper";
import { changePassword } from "ente-accounts/services/password";
import { appHomeRoute, stashRedirect } from "ente-accounts/services/redirect";
import type { LocalUser } from "ente-accounts/services/user";
import { LinkButton } from "ente-base/components/LinkButton";
import { LoadingIndicator } from "ente-base/components/loaders";
import { isNamedError } from "ente-base/error";
import log from "ente-base/log";
import { decryptBox as preloginDecryptBox } from "ente-prelogin-wasm";
import { t } from "i18next";
import { useRouter } from "next/router";
import React, { useCallback, useEffect, useState } from "react";
import {
    NewPasswordForm,
    type NewPasswordFormProps,
} from "../components/NewPasswordForm";
import { savedLocalUser } from "../services/accounts-db";

const Page: React.FC = () => {
    const [user, setUser] = useState<LocalUser | undefined>(undefined);

    const router = useRouter();

    const isReset = router.isReady && router.query.op == "reset";

    useEffect(() => {
        const user = savedLocalUser();
        if (user) {
            setUser(user);
        } else {
            stashRedirect("/change-password");
            void router.replace("/");
        }
    }, [router]);

    return user && router.isReady ? (
        <PageContents {...{ user, isReset }} />
    ) : (
        <LoadingIndicator />
    );
};

export default Page;

interface PageContentsProps {
    user: LocalUser;
    isReset: boolean;
}

const PageContents: React.FC<PageContentsProps> = ({ user, isReset }) => {
    const { Shell, decryptBox: appDecryptBox } = useAuthPageConfig();
    const decryptBox = isReset ? preloginDecryptBox : appDecryptBox;
    const router = useRouter();

    const handleSubmit: NewPasswordFormProps["onSubmit"] = useCallback(
        async (password, setPasswordsFieldError) =>
            changePassword(password, decryptBox)
                .then(() => void router.push(appHomeRoute))
                .catch((e: unknown) => {
                    log.error("Could not change password", e);
                    setPasswordsFieldError(
                        isNamedError(e, "insufficient_memory")
                            ? t("password_generation_failed")
                            : t("generic_error"),
                    );
                }),
        [router, decryptBox],
    );

    if (isReset) {
        return (
            <Shell>
                <NewPasswordForm
                    userEmail={user.email}
                    submitButtonTitle={t("change_password")}
                    onSubmit={handleSubmit}
                    presentation={SetPasswordForm}
                />
            </Shell>
        );
    }

    return (
        <AccountsPageContents>
            <AccountsPageTitle>{t("change_password")}</AccountsPageTitle>
            <NewPasswordForm
                userEmail={user.email}
                submitButtonTitle={t("change_password")}
                onSubmit={handleSubmit}
            />
            <Divider sx={{ mt: 1 }} />
            <AccountsPageFooter>
                <LinkButton onClick={router.back}>{t("go_back")}</LinkButton>
            </AccountsPageFooter>
        </AccountsPageContents>
    );
};
