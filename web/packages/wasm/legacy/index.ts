import type { OpenKitRecoveryInput } from "./pkg/ente_legacy_wasm";

export type {
    LegacyKitRecoveryHandle,
    LegacyKitRecoverySession,
} from "./pkg/ente_legacy_wasm";

const wasm = () => import("./pkg/ente_legacy_wasm");

export const openKitRecovery = async (input: OpenKitRecoveryInput) =>
    (await wasm()).openKitRecovery(input);
