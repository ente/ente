import type {
    EncryptedBlob,
    EncryptedBox,
    OpenSessionInput,
    Session,
} from "./pkg/ente_auth_wasm";

export type { Session } from "./pkg/ente_auth_wasm";

const wasm = () => import("./pkg/ente_auth_wasm");

export const openSession = async (input: OpenSessionInput): Promise<Session> =>
    (await wasm()).openSession(input);

export const recoveryKeyMnemonic = async (session: Session) =>
    (await wasm()).authRecoveryKeyMnemonic(session);

export const decryptBox = async (box: EncryptedBox, keyB64: string) =>
    (await wasm()).cryptoDecryptBox(box.encryptedData, box.nonce, keyB64);

export const decryptMetadataJSON = async (
    blob: EncryptedBlob,
    keyB64: string,
): Promise<unknown> => {
    const plaintext = (await wasm()).cryptoDecryptBlobLegacy(
        blob.encryptedData,
        blob.decryptionHeader,
        keyB64,
    );
    return JSON.parse(new TextDecoder().decode(plaintext));
};

export const decryptMetadataJSONBytes = async (
    blob: { encryptedData: Uint8Array; decryptionHeader: Uint8Array },
    key: Uint8Array,
): Promise<unknown> => {
    const plaintext = (await wasm()).cryptoDecryptBlobLegacyBytes(
        blob.encryptedData,
        blob.decryptionHeader,
        key,
    );
    return JSON.parse(new TextDecoder().decode(plaintext));
};
