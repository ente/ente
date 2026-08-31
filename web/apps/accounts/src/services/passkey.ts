import { TwoFactorAuthorizationResponse } from "ente-accounts/services/user";
import { clientPackageName } from "ente-base/app";
import {
    fromB64URLSafeNoPadding,
    toB64URLSafeNoPadding,
} from "ente-base/crypto";
import { isDevBuild } from "ente-base/env";
import {
    ensureOk,
    HTTPError,
    isMuseumHTTPError,
    publicRequestHeaders,
} from "ente-base/http";
import { apiURL } from "ente-base/origins";
import { nullToUndefined } from "ente-utils/transform";
import { z } from "zod";

export const isWebAuthnSupported = () => !!navigator.credentials;

const accountsAuthenticatedRequestHeaders = (
    token: string,
): Record<string, string> => ({
    "X-Auth-Token": token,
    "X-Client-Package": clientPackageName,
});

const Passkey = z.object({
    id: z.string(),
    friendlyName: z.string(),
    createdAt: z.number(),
});

export type Passkey = z.infer<typeof Passkey>;

const GetPasskeysResponse = z.object({
    accountsUrl: z.string().optional(),
    passkeys: z.array(Passkey).nullish().transform(nullToUndefined),
});

export const getPasskeys = async (token: string) => {
    const res = await fetch(await apiURL("/passkeys"), {
        headers: accountsAuthenticatedRequestHeaders(token),
    });
    ensureOk(res);
    const { accountsUrl, passkeys } = GetPasskeysResponse.parse(
        await res.json(),
    );
    return { accountsUrl, passkeys: passkeys ?? [] };
};

export const renamePasskey = async (
    token: string,
    id: string,
    name: string,
) => {
    const url = await apiURL(`/passkeys/${id}`, { friendlyName: name });
    const res = await fetch(url, {
        method: "PATCH",
        headers: accountsAuthenticatedRequestHeaders(token),
    });
    ensureOk(res);
};

export const deletePasskey = async (token: string, id: string) => {
    const res = await fetch(await apiURL(`/passkeys/${id}`), {
        method: "DELETE",
        headers: accountsAuthenticatedRequestHeaders(token),
    });
    ensureOk(res);
};

export const registerPasskey = async (token: string, name: string) => {
    const { sessionID, options } = await beginPasskeyRegistration(token);

    const credential = (await navigator.credentials.create(options))!;

    await finishPasskeyRegistration({
        token,
        friendlyName: name,
        sessionID,
        credential,
    });
};

interface BeginPasskeyRegistrationResponse {
    sessionID: string;
    options: { publicKey: PublicKeyCredentialCreationOptions };
}

const beginPasskeyRegistration = async (token: string) => {
    const res = await fetch(await apiURL("/passkeys/registration/begin"), {
        method: "POST",
        headers: accountsAuthenticatedRequestHeaders(token),
    });
    ensureOk(res);

    const { sessionID, options } =
        (await res.json()) as BeginPasskeyRegistrationResponse;

    options.publicKey.challenge = await serverB64ToBinary(
        options.publicKey.challenge,
    );

    options.publicKey.user.id = await serverB64ToBinary(
        options.publicKey.user.id,
    );

    return { sessionID, options };
};

// Browser WebAuthn APIs use binary values. The API sends them as unpadded
// base64url strings, which the DOM types do not describe; hence the casts.

const serverB64ToBinary = async (b: BufferSource) => {
    const b64String = b as unknown as string;
    const bytes = await fromB64URLSafeNoPadding(b64String);
    return bytes as unknown as BufferSource;
};

const binaryToServerB64 = async (b: ArrayBuffer) => {
    const bytes = new Uint8Array(b);
    const b64String = await toB64URLSafeNoPadding(bytes);
    return b64String as unknown as BufferSource;
};

interface FinishPasskeyRegistrationOptions {
    token: string;
    sessionID: string;
    friendlyName: string;
    credential: Credential;
}

const finishPasskeyRegistration = async ({
    token,
    sessionID,
    friendlyName,
    credential,
}: FinishPasskeyRegistrationOptions) => {
    const attestationResponse = authenticatorAttestationResponse(credential);

    const attestationObject = await binaryToServerB64(
        attestationResponse.attestationObject,
    );
    const clientDataJSON = await binaryToServerB64(
        attestationResponse.clientDataJSON,
    );
    const transports = attestationResponse.getTransports();

    const url = await apiURL("/passkeys/registration/finish", {
        friendlyName,
        sessionID,
    });
    const res = await fetch(url, {
        method: "POST",
        headers: accountsAuthenticatedRequestHeaders(token),
        body: JSON.stringify({
            id: credential.id,
            // id is already the base64url form of rawId expected by the API.
            rawId: credential.id,
            type: credential.type,
            response: { attestationObject, clientDataJSON, transports },
        }),
    });
    ensureOk(res);
};

const authenticatorAttestationResponse = (credential: Credential) => {
    const pkCredential = credential as PublicKeyCredential;
    const attestationResponse =
        pkCredential.response as AuthenticatorAttestationResponse;
    return attestationResponse;
};

const isAllowedRedirectScheme = (url: URL) =>
    url.protocol === "http:" ||
    url.protocol === "https:" ||
    url.protocol === "ente:" ||
    url.protocol === "enteauth:" ||
    url.protocol === "entelocker:" ||
    url.protocol === "ensu:" ||
    url.protocol === "ente-cli:" ||
    // Tauri's internal protocol (used by EnsU desktop) is not an OS-level
    // deeplink scheme, but we may still get redirects to it when the accounts
    // flow runs inside the app's WebView.
    (url.protocol === "tauri:" && url.hostname === "localhost");

