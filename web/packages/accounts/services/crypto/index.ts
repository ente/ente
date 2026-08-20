import type { Remote } from "comlink";
import { inWorker } from "ente-base/env";
import { ComlinkWorker } from "ente-base/worker/comlink-worker";
import { loadCryptoReadyEnteWasm } from "ente-core-wasm/load";
import type { DerivedKey } from "./kdf";
import * as kdf from "./kdf";
import type { KDFWorker } from "./kdf.worker";

export { deriveKeyInsufficientMemoryErrorMessage } from "./kdf";
export type { DerivedKey } from "./kdf";

export interface EncryptedBox {
    encryptedData: string;
    nonce: string;
}

export interface KeyPair {
    publicKey: string;
    privateKey: string;
}

interface WasmGeneratedSRPSetup {
    srp_salt: string;
    srp_verifier: string;
    login_sub_key: string;
}

const b64ToBinary = (b64: string) => atob(b64);

export const fromB64 = (b64String: string): Promise<Uint8Array> => {
    const binary = b64ToBinary(b64String);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) {
        bytes[i] = binary.charCodeAt(i);
    }
    return Promise.resolve(bytes);
};

export const toB64 = (bytes: Uint8Array): Promise<string> => {
    let binary = "";
    for (const byte of bytes) binary += String.fromCharCode(byte);
    return Promise.resolve(btoa(binary));
};

export const toB64URLSafe = async (bytes: Uint8Array): Promise<string> =>
    (await toB64(bytes)).replace(/\+/g, "-").replace(/\//g, "_");

export const fromB64URLSafeNoPadding = async (b64String: string) => {
    let normalized = b64String.replace(/-/g, "+").replace(/_/g, "/");
    while (normalized.length % 4) normalized += "=";
    return fromB64(normalized);
};

const withKDFWorker = async <T>(
    callback: (worker: Remote<KDFWorker>) => Promise<T>,
): Promise<T> => {
    const worker = new ComlinkWorker<typeof KDFWorker>(
        "kdf",
        new Worker(new URL("kdf.worker.ts", import.meta.url)),
    );
    try {
        return await callback(await worker.remote);
    } finally {
        worker.terminate();
    }
};

export const deriveKey = (
    password: string,
    saltB64: string,
    opsLimit: number,
    memLimit: number,
): Promise<string> =>
    inWorker()
        ? kdf.deriveKey(password, saltB64, opsLimit, memLimit)
        : withKDFWorker((worker) =>
              worker.deriveKey(password, saltB64, opsLimit, memLimit),
          );

export const deriveSensitiveKey = (password: string): Promise<DerivedKey> =>
    inWorker()
        ? kdf.deriveSensitiveKey(password)
        : withKDFWorker((worker) => worker.deriveSensitiveKey(password));

export const deriveInteractiveKey = (password: string): Promise<DerivedKey> =>
    inWorker()
        ? kdf.deriveInteractiveKey(password)
        : withKDFWorker((worker) => worker.deriveInteractiveKey(password));

export const generateKey = async (): Promise<string> => {
    const wasm = await loadCryptoReadyEnteWasm();
    return wasm.crypto_generate_key();
};

export const generateKeyPair = async (): Promise<KeyPair> => {
    const wasm = await loadCryptoReadyEnteWasm();
    const keyPair = wasm.crypto_generate_keypair();
    return { publicKey: keyPair.public_key, privateKey: keyPair.secret_key };
};

export const encryptBox = async (
    dataB64: string,
    keyB64: string,
): Promise<EncryptedBox> => {
    const wasm = await loadCryptoReadyEnteWasm();
    const box = wasm.crypto_encrypt_box(dataB64, keyB64);
    return { encryptedData: box.encrypted_data, nonce: box.nonce };
};

export const decryptBox = async (
    box: EncryptedBox,
    keyB64: string,
): Promise<string> => {
    const wasm = await loadCryptoReadyEnteWasm();
    return wasm.crypto_decrypt_box(box.encryptedData, box.nonce, keyB64);
};

export const boxSealOpenBytes = async (
    encryptedData: string,
    keyPair: KeyPair,
): Promise<Uint8Array> => {
    const wasm = await loadCryptoReadyEnteWasm();
    return fromB64(
        wasm.crypto_box_seal_open(
            encryptedData,
            keyPair.publicKey,
            keyPair.privateKey,
        ),
    );
};

export const deriveSubKeyBytes = async (
    keyB64: string,
    subKeyLength: number,
    subKeyID: number,
    context: string,
) => {
    const wasm = await loadCryptoReadyEnteWasm();
    return fromB64(
        wasm.crypto_derive_subkey(
            keyB64,
            subKeyLength,
            BigInt(subKeyID),
            context,
        ),
    );
};

export const generateSRPSetupAttributesRust = async (
    kekB64: string,
    srpUserID: string,
) => {
    const wasm = await loadCryptoReadyEnteWasm();
    const setup = wasm.auth_generate_srp_setup(
        kekB64,
        srpUserID,
    ) as WasmGeneratedSRPSetup;
    return {
        srpSalt: setup.srp_salt,
        srpVerifier: setup.srp_verifier,
        loginSubKey: setup.login_sub_key,
    };
};

export const recoveryKeyFromMnemonicOrHex = async (value: string) => {
    const wasm = await loadCryptoReadyEnteWasm();
    return wasm.auth_recovery_key_from_mnemonic_or_hex(value);
};

export const recoveryKeyToMnemonicRust = async (recoveryKey: string) => {
    const wasm = await loadCryptoReadyEnteWasm();
    return wasm.auth_recovery_key_to_mnemonic(recoveryKey);
};
