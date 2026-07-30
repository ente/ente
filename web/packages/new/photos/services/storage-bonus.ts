import { authenticatedRequestHeaders, ensureOk } from "ente-base/http";
import { apiURL } from "ente-base/origins";
import { z } from "zod";

const ReferralView = z.object({
    planInfo: z.object({ isEnabled: z.boolean(), storageInGB: z.number() }),
    code: z.string(),
    enableApplyCode: z.boolean(),
    /**
     * `true` iff the user is a non-admin family member; the referral owner is
     * then the family admin.
     */
    isFamilyMember: z.boolean(),
    /**
     * Active REFERRAL + SIGN_UP bonus sum of the referral owner (in bytes).
     */
    claimedStorage: z.number(),
    remainingCodeChangeAttempts: z.number().optional(),
});

/**
 * Referral information for the currently logged in user.
 */
export type ReferralView = z.infer<typeof ReferralView>;

// Remote also returns referralStats and bonuses arrays. They are not modelled
// here; Zod strips the unknown keys.
const StorageBonusDetails = z.object({
    refCount: z.number(),
    refUpgradeCount: z.number(),
    hasAppliedCode: z.boolean(),
});

/**
 * Aggregate referral bonus details for the currently logged in user.
 */
export type StorageBonusDetails = z.infer<typeof StorageBonusDetails>;

export const normalizeReferralCode = (code: string) =>
    code.trim().toUpperCase();

/**
 * Fetch the referral view for the currently logged in user from remote.
 */
export const getReferralView = async (): Promise<ReferralView> => {
    const res = await fetch(await apiURL("/storage-bonus/referral-view"), {
        headers: await authenticatedRequestHeaders(),
    });
    ensureOk(res);
    return ReferralView.parse(await res.json());
};

/**
 * Fetch aggregate storage bonus details for the currently logged in user from
 * remote.
 */
export const getStorageBonusDetails =
    async (): Promise<StorageBonusDetails> => {
        const res = await fetch(await apiURL("/storage-bonus/details"), {
            headers: await authenticatedRequestHeaders(),
        });
        ensureOk(res);
        return StorageBonusDetails.parse(await res.json());
    };

/**
 * Change the referral code for the currently logged in user.
 */
export const changeReferralCode = async (code: string): Promise<void> => {
    ensureOk(
        await fetch(await apiURL("/storage-bonus/change-code"), {
            method: "POST",
            headers: await authenticatedRequestHeaders(),
            body: JSON.stringify({ code: normalizeReferralCode(code) }),
        }),
    );
};

/**
 * Claim a referral code for the currently logged in user.
 */
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
