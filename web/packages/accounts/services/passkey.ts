import {
    saveKeyAttributes,
    updateSavedLocalUser,
} from "ente-accounts/services/accounts-db";
import {
    resetSavedLocalUserTokens,
    TwoFactorAuthorizationResponse,
} from "ente-accounts/services/user";
import { clientPackageName, isDesktop } from "ente-base/app";
import { httpOrHTTPSURL } from "ente-base/safe-navigation";
import { ensureAuthToken } from "ente-base/token";
import {
    passkeyManagementURL,
    checkPasskeyVerificationStatus as rustCheckPasskeyVerificationStatus,
} from "ente-prelogin-wasm";
import { withAccountsClient } from "./accounts-client";
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
    const url = httpOrHTTPSURL(accountsURL);
    url.pathname = `${url.pathname.replace(/\/$/, "")}/passkeys/verify`;
    url.search = params.toString();
    url.hash = "";
    return url.href;
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
    const destination = httpOrHTTPSURL(url).href;

    // The finish page ignores redirects whose session id does not match the
    // inflight value saved here.
    sessionStorage.setItem("inflightPasskeySessionID", passkeySessionID);

    if (globalThis.electron) window.open(destination);
    else window.location.href = destination;
};

export const openAccountsManagePasskeysPage = async (
    recoveryKeyMnemonic: () => Promise<string>,
) => {
    const token = await ensureAuthToken();
    const recoveryKey = await recoveryKeyMnemonic();
    const url = await withAccountsClient((client) =>
        passkeyManagementURL(client, token, recoveryKey),
    );
    window.open(httpOrHTTPSURL(url).href);
};

export const checkPasskeyVerificationStatus = async (
    sessionID: string,
): Promise<TwoFactorAuthorizationResponse | undefined> => {
    const response = await withAccountsClient((client) =>
        rustCheckPasskeyVerificationStatus(client, sessionID),
    );
    return response == null
        ? undefined
        : TwoFactorAuthorizationResponse.parse(response);
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
