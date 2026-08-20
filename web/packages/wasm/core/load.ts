type EnteWasmModule = typeof import("ente-core-wasm");

let wasmPromise: Promise<EnteWasmModule> | undefined;
let cryptoReadyPromise: Promise<EnteWasmModule> | undefined;

export const loadEnteWasm = (): Promise<EnteWasmModule> =>
    (wasmPromise ??= import("ente-core-wasm").catch((error: unknown) => {
        wasmPromise = undefined;
        throw error;
    }));

export const loadCryptoReadyEnteWasm = (): Promise<EnteWasmModule> =>
    (cryptoReadyPromise ??= loadEnteWasm()
        .then((wasm) => {
            wasm.crypto_init();
            return wasm;
        })
        .catch((error: unknown) => {
            cryptoReadyPromise = undefined;
            throw error;
        }));
