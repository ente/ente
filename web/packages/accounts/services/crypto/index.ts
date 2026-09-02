import type { Remote } from "comlink";
import { inWorker } from "ente-base/env";
import { ComlinkWorker } from "ente-base/worker/comlink-worker";
import type { DerivedKey } from "./kdf";
import * as kdf from "./kdf";
import type { KDFWorker } from "./kdf.worker";
export {
    boxSealOpenBytes,
    decryptBox,
    deriveSubKeyBytes,
    encryptBox,
    generateKey,
    generateKeyPair,
    generateSRPSetup,
    recoveryKeyFromMnemonicOrHex,
} from "ente-core-wasm";
export type { EncryptedBoxB64 as EncryptedBox, KeyPair } from "ente-core-wasm";

export type { DerivedKey } from "./kdf";

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
