import { Divider } from "@mui/material";
import {
    AccountsPageContents,
    AccountsPageFooter,
    AccountsPageTitle,
} from "ente-accounts/components/layouts/centered-paper";
import { deriveKeyInsufficientMemoryErrorMessage } from "ente-accounts/services/crypto";
import { appHomeRoute, stashRedirect } from "ente-accounts/services/redirect";
import { changePassword, type LocalUser } from "ente-accounts/services/user";
import { LinkButton } from "ente-base/components/LinkButton";
import { LoadingIndicator } from "ente-base/components/loaders";
import log from "ente-base/log";
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

    const isReset = router.query.op == "reset";

    useEffect(() => {
        const user = savedLocalUser();
        if (user) {
            setUser(user);
        } else {
            stashRedirect("/change-password");
            void router.replace("/");
        }
    }, [router]);

    return user ? (
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
    const router = useRouter();

    const handleSubmit: NewPasswordFormProps["onSubmit"] = useCallback(
        async (password, setPasswordsFieldError) =>
            changePassword(password)
                .then(() => void router.push(appHomeRoute))
                .catch((e: unknown) => {
                    log.error("Could not change password", e);
                    setPasswordsFieldError(
                        e instanceof Error &&
                            e.message == deriveKeyInsufficientMemoryErrorMessage
                            ? t("password_generation_failed")
                            : t("generic_error"),
                    );
                }),
        [router],
    );

    return (
        <AccountsPageContents>
            <AccountsPageTitle>{t("change_password")}</AccountsPageTitle>
            <NewPasswordForm
                userEmail={user.email}
                submitButtonTitle={t("change_password")}
                onSubmit={handleSubmit}
            />
            {!isReset && (
                <>
                    <Divider sx={{ mt: 1 }} />
                    <AccountsPageFooter>
                        <LinkButton onClick={router.back}>
                            {t("go_back")}
                        </LinkButton>
                    </AccountsPageFooter>
                </>
            )}
        </AccountsPageContents>
    );
};
