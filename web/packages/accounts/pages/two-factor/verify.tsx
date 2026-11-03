import { useAuthPageConfig } from "ente-accounts/components/auth/AuthPageProvider";
import { TwoFactorForm } from "ente-accounts/components/auth/TwoFactorForm";
import {
    savedPartialLocalUser,
    saveKeyAttributes,
    updateSavedLocalUser,
} from "ente-accounts/services/accounts-db";
import {
    resetSavedLocalUserTokens,
    verifyTwoFactor,
} from "ente-accounts/services/user";
import { useBaseContext } from "ente-base/context";
import { isNamedError } from "ente-base/error";
import { useRouter } from "next/router";
import { useCallback, useEffect, useState } from "react";
import { unstashRedirect } from "../../services/redirect";

export interface TwoFactorVerifyPresentationProps {
    onSubmit: (otp: string) => Promise<void>;
    onRecover: () => void;
    onChangeEmail: () => void;
}

const Page: React.FC = () => {
    const { Shell } = useAuthPageConfig();
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
                if (isNamedError(e, "session_expired")) {
                    logout();
                } else {
                    throw e;
                }
            }
        },
        [logout, router, twoFactorSessionID],
    );

    const handleRecover = useCallback(
        () => void router.push("/two-factor/recover"),
        [router],
    );

    return (
        <Shell>
            <TwoFactorForm
                onSubmit={handleSubmit}
                onRecover={handleRecover}
                onChangeEmail={logout}
            />
        </Shell>
    );
};

export default Page;
