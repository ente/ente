// Extension storage layer, replacing the `localStorage` / IndexedDB KV used by
// the Ente web packages (`ente-accounts/services/accounts-db.ts` and
// `ente-base/kv.ts`) so that the same values are reachable from the popup and
// the background service worker.
//
// Two tiers:
//   - `local`   : persistent across browser restarts (like Ente's localStorage).
//   - `session` : cleared when the browser closes (holds decrypted key
//                 material). Restricted to trusted extension contexts so that
//                 content scripts cannot read it.

import { browser } from "wxt/browser";

// Mirrors the Ente web KV keys so the values are recognisable to anyone
// familiar with `web/packages`.
const KV = { token: "token", apiOrigin: "apiOrigin" } as const;

export const getKV = async (key: string) => {
    const value = await browser.storage.local.get(key);
    return value[key] as unknown;
};

export const getKVS = async (key: string): Promise<string | undefined> => {
    const v = await getKV(key);
    return typeof v == "string" ? v : undefined;
};

export const setKV = (key: string, value: unknown) =>
    browser.storage.local.set({ [key]: value });

export const removeKV = (key: string) => browser.storage.local.remove(key);

export const kvKeys = KV;

// --- Decrypted, per-session material ----------------------------------------

// Secrets that only trusted extension contexts (popup, background) may read.
// `storage.session` defaults to exposing values to content scripts too, so we
// explicitly restrict access. The API is Chromium-only, hence the cast.
export const restrictSessionStorageToTrustedContexts = async () => {
    const session = browser.storage.session as unknown as {
        setAccessLevel?: (options: { accessLevel: string }) => Promise<void>;
    };
    try {
        await session.setAccessLevel?.({ accessLevel: "TRUSTED_CONTEXTS" });
    } catch {
        // Firefox / older Chromium: no-op, session storage is not exposed to
        // content scripts there anyway.
    }
};

export const getSession = async <T>(key: string): Promise<T | undefined> => {
    const value = await browser.storage.session.get(key);
    return value[key] as T | undefined;
};

export const setSession = (key: string, value: unknown) =>
    browser.storage.session.set({ [key]: value });

export const removeSession = (key: string) =>
    browser.storage.session.remove(key);

export const clearSessionStorage = () => browser.storage.session.clear();
