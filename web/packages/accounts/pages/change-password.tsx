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
import React, {
    useCallback,
    useEffect,
    useState,
    type ComponentType,
} from "react";
import {
    NewPasswordForm,
    type NewPasswordFormProps,
    type NewPasswordPresentationProps,
} from "../components/NewPasswordForm";
import { savedLocalUser } from "../services/accounts-db";

export interface ChangePasswordPageProps {
    resetPresentation?: ComponentType<NewPasswordPresentationProps>;
}

const Page: React.FC<ChangePasswordPageProps> = ({ resetPresentation }) => {
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

    return user && (!resetPresentation || router.isReady) ? (
        <PageContents {...{ user, isReset, resetPresentation }} />
    ) : (
        <LoadingIndicator />
    );
};

export default Page;

interface PageContentsProps {
    user: LocalUser;
    isReset: boolean;
    resetPresentation?: ComponentType<NewPasswordPresentationProps>;
}

const PageContents: React.FC<PageContentsProps> = ({
    user,
    isReset,
    resetPresentation: ResetPresentation,
}) => {
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

    if (isReset && ResetPresentation) {
        return (
            <NewPasswordForm
                userEmail={user.email}
                submitButtonTitle={t("change_password")}
                onSubmit={handleSubmit}
                presentation={ResetPresentation}
            />
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
