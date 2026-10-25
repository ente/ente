// Adapted from `web/packages/accounts/services/accounts-db.ts`. Values that
// Ente keeps in `localStorage` now live in `browser.storage.local` so the
// popup and the background worker share one source of truth.
import { z } from "zod";
import {
    RemoteKeyAttributes,
    type KeyAttributes,
    type LocalUser,
} from "./keys";
import { RemoteSRPAttributes, type SRPAttributes } from "./srp";
import { getKV, removeKV, setKV } from "./storage";

export interface PartialLocalUser {
    id?: number;
    email?: string;
    token?: string;
    encryptedToken?: string;
    isTwoFactorEnabled?: boolean;
    twoFactorSessionID?: string;
}

const PartialLocalUser = z.object({
    id: z
        .number()
        .nullish()
        .transform((v) => v ?? undefined),
    email: z
        .string()
        .nullish()
        .transform((v) => v ?? undefined),
    token: z
        .string()
        .nullish()
        .transform((v) => v ?? undefined),
    encryptedToken: z
        .string()
        .nullish()
        .transform((v) => v ?? undefined),
    isTwoFactorEnabled: z
        .boolean()
        .nullish()
        .transform((v) => v ?? undefined),
    twoFactorSessionID: z
        .string()
        .nullish()
        .transform((v) => v ?? undefined),
});

const LocalUser = z.object({
    id: z.number(),
    email: z.string(),
    token: z.string(),
    isTwoFactorEnabled: z
        .boolean()
        .nullish()
        .transform((v) => v ?? undefined),
});

export const savedPartialLocalUser = async (): Promise<
    PartialLocalUser | undefined
> => {
    const value = await getKV("user");
    if (!value) return undefined;
    const { success, data } = PartialLocalUser.safeParse(value);
    return success ? data : undefined;
};

export const replaceSavedLocalUser = (partialLocalUser: PartialLocalUser) =>
    setKV("user", partialLocalUser);

export const updateSavedLocalUser = async (
    updates: Partial<PartialLocalUser>,
) => replaceSavedLocalUser({ ...(await savedPartialLocalUser()), ...updates });

export const savedLocalUser = async (): Promise<LocalUser | undefined> => {
    const value = await getKV("user");
    if (!value) return undefined;
    const { success, data } = LocalUser.safeParse(value);
    return success ? data : undefined;
};

export const clearLocalState = async () => {
    await Promise.all([
        removeKV("user"),
        removeKV("keyAttributes"),
        removeKV("srpAttributes"),
    ]);
};

// --- Key attributes ---------------------------------------------------------

export const savedKeyAttributes = async (): Promise<
    KeyAttributes | undefined
> => {
    const value = await getKV("keyAttributes");
    if (!value) return undefined;
    const { success, data } = RemoteKeyAttributes.safeParse(value);
    return success ? data : undefined;
};

export const saveKeyAttributes = (keyAttributes: KeyAttributes) =>
    setKV("keyAttributes", keyAttributes);

// --- SRP attributes ---------------------------------------------------------

export const savedSRPAttributes = async (): Promise<
    SRPAttributes | undefined
> => {
    const value = await getKV("srpAttributes");
    if (!value) return undefined;
    const { success, data } = RemoteSRPAttributes.safeParse(value);
    return success ? data : undefined;
};

export const saveSRPAttributes = (srpAttributes: SRPAttributes) =>
    setKV("srpAttributes", srpAttributes);
