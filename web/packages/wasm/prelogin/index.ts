import type { SrpSession } from "./pkg/ente_prelogin_wasm";

export type EncryptedBoxB64 = Awaited<ReturnType<typeof encryptBox>>;
export type KeyPair = Awaited<ReturnType<typeof generateKeyPair>>;
export type { GeneratedKek as DerivedKey } from "./pkg/ente_prelogin_wasm";

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

export const deriveSensitiveKey = async (password: string) =>
    (await wasm()).authGenerateSensitiveKek(password);

export const deriveInteractiveKey = async (password: string) =>
    (await wasm()).authGenerateInteractiveKek(password);

export const deriveSRPLoginKey = async (kekB64: string) =>
    (await wasm()).authDeriveSrpLoginKey(kekB64);

export const generateSRPSetup = async (kekB64: string, srpUserID: string) =>
    (await wasm()).authGenerateSrpSetup(kekB64, srpUserID);

export const recoveryKeyFromMnemonicOrHex = async (value: string) =>
    (await wasm()).authRecoveryKeyFromMnemonicOrHex(value);

export const recoveryKeyToMnemonic = async (recoveryKeyB64: string) =>
    (await wasm()).authRecoveryKeyToMnemonic(recoveryKeyB64);

export const createSRPSession = async (
    srpSaltB64: string,
    srpUserID: string,
    loginKeyB64: string,
): Promise<SrpSession> =>
    new (await wasm()).SrpSession(srpUserID, srpSaltB64, loginKeyB64);

export const generateKey = async () => (await wasm()).cryptoGenerateKey();

export const generateKeyPair = async () =>
    (await wasm()).cryptoGenerateKeyPair();

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

export const boxSealOpenBytes = async (
    encryptedData: string,
    keyPair: KeyPair,
): Promise<Uint8Array> =>
    (await wasm()).cryptoBoxSealOpen(
        encryptedData,
        keyPair.publicKey,
        keyPair.privateKey,
    );

const toB64String = (value: Uint8Array | string): string => {
    if (typeof value == "string") return value;
    let binary = "";
    for (const byte of value) binary += String.fromCharCode(byte);
    return btoa(binary);
};
