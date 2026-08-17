import { Verify2FACodeForm } from "ente-accounts/components/Verify2FACodeForm";
import {
    savedPartialLocalUser,
    saveKeyAttributes,
    updateSavedLocalUser,
} from "ente-accounts/services/accounts-db";
import {
    resetSavedLocalUserTokens,
    verifyTwoFactor,
} from "ente-accounts/services/user";
import { LinkButton } from "ente-base/components/LinkButton";
import { useBaseContext } from "ente-base/context";
import { isHTTPErrorWithStatus } from "ente-base/http";
import { t } from "i18next";
import { useRouter } from "next/router";
import { useCallback, useEffect, useState } from "react";
import {
    AccountsPageContents,
    AccountsPageFooter,
    AccountsPageTitle,
} from "../../components/layouts/centered-paper";
import { unstashRedirect } from "../../services/redirect";

const Page: React.FC = () => {
    const { logout } = useBaseContext();

    const [twoFactorSessionID, setTwoFactorSessionID] = useState("");

    const router = useRouter();

    useEffect(() => {
        const user = savedPartialLocalUser();
        if (!user?.email || !user.twoFactorSessionID) {
            void router.replace("/");
        } else if (
            !user.isTwoFactorEnabled &&
            (user.encryptedToken || user.token)
        ) {
            void router.replace("/credentials");
        } else {
            setTwoFactorSessionID(user.twoFactorSessionID);
        }
    }, [router]);

    const handleSubmit = useCallback(
        async (otp: string) => {
            try {
                const { keyAttributes, encryptedToken, id } =
                    await verifyTwoFactor(otp, twoFactorSessionID);
                await resetSavedLocalUserTokens(id, encryptedToken);
                updateSavedLocalUser({ twoFactorSessionID: undefined });
                saveKeyAttributes(keyAttributes);
                await router.push(unstashRedirect() ?? "/credentials");
            } catch (e) {
                if (isHTTPErrorWithStatus(e, 404)) {
                    logout();
                } else {
                    throw e;
                }
            }
        },
        [logout, router, twoFactorSessionID],
    );

    return (
        <AccountsPageContents>
            <AccountsPageTitle>{t("two_factor")}</AccountsPageTitle>
            <Verify2FACodeForm
                onSubmit={handleSubmit}
                submitButtonText={t("verify")}
            />
            <AccountsPageFooter>
                <LinkButton onClick={() => router.push("/two-factor/recover")}>
                    {t("lost_2fa_device")}
                </LinkButton>
                <LinkButton onClick={logout}>{t("change_email")}</LinkButton>
            </AccountsPageFooter>
        </AccountsPageContents>
    );
};

export default Page;
