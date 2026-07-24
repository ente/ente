import { TwoFactorAuthorizationResponse } from "ente-accounts/services/user";
import { clientPackageName } from "ente-base/app";
import {
    fromB64URLSafeNoPadding,
    toB64URLSafeNoPadding,
} from "ente-base/crypto";
import { isDevBuild } from "ente-base/env";
import { ensureOk, HTTPError, publicRequestHeaders } from "ente-base/http";
import { apiURL } from "ente-base/origins";
import { nullToUndefined } from "ente-utils/transform";
import { z } from "zod";

/** Return true if the user's browser supports WebAuthn (Passkeys). */
export const isWebAuthnSupported = () => !!navigator.credentials;

/**
 * Variant of {@link authenticatedRequestHeaders} but for authenticated requests
 * made by the accounts app.
 *
 * @param token The accounts specific auth token to use for making API requests.
 */
const accountsAuthenticatedRequestHeaders = (
    token: string,
): Record<string, string> => ({
    "X-Auth-Token": token,
    "X-Client-Package": clientPackageName,
});

const Passkey = z.object({
    /** A unique ID for the passkey */
    id: z.string(),
    /**
     * An arbitrary name associated by the user with the passkey (a.k.a
     * its "friendly name").
     */
    friendlyName: z.string(),
    /**
     * Epoch microseconds when this passkey was created.
     */
    createdAt: z.number(),
});

export type Passkey = z.infer<typeof Passkey>;

const GetPasskeysResponse = z.object({
    accountsUrl: z.string().optional(),
    passkeys: z.array(Passkey).nullish().transform(nullToUndefined),
});

/**
 * Fetch the existing passkeys for the user.
 *
 * @param token The accounts specific auth token to use for making API requests.
 *
 * @returns An array of {@link Passkey}s. The array will be empty if the user
 * has no passkeys.
 */
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

/**
 * Rename one of the user's existing passkey with the given {@link id}.
 *
 * @param token The accounts specific auth token to use for making API requests.
 *
 * @param id The `id` of the existing passkey to rename.
 *
 * @param name The new name (a.k.a. "friendly name").
 */
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

/**
 * Delete one of the user's existing passkeys.
 *
 * @param token The accounts specific auth token to use for making API requests.
 *
 * @param id The `id` of the existing passkey to delete.
 */
export const deletePasskey = async (token: string, id: string) => {
    const res = await fetch(await apiURL(`/passkeys/${id}`), {
        method: "DELETE",
        headers: accountsAuthenticatedRequestHeaders(token),
    });
    ensureOk(res);
};

/**
 * Add a new passkey as the second factor to the user's account.
 *
 * @param token The accounts specific auth token to use for making API requests.
 *
 * @param name An arbitrary name that the user wishes to label this passkey with
 * (a.k.a. "friendly name").
 */
export const registerPasskey = async (token: string, name: string) => {
    // Get options (and sessionID) from the backend.
    const { sessionID, options } = await beginPasskeyRegistration(token);

    // Ask the browser to new (public key) credentials using these options.
    const credential = (await navigator.credentials.create(options))!;

    // Finish by letting the backend know about these credentials so that it can
    // save the public key for future authentication.
    await finishPasskeyRegistration({
        token,
        friendlyName: name,
        sessionID,
        credential,
    });
};

interface BeginPasskeyRegistrationResponse {
    /**
     * An identifier for this registration ceremony / session.
     *
     * This sessionID is subsequently passed to the API when finish credential
     * creation to tie things together.
     */
    sessionID: string;
    /**
     * Options that should be passed to `navigator.credential.create` when
     * creating the new {@link Credential}.
     */
    options: { publicKey: PublicKeyCredentialCreationOptions };
}