// Ente-hosted and local builds restrict redirect hosts.
// Self-hosted Accounts must accept its own hosts.
export const isWhitelistedRedirect = (redirectURL: URL) => {
    if (!isAllowedRedirectScheme(redirectURL)) return false;
    if (!shouldRestrictToWhitelistedRedirect()) return true;
    return (
        redirectURL.protocol === "ente:" ||
        redirectURL.protocol === "enteauth:" ||
        redirectURL.protocol === "entelocker:" ||
        redirectURL.protocol === "ensu:" ||
        redirectURL.protocol === "ente-cli:" ||
        (redirectURL.protocol === "tauri:" &&
            redirectURL.hostname === "localhost") ||
        _isWhitelistedRedirect(redirectURL)
    );
};

export const shouldRestrictToWhitelistedRedirect = () => {
    const hostname = new URL(window.location.origin).hostname;
    return (
        hostname.endsWith("localhost") ||
        hostname.endsWith(".ente.com") ||
        hostname.endsWith(".ente.io") ||
        hostname.endsWith(".ente.sh")
    );
};

const _isWhitelistedRedirect = (redirectURL: URL) =>
    (isDevBuild && redirectURL.hostname.endsWith("localhost")) ||
    redirectURL.host === "ente.space" ||
    redirectURL.host.endsWith(".ente.com") ||
    redirectURL.host.endsWith(".ente.io") ||
    redirectURL.host.endsWith(".ente.sh");

export const parseRedirectURLParam = (
    value: string | undefined,
): URL | undefined => {
    if (!value) return undefined;
    try {
        const url = new URL(value);
        return isWhitelistedRedirect(url) ? url : undefined;
    } catch {
        return undefined;
    }
};

export interface BeginPasskeyAuthenticationResponse {
    ceremonySessionID: string;
    options: { publicKey: PublicKeyCredentialRequestOptions };
}

export const beginPasskeyAuthentication = async (
    passkeySessionID: string,
): Promise<BeginPasskeyAuthenticationResponse> => {
    const url = await apiURL("/users/two-factor/passkeys/begin");
    const res = await fetch(url, {
        method: "POST",
        headers: publicRequestHeaders(),
        body: JSON.stringify({ sessionID: passkeySessionID }),
    });
    if (!res.ok) {
        const error = new HTTPError(res);
        if (await isMuseumHTTPError(error, 409, "SESSION_ALREADY_CLAIMED")) {
            error.name = "passkey_session_already_claimed";
        }
        throw error;
    }

    const { ceremonySessionID, options } =
        (await res.json()) as BeginPasskeyAuthenticationResponse;

    options.publicKey.challenge = await serverB64ToBinary(
        options.publicKey.challenge,
    );

    for (const credential of options.publicKey.allowCredentials ?? []) {
        credential.id = await serverB64ToBinary(credential.id);
    }

    return { ceremonySessionID, options };
};

export const signChallenge = async (
    publicKey: PublicKeyCredentialRequestOptions,
) => {
    // Browsers report incomplete transports, and other browsers may treat
    // those hints as restrictions. Send every transport as a workaround.
    for (const cred of publicKey.allowCredentials ?? []) {
        cred.transports = [
            ...(cred.transports ?? []),
            "usb",
            "nfc",
            "ble",
            "hybrid",
            "internal",
        ];
    }

    return nullToUndefined(await navigator.credentials.get({ publicKey }));
};

interface FinishPasskeyAuthenticationOptions {
    passkeySessionID: string;
    ceremonySessionID: string;
    clientPackage: string;
    credential: Credential;
}

export const finishPasskeyAuthentication = async ({
    passkeySessionID,
    ceremonySessionID,
    clientPackage,
    credential,
}: FinishPasskeyAuthenticationOptions) => {
    const response = authenticatorAssertionResponse(credential);

    const authenticatorData = await binaryToServerB64(
        response.authenticatorData,
    );
    const clientDataJSON = await binaryToServerB64(response.clientDataJSON);
    const signature = await binaryToServerB64(response.signature);
    const userHandle = response.userHandle
        ? await binaryToServerB64(response.userHandle)
        : null;

    const params = new URLSearchParams({
        sessionID: passkeySessionID,
        ceremonySessionID,
        clientPackage,
    });
    const url = await apiURL("/users/two-factor/passkeys/finish");
    const res = await fetch(`${url}?${params.toString()}`, {
        method: "POST",
        headers: {
            // Unlike the other requests, this is deliberately the client
            // package of the requesting app, not of the accounts app itself.
            "X-Client-Package": clientPackage,
        },
        body: JSON.stringify({
            id: credential.id,
            // id is already the base64url form of rawId expected by the API.
            rawId: credential.id,
            type: credential.type,
            response: {
                authenticatorData,
                clientDataJSON,
                signature,
                userHandle,
            },
        }),
    });
    ensureOk(res);

    return TwoFactorAuthorizationResponse.parse(await res.json());
};

const authenticatorAssertionResponse = (credential: Credential) => {
    const pkCredential = credential as PublicKeyCredential;
    const assertionResponse =
        pkCredential.response as AuthenticatorAssertionResponse;
    return assertionResponse;
};

export const passkeyAuthenticationSuccessRedirectURL = async (
    redirectURL: URL,
    passkeySessionID: string,
    twoFactorAuthorizationResponse: TwoFactorAuthorizationResponse,
) => {
    const encodedResponse = await toB64URLSafeNoPadding(
        new TextEncoder().encode(
            JSON.stringify(twoFactorAuthorizationResponse),
        ),
    );
    redirectURL.searchParams.set("passkeySessionID", passkeySessionID);
    redirectURL.searchParams.set("response", encodedResponse);
    return redirectURL;
};

export const redirectToPasskeyRecoverPage = (recoverURL: URL) => {
    window.location.href = recoverURL.href;
};
