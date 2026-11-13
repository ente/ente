import { authenticatedRequestHeaders, ensureOk } from "ente-base/http";
import { apiURL } from "ente-base/origins";
import { z } from "zod";

const ReferralView = z.object({
    planInfo: z.object({ isEnabled: z.boolean(), storageInGB: z.number() }),
    code: z.string(),
    enableApplyCode: z.boolean(),
    // For non-admin family members, the family admin owns the referral.
    isFamilyMember: z.boolean(),
    // Active referral and sign-up bonuses owned by the referral owner, in bytes.
    claimedStorage: z.number(),
    remainingCodeChangeAttempts: z.number().optional(),
});

export type ReferralView = z.infer<typeof ReferralView>;

// Zod intentionally strips the remote referralStats and bonuses arrays.
const StorageBonusDetails = z.object({
    refCount: z.number(),
    refUpgradeCount: z.number(),
    hasAppliedCode: z.boolean(),
});

export type StorageBonusDetails = z.infer<typeof StorageBonusDetails>;

export const normalizeReferralCode = (code: string) =>
    code.trim().toUpperCase();

export const getReferralView = async (): Promise<ReferralView> => {
    const res = await fetch(await apiURL("/storage-bonus/referral-view"), {
        headers: await authenticatedRequestHeaders(),
    });
    ensureOk(res);
    return ReferralView.parse(await res.json());
};

export const getStorageBonusDetails =
    async (): Promise<StorageBonusDetails> => {
        const res = await fetch(await apiURL("/storage-bonus/details"), {
            headers: await authenticatedRequestHeaders(),
        });
        ensureOk(res);
        return StorageBonusDetails.parse(await res.json());
    };

export const changeReferralCode = async (code: string): Promise<void> => {
    ensureOk(
        await fetch(await apiURL("/storage-bonus/change-code"), {
            method: "POST",
            headers: await authenticatedRequestHeaders(),
            body: JSON.stringify({ code: normalizeReferralCode(code) }),
        }),
    );
};

export const claimReferralCode = async (code: string): Promise<void> => {
    ensureOk(
        await fetch(
            await apiURL("/storage-bonus/referral-claim", {
                code: normalizeReferralCode(code),
            }),
            { method: "POST", headers: await authenticatedRequestHeaders() },
        ),
    );
};