const beginPasskeyRegistration = async (token: string) => {
    const res = await fetch(await apiURL("/passkeys/registration/begin"), {
        method: "POST",
        headers: accountsAuthenticatedRequestHeaders(token),
    });
    ensureOk(res);

    // [Note: Converting binary data in WebAuthn API payloads]
    //
    // The server returns a JSON containing a "sessionID" (to tie together the
    // beginning and the end of the registration), and "options" that we should
    // pass on to the browser when asking it to create credentials.
    //
    // However, some massaging needs to be done first. On the backend, we use
    // the [go-webauthn](https://github.com/go-webauthn/webauthn) library to
    // begin the registration ceremony, and we verbatim credential creation
    // options that the library returns to us. These are meant to plug directly
    // into `CredentialCreationOptions` that `navigator.credential.create`
    // expects. Specifically, since we're creating a public key credential, the
    // `publicKey` attribute of the returned options will be in the shape of the
    // `PublicKeyCredentialCreationOptions` expected by the browser). Except,
    // binary data.
    //
    // Binary data in the returned `PublicKeyCredentialCreationOptions` are
    // serialized as a "URLEncodedBase64", which is a URL-encoded base64 string
    // without any padding. The library is following the WebAuthn recommendation
    // when it does this:
    //
    // > The term "Base64url Encoding refers" to the base64 encoding using the
    // > URL- and filename-safe character set defined in Section 5 of RFC4648,
    // > which all trailing '=' characters omitted (as permitted by Section 3.2)
    // >
    // > https://www.w3.org/TR/webauthn-3/#base64url-encoding
    //
    // However, the browser expects binary data as an "ArrayBuffer, TypedArray
    // or DataView".
    // https://developer.mozilla.org/en-US/docs/Web/API/PublicKeyCredentialCreationOptions
    //
    // So we do the conversion here.
    //
    // 1. To avoid inventing an intermediary type and the boilerplate that'd
    //    come with it, we do a force typecast the options in the response to
    //    one that has `PublicKeyCredentialCreationOptions`.
    //
    // 2. Convert the two binary data fields that are expected to be in the
    //    response from URLEncodedBase64 strings to Uint8Arrays. There is a
    //    third possibility, excludedCredentials[].id, but that we don't
    //    currently use.
    //
    // The web.dev guide calls this out too:
    //
    // > ArrayBuffer values transferred from the server such as `challenge`,
    // > `user.id` and credential `id` for `excludeCredentials` need to be
    // > encoded on transmission. Don't forget to decode them on the frontend
    // > before passing to the WebAuthn API call. We recommend using Base64URL
    // > encode.
    // >
    // > https://web.dev/articles/passkey-registration
    //
    // So that's that. But to further complicate things, the libdom.ts typings
    // included with the current TypeScript version (5.4) indicate these binary
    // types as a:
    //
    //     type BufferSource = ArrayBufferView | ArrayBuffer
    //
    // However MDN documentation states that they can be TypedArrays (e.g.
    // Uint8Arrays), and using Uint8Arrays works in practice too. So another
    // force cast is needed.
    //
    // ----
    //
    // Finally, the same process needs to happen, in reverse, when we're sending
    // the browser's response to credential creation to our backend for storing
    // that credential (for future authentication). Binary fields need to be
    // converted to URL-safe B64 before transmission.

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

/**
 * This is the function that does the dirty work for the binary conversion,
 * including the unfortunate typecasts.
 *
 * See: [Note: Converting binary data in WebAuthn API payloads]
 */
const serverB64ToBinary = async (b: BufferSource) => {
    // This is actually a URL-safe B64 string without trailing padding.
    const b64String = b as unknown as string;
    // Convert it to a Uint8Array by doing the appropriate B64 decoding.
    const bytes = await fromB64URLSafeNoPadding(b64String);
    // Cast again to satisfy the incomplete BufferSource type.
    return bytes as unknown as BufferSource;
};

/**
 * This is the sibling of {@link serverB64ToBinary} that does the conversions in
 * the other direction.
 *
 * See: [Note: Converting binary data in WebAuthn API payloads]
 */
const binaryToServerB64 = async (b: ArrayBuffer) => {
    // Convert it to a Uint8Array
    const bytes = new Uint8Array(b);
    // Convert to a URL-safe B64 string without any trailing padding.
    const b64String = await toB64URLSafeNoPadding(bytes);
    // Lie about the types to make the compiler happy.
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
            // This is meant to be the ArrayBuffer version of the (base64
            // encoded) `id`, but since we then would need to base64 encode it
            // anyways for transmission, we can just reuse the same string.
            rawId: credential.id,
            type: credential.type,
            response: { attestationObject, clientDataJSON, transports },
        }),
    });
    ensureOk(res);
};

/**
 * A function to hide the type casts necessary to extract an
 * {@link AuthenticatorAttestationResponse} from the {@link Credential} we
 * obtain during a new passkey registration.
 */
