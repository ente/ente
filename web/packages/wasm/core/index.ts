import type { SrpSession } from "./pkg/ente_core_wasm";

export type { SrpSession };

const wasm = () => import("./pkg/ente_core_wasm");

type BytesOrB64 = Uint8Array | string;

export interface DerivedKey {
    key: string;
    salt: string;
    opsLimit: number;
    memLimit: number;
}

export interface EncryptedBlob {
    encryptedData: BytesOrB64;
    decryptionHeader: BytesOrB64;
}

export interface EncryptedBlobB64 {
    encryptedData: string;
    decryptionHeader: string;
}

export interface EncryptedBox {
    encryptedData: BytesOrB64;
    nonce: BytesOrB64;
}

export interface EncryptedBoxB64 {
    encryptedData: string;
    nonce: string;
}

export interface KeyPair {
    publicKey: string;
    privateKey: string;
}

export interface SRPSetupAttributes {
    srpSalt: string;
    srpVerifier: string;
    loginSubKey: string;
}

export const deriveKey = async (
    password: string,
    saltB64: string,
    opsLimit: number,
    memLimit: number,
) => (await wasm()).auth_derive_kek(password, saltB64, memLimit, opsLimit);

export const deriveSensitiveKey = async (
    password: string,
): Promise<DerivedKey> =>
    plainValue(
        (await wasm()).auth_generate_sensitive_kek(password),
        derivedKeyValue,
    );

export const deriveInteractiveKey = async (
    password: string,
): Promise<DerivedKey> =>
    plainValue(
        (await wasm()).auth_generate_interactive_kek(password),
        derivedKeyValue,
    );

export const generateSRPSetup = async (
    kekB64: string,
    srpUserID: string,
): Promise<SRPSetupAttributes> =>
    plainValue(
        (await wasm()).auth_generate_srp_setup(kekB64, srpUserID),
        (setup) => ({
            srpSalt: setup.srp_salt,
            srpVerifier: setup.srp_verifier,
            loginSubKey: setup.login_sub_key,
        }),
    );

export const recoveryKeyFromMnemonicOrHex = async (value: string) =>
    (await wasm()).auth_recovery_key_from_mnemonic_or_hex(value);

export const recoveryKeyToMnemonic = async (recoveryKeyB64: string) =>
    (await wasm()).auth_recovery_key_to_mnemonic(recoveryKeyB64);

export const createSRPSession = async (
    srpSaltB64: string,
    srpUserID: string,
    loginKeyB64: string,
): Promise<SrpSession> =>
    new (await wasm()).SrpSession(srpUserID, srpSaltB64, loginKeyB64);

export const generateKey = async () => (await wasm()).crypto_generate_key();

export const generateKeyPair = async (): Promise<KeyPair> =>
    plainValue((await wasm()).crypto_generate_keypair(), (keyPair) => ({
        publicKey: keyPair.public_key,
        privateKey: keyPair.secret_key,
    }));

export const encryptBox = async (
    dataB64: string,
    keyB64: string,
): Promise<EncryptedBoxB64> =>
    plainValue((await wasm()).crypto_encrypt_box(dataB64, keyB64), (box) => ({
        encryptedData: box.encrypted_data,
        nonce: box.nonce,
    }));

export const decryptBox = async (
    box: EncryptedBox,
    key: Uint8Array | string,
): Promise<string> =>
    (await wasm()).crypto_decrypt_box(
        toB64String(box.encryptedData),
        toB64String(box.nonce),
        toB64String(key),
    );

export const decryptBoxBytes = async (
    box: EncryptedBox,
    key: Uint8Array | string,
): Promise<Uint8Array<ArrayBuffer>> =>
    fromB64String(await decryptBox(box, key));

export const encryptBlob = async (
    dataB64: string,
    keyB64: string,
): Promise<EncryptedBlobB64> =>
    plainValue((await wasm()).crypto_encrypt_blob(dataB64, keyB64), (blob) => ({
        encryptedData: blob.encrypted_data,
        decryptionHeader: blob.decryption_header,
    }));

export const decryptMetadataJSON = async (
    blob: EncryptedBlob,
    key: Uint8Array | string,
): Promise<unknown> => {
    const wasmModule = await wasm();
    const encryptedData = toB64String(blob.encryptedData);
    const decryptionHeader = toB64String(blob.decryptionHeader);
    const keyB64 = toB64String(key);
    let plaintextB64: string;
    try {
        plaintextB64 = wasmModule.crypto_decrypt_blob(
            encryptedData,
            decryptionHeader,
            keyB64,
        );
    } catch (error) {
        if (!(error instanceof Error && error.name == "stream_truncated")) {
            throw error;
        }
        plaintextB64 = wasmModule.crypto_decrypt_blob_legacy(
            encryptedData,
            decryptionHeader,
            keyB64,
        );
    }
    return JSON.parse(new TextDecoder().decode(fromB64String(plaintextB64)));
};

