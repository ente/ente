// Thin wrappers over Ente's audited Rust crypto, compiled to WebAssembly.
// Mirrors `web/packages/accounts/services/crypto/index.ts` and
// `web/apps/auth/src/services/remote.ts`.
export {
    boxSealOpenBytes,
    createSRPSession,
    // Used for the master key / key attributes boxes during login.
    decryptBox,
    deriveInteractiveKey,
    deriveKey,
    deriveSRPLoginKey,
    deriveSensitiveKey,
    encryptBox,
    generateKey,
    generateKeyPair,
    generateSRPSetup,
    recoveryKeyFromMnemonicOrHex,
} from "../wasm/prelogin";

// Used for the authenticator key and per-item blobs, matching `remote.ts`.
export {
    decryptMetadataJSON,
    decryptBox as decryptSecretBox,
} from "../wasm/auth";

export type { EncryptedBoxB64, KeyPair } from "../wasm/prelogin";

const toB64 = (bytes: Uint8Array): string => {
    let binary = "";
    for (const byte of bytes) binary += String.fromCharCode(byte);
    return btoa(binary);
};

const fromB64 = (b64: string): Uint8Array => {
    const binary = atob(b64);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
    return bytes;
};

export const toB64URLSafe = (bytes: Uint8Array): string =>
    toB64(bytes).replace(/\+/g, "-").replace(/\//g, "_");

export const fromB64URLSafeNoPadding = (b64: string): Uint8Array => {
    let normalized = b64.replace(/-/g, "+").replace(/_/g, "/");
    while (normalized.length % 4) normalized += "=";
    return fromB64(normalized);
};
