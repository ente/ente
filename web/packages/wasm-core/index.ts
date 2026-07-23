/**
 * @file TypeScript wrapper for the `ente-core` Rust crate.
 *
 * See `rust/crates/core` for full documentation.
 *
 * Each function loads the WebAssembly backend on first use (so all are async)
 * and runs on the calling thread; run heavy operations from a Web Worker to
 * keep the UI responsive.
 */
export * from "./blob";
export * from "./secretbox";
export * from "./types";
