import {
    saveKeyAttributes,
    updateSavedLocalUser,
} from "ente-accounts/services/accounts-db";
import { encryptBox, generateKey } from "ente-accounts/services/crypto";
import {
    resetSavedLocalUserTokens,
    TwoFactorAuthorizationResponse,
} from "ente-accounts/services/user";
import { clientPackageName, isDesktop } from "ente-base/app";
import { namedError } from "ente-base/error";
import {
    authenticatedRequestHeaders,
    ensureOk,
    HTTPError,
    publicRequestHeaders,
} from "ente-base/http";
import { apiURL } from "ente-base/origins";
import { z } from "zod";
import { getUserRecoveryKey } from "./recovery-key";
import { unstashRedirect } from "./redirect";

export const passkeyVerificationRedirectURL = (
    accountsURL: string,
    passkeySessionID: string,
) => {
    // In the desktop app, window.location.origin is the custom app protocol
    // origin, which doubles as the deeplink back into the app.
    const redirect = `${window.location.origin}/passkeys/finish`;
    // The desktop app's own waiting screen already shows a recovery option, so
    // it does not ask the accounts app to show one.
    const recoverOption: Record<string, string> = isDesktop
        ? {}
        : { recover: `${window.location.origin}/passkeys/recover` };
    const params = new URLSearchParams({
        clientPackage: clientPackageName,
        passkeySessionID,
        redirect,
        ...recoverOption,
    });
    return `${accountsURL}/passkeys/verify?${params.toString()}`;
};

interface OpenPasskeyVerificationURLOptions {
    passkeySessionID: string;
    url: string;
}

// Passkeys do not work on the desktop app's custom protocol.
// Complete the flow in the system browser and return through a deep link.
export const openPasskeyVerificationURL = ({
    passkeySessionID,
    url,
}: OpenPasskeyVerificationURLOptions) => {
    // The finish page ignores redirects whose session id does not match the
    // inflight value saved here.
    sessionStorage.setItem("inflightPasskeySessionID", passkeySessionID);

    if (globalThis.electron) window.open(url);
    else window.location.href = url;
};

export const openAccountsManagePasskeysPage = async () => {
    const { isPasskeyRecoveryEnabled } = await getTwoFactorRecoveryStatus();
    if (!isPasskeyRecoveryEnabled) {
        const resetSecret = await generateKey();
        const { encryptedData, nonce } = await encryptBox(
            resetSecret,
            await getUserRecoveryKey(),
        );
        await configurePasskeyRecovery(resetSecret, encryptedData, nonce);
    }

    const { accountsToken: token, accountsUrl: accountsURL } =
        await getAccountsTokenAndURL();
    const params = new URLSearchParams({ token });

    window.open(`${accountsURL}/passkeys?${params.toString()}`);
};

const TwoFactorRecoveryStatus = z.object({
    isPasskeyRecoveryEnabled: z.boolean(),
});

export const getTwoFactorRecoveryStatus = async () => {
    const res = await fetch(await apiURL("/users/two-factor/recovery-status"), {
        headers: await authenticatedRequestHeaders(),
    });
    ensureOk(res);
    return TwoFactorRecoveryStatus.parse(await res.json());
};

const configurePasskeyRecovery = async (
    secret: string,
    userSecretCipher: string,
    userSecretNonce: string,
) =>
    ensureOk(
        await fetch(
            await apiURL("/users/two-factor/passkeys/configure-recovery"),
            {
                method: "POST",
                headers: await authenticatedRequestHeaders(),
                body: JSON.stringify({
                    secret,
                    userSecretCipher,
                    userSecretNonce,
                }),
            },
        ),
    );

const getAccountsTokenAndURL = async () => {
    const res = await fetch(await apiURL("/users/accounts-token"), {
        headers: await authenticatedRequestHeaders(),
    });
    ensureOk(res);
    return z
        .object({ accountsUrl: z.string(), accountsToken: z.string() })
        .parse(await res.json());
};

export const checkPasskeyVerificationStatus = async (
    sessionID: string,
): Promise<TwoFactorAuthorizationResponse | undefined> => {
    const res = await fetch(
        await apiURL("/users/two-factor/passkeys/get-token", { sessionID }),
        { headers: publicRequestHeaders() },
    );
    if (!res.ok) {
        if (res.status == 404 || res.status == 410) {
            throw namedError(
                "passkey_session_expired",
                "Passkey session has expired",
            );
        }
        // Remote uses 400 to indicate that verification is still pending.
        if (res.status == 400) return undefined;
        throw new HTTPError(res);
    }
    return TwoFactorAuthorizationResponse.parse(await res.json());
};

export const saveCredentialsAndNavigateTo = async (
    response: TwoFactorAuthorizationResponse,
) => {
    clearInflightPasskeySessionID();

    const { id, encryptedToken, keyAttributes } = response;

    await resetSavedLocalUserTokens(id, encryptedToken);
    updateSavedLocalUser({ passkeySessionID: undefined });
    saveKeyAttributes(keyAttributes);

    return unstashRedirect() ?? "/credentials";
};

export const clearInflightPasskeySessionID = () => {
    sessionStorage.removeItem("inflightPasskeySessionID");
};
