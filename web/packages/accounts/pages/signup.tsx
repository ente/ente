import { AccountsPageContents } from "ente-accounts/components/layouts/centered-paper";
import {
    SignUpContents,
    type SignUpPresentationProps,
} from "ente-accounts/components/SignUpContents";
import { savedPartialLocalUser } from "ente-accounts/services/accounts-db";
import { LoadingIndicator } from "ente-base/components/loaders";
import { customAPIHost } from "ente-base/origins";
import { useRouter } from "next/router";
import React, {
    useCallback,
    useEffect,
    useState,
    type ComponentType,
} from "react";

export interface SignUpPageProps {
    presentation?: ComponentType<SignUpPresentationProps>;
}

const Page: React.FC<SignUpPageProps> = ({ presentation }) => {
    const [loading, setLoading] = useState(true);
    const [host, setHost] = useState<string | undefined>(undefined);

    const router = useRouter();

    useEffect(() => {
        void customAPIHost().then(setHost);
        if (savedPartialLocalUser()?.email) void router.replace("/verify");
        setLoading(false);
    }, [router]);

    const onLogin = useCallback(() => void router.push("/login"), [router]);

    return loading ? (
        <LoadingIndicator />
    ) : presentation ? (
        <SignUpContents {...{ router, host, onLogin, presentation }} />
    ) : (
        <AccountsPageContents>
            <SignUpContents {...{ router, host, onLogin }} />
        </AccountsPageContents>
    );
};

export default Page;
