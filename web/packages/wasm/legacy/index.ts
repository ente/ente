import type { OpenKitRecoveryInput } from "./pkg/ente_legacy_wasm";

export type {
    LegacyKitRecoveryHandle,
    LegacyKitRecoverySession,
    LegacyKitShare,
} from "./pkg/ente_legacy_wasm";

const wasm = () => import("./pkg/ente_legacy_wasm");

export const loadLegacyKitParser = async () => {
    const { parseLegacyKitShare, validateLegacyKitSharePair } = await wasm();
    return { parseLegacyKitShare, validateLegacyKitSharePair };
};

export type LegacyKitParser = Awaited<ReturnType<typeof loadLegacyKitParser>>;

export const openKitRecovery = async (input: OpenKitRecoveryInput) =>
    (await wasm()).openKitRecovery(input);