const authenticatorAttestationResponse = (credential: Credential) => {
    // We passed `options: { publicKey }` to `navigator.credentials.create`, and
    // so we will get back an `PublicKeyCredential`:
    // https://developer.mozilla.org/en-US/docs/Web/API/PublicKeyCredentialCreationOptions#creating_a_public_key_credential
    //
    // However, the return type of `create` is the base `Credential`, so we need
    // to cast.
    const pkCredential = credential as PublicKeyCredential;

    // Further, since this was a `create` and not a `get`, the
    // PublicKeyCredential.response will be an
    // `AuthenticatorAttestationResponse` (See same MDN reference).
    //
    // We need to cast again.
    const attestationResponse =
        pkCredential.response as AuthenticatorAttestationResponse;

    return attestationResponse;
};

/**
 * Return `true` if the given {@link redirectURL} (obtained from the redirect
 * query parameter passed around during the passkey verification flow) is one of
 * the whitelisted URLs that we allow redirecting to on success.
 *
 * This check is likely not necessary but we've only kept it just to be on the
 * safer side. However, this gets in the way of people who are self hosting
 * Ente. So only do this check if we're running on our production servers (or
 * localhost).
 */
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

export const isWhitelistedRedirect = (redirectURL: URL) => {
    if (!isAllowedRedirectScheme(redirectURL)) return false;
    if (!shouldRestrictToWhitelistedRedirect()) return true;
    // In production/local, enforce host allowlist only for http(s)
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
    // host includes port, hostname is sans port
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
    /**
     * An identifier for this authentication ceremony / session.
     *
     * This `ceremonySessionID` is subsequently passed to the API when finish
     * credential creation to tie things together.
     */
    ceremonySessionID: string;
    /**
     * Options that should be passed to `navigator.credential.get` to obtain the
     * attested {@link Credential}.
     */
    options: { publicKey: PublicKeyCredentialRequestOptions };
}

/**
 * The passkey session which we are trying to start an authentication ceremony
 * for has already finished elsewhere.
 */
export const passkeySessionAlreadyClaimedErrorMessage =
    "Passkey session already claimed";

/**
 * Create a authentication ceremony session and return a challenge and a list of
 * public key credentials that can be used to attest that challenge.
 *
 * [Note: WebAuthn authentication flow]
 *
 * This is step 1 of passkey authentication flow as described in
 * https://developer.mozilla.org/en-US/docs/Web/API/Web_Authentication_API#authenticating_a_user
 *
 * @param passkeySessionID A session created by the requesting app that can be
 * used to initiate a passkey authentication ceremony on the accounts app.
 *
 * @throws In addition to arbitrary errors, it throws errors with the message
 * {@link passkeySessionAlreadyClaimedErrorMessage}.
 */
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
        if (res.status == 409)
            throw new Error(passkeySessionAlreadyClaimedErrorMessage);
        throw new HTTPError(res);
    }

    // See: [Note: Converting binary data in WebAuthn API payloads]

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

/**
 * Authenticate the user by asking them to use a passkey that the they had
 * previously created for the current domain to sign a challenge.
 *
 * This function implements steps 2 and 3 of the passkey authentication flow.
 * See [Note: WebAuthn authentication flow].
 *
 * @param publicKey A challenge and a list of public key credentials
 * ("passkeys") that can be used to attest that challenge.
 *
 * @returns A {@link PublicKeyCredential} that contains the signed
 * {@link AuthenticatorAssertionResponse}. Note that the type does not reflect
 * this specialization, and the result is a base {@link Credential}.
 */
