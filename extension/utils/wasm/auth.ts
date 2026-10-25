// Thin wrapper around the auth WASM build produced by
// `npm run build:auth-wasm` in `web/`. See `./prelogin.ts` for why we import
// the generated `pkg` output directly.
//
// Mirrors `web/packages/wasm/auth/index.ts`.
import type {
    EncryptedBlob,
    EncryptedBox,
    OpenSessionInput,
    Session,
} from "../../../web/packages/wasm/auth/pkg/ente_auth_wasm.js";

export type { Session } from "../../../web/packages/wasm/auth/pkg/ente_auth_wasm.js";

const wasm = () =>
    import("../../../web/packages/wasm/auth/pkg/ente_auth_wasm.js");

export const openSession = async (input: OpenSessionInput): Promise<Session> =>
    (await wasm()).openSession(input);

export const encryptBoxWithRecoveryKey = async (
    session: Session,
    dataB64: string,
) => (await wasm()).authEncryptWithRecoveryKey(session, dataB64);

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
