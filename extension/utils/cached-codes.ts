// Read-only view of the decrypted vault from `browser.storage.session`,
// generating OTPs on demand. Deliberately free of any wasm imports so the
// background service worker stays lightweight.
import { generateOTPs, type Code } from "./ente/code";
import { getSession } from "./ente/storage";
import { findBestCodeForHost } from "./matcher";
import type { CodeForHost } from "./messaging";
import { SESSION } from "./session-keys";

export const readCachedCodes = async (): Promise<Code[]> =>
    (await getSession<Code[]>(SESSION.codes)) ?? [];

export const readTimeOffset = async (): Promise<number> =>
    (await getSession<number>(SESSION.timeOffset)) ?? 0;

export const hasMatchForHost = async (host: string): Promise<boolean> => {
    const codes = await readCachedCodes();
    return !!findBestCodeForHost(codes, host);
};

export const codeForHost = async (
    host: string,
): Promise<CodeForHost | null> => {
    const codes = await readCachedCodes();
    const code = findBestCodeForHost(codes, host);
    if (!code) return null;

    const timeOffset = await readTimeOffset();
    const { otp, nextOTP, validFor } = generateOTPs(code, timeOffset);
    return {
        otp,
        nextOTP,
        validFor,
        issuer: code.issuer,
        account: code.account,
    };
};