export const boxSeal = async (
    dataB64: string,
    publicKeyB64: string,
): Promise<string> => (await wasm()).crypto_box_seal(dataB64, publicKeyB64);

export const boxSealOpen = async (
    encryptedData: string,
    keyPair: KeyPair,
): Promise<string> =>
    (await wasm()).crypto_box_seal_open(
        encryptedData,
        keyPair.publicKey,
        keyPair.privateKey,
    );

export const boxSealOpenBytes = async (
    encryptedData: string,
    keyPair: KeyPair,
): Promise<Uint8Array<ArrayBuffer>> =>
    fromB64String(await boxSealOpen(encryptedData, keyPair));

export const deriveSubKeyBytes = async (
    keyB64: string,
    subKeyLength: number,
    subKeyID: number,
    context: string,
): Promise<Uint8Array<ArrayBuffer>> =>
    fromB64String(
        (await wasm()).crypto_derive_subkey(
            keyB64,
            subKeyLength,
            BigInt(subKeyID),
            context,
        ),
    );

export const md5Base64 = async (data: Uint8Array) =>
    (await wasm()).crypto_md5_base64(data);

export interface StreamEncryptorHandle {
    key: string;
    decryptionHeader: string;
    encryptChunk: (data: Uint8Array, isFinal: boolean) => Promise<Uint8Array>;
    free: () => void;
}

export const createStreamEncryptor =
    async (): Promise<StreamEncryptorHandle> => {
        const encryptor = new (await wasm()).CryptoStreamEncryptor();
        return {
            key: encryptor.key,
            decryptionHeader: encryptor.decryption_header,
            encryptChunk: (data, isFinal) =>
                Promise.resolve(encryptor.encrypt_chunk(data, isFinal)),
            free: () => encryptor.free(),
        };
    };

export interface StreamDecryptorHandle {
    decryptionChunkSize: number;
    decryptChunk: (data: Uint8Array) => Promise<Uint8Array>;
    isFinalized: () => boolean;
    free: () => void;
}

export const createStreamDecryptor = async (
    decryptionHeaderB64: string,
    keyB64: string,
): Promise<StreamDecryptorHandle> => {
    const decryptor = new (await wasm()).CryptoStreamDecryptor(
        decryptionHeaderB64,
        keyB64,
    );
    return {
        decryptionChunkSize: decryptor.decryption_chunk_size,
        decryptChunk: (data) => Promise.resolve(decryptor.decrypt_chunk(data)),
        isFinalized: () => decryptor.is_finalized,
        free: () => decryptor.free(),
    };
};

export interface EncryptedFileResult {
    encryptedData: string;
    decryptionHeader: string;
    md5Hash: string;
    key: string;
}

export const encryptFileStreamWithKey = async (
    dataB64: string,
    keyB64: string,
): Promise<EncryptedFileResult> =>
    plainValue(
        (await wasm()).crypto_encrypt_stream_with_key(dataB64, keyB64),
        encryptedFileValue,
    );

export const stringToB64 = (value: string): string =>
    toB64String(new TextEncoder().encode(value));

export const b64ToBytes = (value: string): Uint8Array<ArrayBuffer> =>
    fromB64String(value);

const derivedKeyValue = (key: {
    key: string;
    salt: string;
    ops_limit: number;
    mem_limit: number;
}): DerivedKey => ({
    key: key.key,
    salt: key.salt,
    opsLimit: key.ops_limit,
    memLimit: key.mem_limit,
});

const encryptedFileValue = (file: {
    encrypted_data: string;
    decryption_header: string;
    key: string;
    md5_hash: string;
}): EncryptedFileResult => ({
    encryptedData: file.encrypted_data,
    decryptionHeader: file.decryption_header,
    key: file.key,
    md5Hash: file.md5_hash,
});

const plainValue = <T extends { free: () => void }, U>(
    value: T,
    read: (value: T) => U,
) => {
    try {
        return read(value);
    } finally {
        value.free();
    }
};

const toB64String = (value: Uint8Array | string): string => {
    if (typeof value == "string") return value;
    let binary = "";
    for (const byte of value) binary += String.fromCharCode(byte);
    return btoa(binary);
};

const fromB64String = (value: string): Uint8Array<ArrayBuffer> => {
    const binary = atob(value);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
    return bytes;
};
