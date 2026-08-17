import {
    saveKeyAttributes,
    updateSavedLocalUser,
} from "ente-accounts/services/accounts-db";
import { fromB64URLSafeNoPadding } from "ente-accounts/services/crypto";
import { clearInflightPasskeySessionID } from "ente-accounts/services/passkey";
import { unstashRedirect } from "ente-accounts/services/redirect";
import {
    resetSavedLocalUserTokens,
    TwoFactorAuthorizationResponse,
} from "ente-accounts/services/user";
import { LoadingIndicator } from "ente-base/components/loaders";
import log from "ente-base/log";
import { nullToUndefined } from "ente-utils/transform";
import { useRouter } from "next/router";
import React, { useEffect } from "react";

// The passkey finish step must run in the app that invoked the passkey flow:
// it saves the obtained credentials to local storage, which is tied to the
// origin.
const Page: React.FC = () => {
    const router = useRouter();

    useEffect(() => {
        const searchParams = new URLSearchParams(window.location.search);
        const passkeySessionID = searchParams.get("passkeySessionID");
        const response = searchParams.get("response");
        if (!passkeySessionID || !response) return;

        void saveQueryCredentialsAndNavigateTo(passkeySessionID, response).then(
            (slug) => router.replace(slug),
        );
    }, [router]);

    return <LoadingIndicator />;
};

export default Page;

const saveQueryCredentialsAndNavigateTo = async (
    passkeySessionID: string,
    response: string,
) => {
    const inflightPasskeySessionID = nullToUndefined(
        sessionStorage.getItem("inflightPasskeySessionID"),
    );

    if (
        !inflightPasskeySessionID ||
        passkeySessionID != inflightPasskeySessionID
    ) {
        // This is a stale or unexpected redirect. Do not change any state;
        // just send the user back home.
        log.info(
            `Ignoring redirect for unexpected passkeySessionID ${passkeySessionID}`,
        );
        return "/";
    }

    clearInflightPasskeySessionID();

    const decodedResponse = TwoFactorAuthorizationResponse.parse(
        JSON.parse(
            new TextDecoder().decode(await fromB64URLSafeNoPadding(response)),
        ),
    );

    const { id, keyAttributes, encryptedToken } = decodedResponse;

    await resetSavedLocalUserTokens(id, encryptedToken);
    updateSavedLocalUser({ passkeySessionID: undefined });
    saveKeyAttributes(keyAttributes);

    return unstashRedirect() ?? "/credentials";
};