export const signChallenge = async (
    publicKey: PublicKeyCredentialRequestOptions,
) => {
    // Hint all transports to make security keys like Yubikey work across
    // varying registration/verification scenarios.
    //
    // During verification, we need to pass a `transport` property.
    //
    // > The `transports` property is hint of the methods that the client could
    // > use to communicate with the relevant authenticator of the public key
    // > credential to retrieve. Possible values are ["ble", "hybrid",
    // > "internal", "nfc", "usb"].
    // >
    // > MDN
    //
    // When we register a passkey, we save the transport alongwith the
    // credential. During authentication, we pass that transport back to the
    // browser. This is the approach recommended by the spec:
    //
    // > When registering a new credential, the Relying Party SHOULD store the
    // > value returned from getTransports(). When creating a
    // > PublicKeyCredentialDescriptor for that credential, the Relying Party
    // > SHOULD retrieve that stored value and set it as the value of the
    // > transports member.
    // >
    // > https://www.w3.org/TR/webauthn-3/#dom-publickeycredentialdescriptor-transports
    //
    // However, following this recommendation break things currently (2024) in
    // various ways. For example, if a user registers a Yubikey NFC security key
    // on Firefox on their laptop, then Firefox returns ["usb"]. This is
    // incorrect, it should be ["usb", "nfc"] (which is what Chrome does, since
    // the hardware itself supports both USB and NFC transports).
    //
    // Later, if the user tries to verifying with their security key on their
    // iPhone Safari via NFC, the browser doesn't recognize it (which seems
    // incorrect too, the transport is meant to be a "hint" not a binding).
    //
    // > Note that these hints represent the WebAuthn Relying Party's best
    // > belief as to how an authenticator may be reached.
    // >
    // > https://www.w3.org/TR/webauthn-3/#dom-publickeycredentialdescriptor-transports
    //
    // As a workaround, we override transports with known possible values.

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
    /**
     * The package name of the client on whose behalf we're authenticating with
     * the user's passkey.
     *
     * This is used by the backend to generate an appropriately scoped auth
     * token for used by (and only by) the authenticating app.
     */
    clientPackage: string;
    credential: Credential;
}

/**
 * Finish the authentication by providing the signed assertion to the backend.
 *
 * This function implements steps 4 and 5 of the passkey authentication flow.
 * See [Note: WebAuthn authentication flow].
 *
 * @returns The result of successful authentication, a
 * {@link TwoFactorAuthorizationResponse}.
 */
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
            // Note: Unlike the other requests, this is the clientPackage of the
            // _requesting_ app, not the accounts app.
            "X-Client-Package": clientPackage,
        },
        body: JSON.stringify({
            id: credential.id,
            // This is meant to be the ArrayBuffer version of the (base64
            // encoded) `id`, but since we then would need to base64 encode it
            // anyways for transmission, we can just reuse the same string.
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

/**
 * A function to hide the type casts necessary to extract a
 * {@link AuthenticatorAssertionResponse} from the {@link Credential} we obtain
 * during a passkey attestation.
 */
const authenticatorAssertionResponse = (credential: Credential) => {
    // We passed `options: { publicKey }` to `navigator.credentials.get`, and so
    // we will get back an `PublicKeyCredential`:
    // https://developer.mozilla.org/en-US/docs/Web/API/CredentialsContainer/get#web_authentication_api
    //
    // However, the return type of `get` is the base `Credential`, so we need to
    // cast.
    const pkCredential = credential as PublicKeyCredential;

    // Further, since this was a `get` and not a `create`, the
    // PublicKeyCredential.response will be an `AuthenticatorAssertionResponse`
    // (See same MDN reference).
    //
    // We need to cast again.
    const assertionResponse =
        pkCredential.response as AuthenticatorAssertionResponse;

    return assertionResponse;
};

/**
 * Create a redirection URL to get back to the calling app that initiated the
 * passkey authentication flow with the result of the authentication.
 *
 * @param redirectURL The base URL to redirect to. Provided by the calling app
 * that initiated the passkey authentication.
 *
 * @param passkeySessionID The passkeySessionID that was provided by the calling
 * app that initiated the passkey authentication. It is returned back in the
 * response so that the calling app has a way to ensure that this is indeed a
 * redirect for the session that they initiated and are waiting for.
 *
 * @param twoFactorAuthorizationResponse The result of
 * {@link finishPasskeyAuthentication} returned by the backend.
 */
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

/**
 * Redirect back to the app that initiated the passkey authentication,
 * navigating the user to a place where they can reset their second factor using
 * their recovery key (e.g. if they have lost access to their passkey).
 *
 * The same considerations mentioned in [Note: Finish passkey flow in the
 * requesting app] apply to recovery too, which is why we need to redirect back
 * to the app on whose behalf we're authenticating.
 *
 * @param recoverURL The recovery URL provided as a query parameter by the app
 * that called us.
 */
export const redirectToPasskeyRecoverPage = (recoverURL: URL) => {
    window.location.href = recoverURL.href;
};
