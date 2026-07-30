/**
 * Return the lazy-loaded shared `ente-wasm-core` WebAssembly module.
 */
export const loadWasmCore = () => import("./pkg/ente_wasm_core");
