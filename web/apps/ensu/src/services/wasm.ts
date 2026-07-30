/**
 * Lazy loader for the `ente-wasm` package or Tauri-native bindings.
 *
 * We keep this behind a dynamic import so that the WASM bundle is only loaded
 * when local crypto is needed, while Tauri uses native Rust bindings.
 */

import { isTauriRuntime } from "@/services/tauri-runtime";
import { loadEnteWasm } from "ente-wasm/load";

export type EnteWasmModule = typeof import("ente-wasm");

export interface EncryptedBlob {
    encrypted_data: string;
    decryption_header: string;
}

export interface EnteCryptoAdapter {
    crypto_init(): Promise<void>;
    crypto_generate_key(): Promise<string>;
    crypto_encrypt_blob(
        dataB64: string,
        keyB64: string,
    ): Promise<EncryptedBlob>;
    crypto_decrypt_blob(
        encryptedDataB64: string,
        headerB64: string,
        keyB64: string,
    ): Promise<string>;
}

const createWasmAdapter = (wasm: EnteWasmModule): EnteCryptoAdapter => {
    return {
        crypto_init: () => {
            wasm.crypto_init();
            return Promise.resolve();
        },
        crypto_generate_key: () => Promise.resolve(wasm.crypto_generate_key()),
        crypto_encrypt_blob: (dataB64, keyB64) =>
            Promise.resolve(wasm.crypto_encrypt_blob(dataB64, keyB64)),
        crypto_decrypt_blob: (encryptedDataB64, headerB64, keyB64) =>
            Promise.resolve(
                wasm.crypto_decrypt_blob(encryptedDataB64, headerB64, keyB64),
            ),
    };
};

const createTauriAdapter = async (): Promise<EnteCryptoAdapter> => {
    const { invoke } = (await import("@tauri-apps/api/core")) as {
        invoke: <T>(
            command: string,
            args?: Record<string, unknown>,
        ) => Promise<T>;
    };

    const toNativeError = (code: string, message: string) =>
        Object.assign(new Error(message), { code });

    const invokeOrThrow = async <T>(
        command: string,
        args?: Record<string, unknown>,
    ) => {
        try {
            return await invoke<T>(command, args);
        } catch (error) {
            if (
                typeof error === "object" &&
                error !== null &&
                "code" in error &&
                "message" in error
            ) {
                const code =
                    typeof error.code === "string"
                        ? error.code
                        : "native_error";
                const message =
                    typeof error.message === "string"
                        ? error.message
                        : "Unknown error";

                if (error instanceof Error) {
                    (error as Error & { code?: string }).code = code;
                    throw error;
                }

                throw toNativeError(code, message);
            }

            if (typeof error === "string") {
                try {
                    const parsed = JSON.parse(error) as {
                        code?: string;
                        message?: string;
                    };
                    if (parsed.code && parsed.message) {
                        throw toNativeError(parsed.code, parsed.message);
                    }
                } catch {
                    // ignore JSON parse failures
                }
                throw toNativeError("native_error", error);
            }

            if (error instanceof Error) {
                try {
                    const parsed = JSON.parse(error.message) as {
                        code?: string;
                        message?: string;
                    };
                    if (parsed.code && parsed.message) {
                        throw toNativeError(parsed.code, parsed.message);
                    }
                } catch {
                    // ignore JSON parse failures
                }
                throw toNativeError("native_error", error.message);
            }

            throw toNativeError("native_error", "Unknown error");
        }
    };

    return {
        crypto_init: async () => {
            await invokeOrThrow("crypto_init");
        },
        crypto_generate_key: () => invokeOrThrow<string>("crypto_generate_key"),
        crypto_encrypt_blob: (dataB64, keyB64) =>
            invokeOrThrow<EncryptedBlob>("crypto_encrypt_blob", {
                input: { dataB64, keyB64 },
            }),
        crypto_decrypt_blob: (encryptedDataB64, headerB64, keyB64) =>
            invokeOrThrow<string>("crypto_decrypt_blob", {
                input: { encryptedDataB64, headerB64, keyB64 },
            }),
    };
};

let _wasmPromise: Promise<EnteCryptoAdapter> | undefined;
let _cryptoInitDone = false;

export const enteWasm = async (): Promise<EnteCryptoAdapter> => {
    _wasmPromise ??= (async () => {
        if (isTauriRuntime()) {
            return createTauriAdapter();
        }
        const wasm = await loadEnteWasm();
        return createWasmAdapter(wasm);
    })();

    return _wasmPromise;
};

export const ensureCryptoInit = async () => {
    if (_cryptoInitDone) return;
    const wasm = await enteWasm();
    await wasm.crypto_init();
    _cryptoInitDone = true;
};
