import { clientPackageName, desktopAppVersion, isDesktop } from "ente-base/app";
import { apiOrigin } from "ente-base/origins";
import type { LegacyKitRecoveryHandle } from "ente-core-wasm";
import { loadCryptoReadyEnteWasm } from "ente-core-wasm/load";
import { z } from "zod";
import type { LegacyKitShare } from "./share";

export const LegacyKitRecoverySessionSchema = z.object({
    id: z.string(),
    kitID: z.string(),
    status: z.enum(["WAITING", "READY", "BLOCKED", "CANCELLED", "RECOVERED"]),
    // Despite the name, this is the remaining microseconds, not an epoch
    // timestamp.
    waitTill: z.number(),
    createdAt: z.number(),
});

export type LegacyKitRecoverySession = z.infer<
    typeof LegacyKitRecoverySessionSchema
>;

export interface OpenedLegacyKitRecovery {
    handle: LegacyKitRecoveryHandle;
    session: LegacyKitRecoverySession;
}

export const openLegacyKitRecovery = async (
    shares: LegacyKitShare[],
    email?: string,
): Promise<OpenedLegacyKitRecovery> => {
    const wasm = await loadCryptoReadyEnteWasm();
    const handle = await wasm.legacy_kit_open_recovery({
        baseUrl: await apiOrigin(),
        shares,
        email: email?.trim() || undefined,
        clientPackage: clientPackageName,
        clientVersion: isDesktop ? desktopAppVersion : undefined,
        userAgent:
            typeof navigator === "undefined" ? undefined : navigator.userAgent,
    });

    return {
        handle,
        session: LegacyKitRecoverySessionSchema.parse(handle.session()),
    };
};

export const refreshLegacyKitRecoverySession = async (
    handle: LegacyKitRecoveryHandle,
) => LegacyKitRecoverySessionSchema.parse(await handle.refresh_session());

export const changeLegacyKitPassword = async (
    handle: LegacyKitRecoveryHandle,
    password: string,
) => handle.change_password(password);

export const formatRecoveryWait = (waitRemainingMicros: number) => {
    if (waitRemainingMicros <= 0) {
        return "ready now";
    }

    const totalMinutes = Math.ceil(waitRemainingMicros / (1000 * 1000 * 60));
    if (totalMinutes >= 60 * 24) {
        const days = Math.ceil(totalMinutes / (60 * 24));
        return `${days} day${days === 1 ? "" : "s"}`;
    }
    if (totalMinutes >= 60) {
        const hours = Math.ceil(totalMinutes / 60);
        return `${hours} hour${hours === 1 ? "" : "s"}`;
    }
    return `${totalMinutes} minute${totalMinutes === 1 ? "" : "s"}`;
};
