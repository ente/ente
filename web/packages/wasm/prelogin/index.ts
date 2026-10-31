import type {
    AccountsClient,
    AccountsClientConfig,
} from "./pkg/ente_prelogin_wasm";

export type EncryptedBoxB64 = Awaited<ReturnType<typeof encryptBox>>;
export type { AccountsClient } from "./pkg/ente_prelogin_wasm";

const wasm = () => import("./pkg/ente_prelogin_wasm");

type BytesOrB64 = Uint8Array | string;

interface EncryptedBox {
    encryptedData: BytesOrB64;
    nonce: BytesOrB64;
}

export const deriveKey = async (
    password: string,
    saltB64: string,
    opsLimit: number,
    memLimit: number,
) =>
    (await wasm()).authDeriveKek(password, saltB64, BigInt(memLimit), opsLimit);

export const generateSRPSetup = async (kekB64: string, srpUserID: string) =>
    (await wasm()).authGenerateSrpSetup(kekB64, srpUserID);

export const createAccountsClient = async (config: AccountsClientConfig) =>
    (await wasm()).createAccountsClient(config);

export const getSRPAttributes = async (
    client: AccountsClient,
    email: string,
): Promise<unknown> => (await wasm()).getSRPAttributes(client, email);

export const sendOTP = async (
    client: AccountsClient,
    email: string,
    purpose: string,
) => (await wasm()).sendOTP(client, email, purpose);

export const verifyEmail = async (
    client: AccountsClient,
    email: string,
    code: string,
    source?: string,
): Promise<unknown> => (await wasm()).verifyEmail(client, email, code, source);

export const verifySRP = async (
    client: AccountsClient,
    attributes: unknown,
    kek: string,
): Promise<unknown> => (await wasm()).verifySRP(client, attributes, kek);

export const verifyTwoFactor = async (
    client: AccountsClient,
    sessionID: string,
    code: string,
): Promise<unknown> => (await wasm()).verifyTwoFactor(client, sessionID, code);

export const checkPasskeyVerificationStatus = async (
    client: AccountsClient,
    sessionID: string,
): Promise<unknown> =>
    (await wasm()).checkPasskeyVerificationStatus(client, sessionID);

export const setKeyAttributes = async (
    client: AccountsClient,
    token: string,
    attributes: unknown,
) => (await wasm()).setKeyAttributes(client, token, attributes);

export const getSessionValidity = async (
    client: AccountsClient,
    token: string,
): Promise<unknown> => (await wasm()).getSessionValidity(client, token);

export const setupSRP = async (
    client: AccountsClient,
    token: string,
    setup: unknown,
) => (await wasm()).setupSRP(client, token, setup);

export const completeSignup = async (
    client: AccountsClient,
    email: string,
    token: string,
    attributes: unknown,
    setup: unknown,
): Promise<unknown> =>
    (await wasm()).completeSignup(client, email, token, attributes, setup);

export const unlockAccount = async (
    response: unknown,
    kek: string,
): Promise<unknown> => (await wasm()).unlockAccount(response, kek);

export const unlockAccountWithMasterKey = async (
    response: unknown,
    masterKey: string,
): Promise<unknown> =>
    (await wasm()).unlockAccountWithMasterKey(response, masterKey);

export const generateSignupKeys = async (password: string, srpUserID: string) =>
    (await wasm()).authGenerateSignupKeys(password, srpUserID);

export const generateInteractiveKeyAttributes = async (
    password: string,
    attributes: unknown,
    masterKey: string,
): Promise<unknown> =>
    (await wasm()).authGenerateInteractiveKeyAttributes(
        password,
        attributes,
        masterKey,
    );

export const getTwoFactorRecovery = async (
    client: AccountsClient,
    twoFactorType: "totp" | "passkey",
    sessionID: string,
): Promise<unknown> =>
    (await wasm()).getTwoFactorRecovery(client, twoFactorType, sessionID);

export const recoverTwoFactor = async (
    client: AccountsClient,
    twoFactorType: "totp" | "passkey",
    sessionID: string,
    recoveryResponse: {
        encryptedSecret: string;
        secretDecryptionNonce: string;
    },
    recoveryKey: string,
): Promise<unknown> =>
    (await wasm()).recoverTwoFactor(
        client,
        twoFactorType,
        sessionID,
        recoveryResponse,
        recoveryKey,
    );

export const recoveryKeyToMnemonic = async (recoveryKeyB64: string) =>
    (await wasm()).authRecoveryKeyToMnemonic(recoveryKeyB64);

export const generateKey = async () => (await wasm()).cryptoGenerateKey();

export const encryptBox = async (dataB64: string, keyB64: string) =>
    (await wasm()).cryptoEncryptBox(dataB64, keyB64);

export const decryptBox = async (
    box: EncryptedBox,
    key: Uint8Array | string,
): Promise<string> =>
    (await wasm()).cryptoDecryptBox(
        toB64String(box.encryptedData),
        toB64String(box.nonce),
        toB64String(key),
    );

const toB64String = (value: Uint8Array | string): string => {
    if (typeof value == "string") return value;
    let binary = "";
    for (const byte of value) binary += String.fromCharCode(byte);
    return btoa(binary);
};

export const recoverAccount = async (
    response: unknown,
    recoveryKey: string,
): Promise<unknown> => (await wasm()).recoverAccount(response, recoveryKey);

export const changePassword = async (
    client: AccountsClient,
    token: string,
    password: string,
    masterKey: string,
    keyAttributes: unknown,
): Promise<unknown> =>
    (await wasm()).changePassword(
        client,
        token,
        password,
        masterKey,
        keyAttributes,
    );

export const setupTwoFactor = async (
    client: AccountsClient,
    token: string,
): Promise<unknown> => (await wasm()).setupTwoFactor(client, token);

export const enableTwoFactor = async (
    client: AccountsClient,
    token: string,
    secret: string,
    recoveryKey: string,
    code: string,
) => (await wasm()).enableTwoFactor(client, token, secret, recoveryKey, code);

export const passkeyManagementURL = async (
    client: AccountsClient,
    token: string,
    recoveryKey: string,
) => (await wasm()).passkeyManagementURL(client, token, recoveryKey);

export const checkSessionValidity = async (
    client: AccountsClient,
    token: string,
    email: string,
    localSRPAttributes: unknown,
): Promise<unknown> =>
    (await wasm()).checkSessionValidity(
        client,
        token,
        email,
        localSRPAttributes,
    );
