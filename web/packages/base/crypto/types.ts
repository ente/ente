import type { StateAddress } from "libsodium-wrappers-sumo";

export type SodiumStateAddress = StateAddress;

// Existing encrypted files depend on this chunk boundary.
export const streamEncryptionChunkSize = 4 * 1024 * 1024;
// libsodium secretstream adds this many bytes per encrypted chunk.
export const streamEncryptionChunkOverhead = 17;

export type BytesOrB64 = Uint8Array | string;

export interface EncryptedBox {
    encryptedData: BytesOrB64;
    nonce: BytesOrB64;
}

export interface EncryptedBoxB64 {
    encryptedData: string;
    nonce: string;
}

export interface EncryptedBlob {
    encryptedData: BytesOrB64;
    decryptionHeader: BytesOrB64;
}

export interface EncryptedBlobBytes {
    encryptedData: Uint8Array<ArrayBuffer>;
    decryptionHeader: Uint8Array<ArrayBuffer>;
}

export interface EncryptedBlobB64 {
    encryptedData: string;
    decryptionHeader: string;
}

export interface EncryptedFile {
    encryptedData: Uint8Array<ArrayBuffer>;
    decryptionHeader: string;
}

export interface InitChunkEncryptionResult {
    decryptionHeader: string;
    pushState: SodiumStateAddress;
}

export interface InitChunkDecryptionResult {
    pullState: SodiumStateAddress;
    decryptionChunkSize: number;
}

export interface KeyPair {
    publicKey: string;
    privateKey: string;
}

export interface DerivedKey {
    key: string;
    salt: string;
    opsLimit: number;
    memLimit: number;
}
