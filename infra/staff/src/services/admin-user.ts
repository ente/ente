import { z } from "zod";
import {
    apiURL,
    ensureOk,
    requireEmail,
    staffJSONRequestHeaders,
    staffRequestHeaders,
} from "./api";
import type { StaffSession } from "./session";

const nullToUndefined = <T>(value: T | null | undefined): T | undefined =>
    value === null ? undefined : value;

const nullishToEmpty = <T>(value: T[] | null | undefined): T[] => value ?? [];

const nullishToZero = (value: number | null | undefined): number => value ?? 0;

const UserProfileData = z.object({
    isEmailMFAEnabled: z.boolean(),
    isTwoFactorEnabled: z.boolean(),
    passkeyCount: z.number(),
    canDisableEmailMFA: z.boolean(),
});

const FamilyMember = z.object({
    id: z.string(),
    email: z.string(),
    status: z.string(),
    userID: z.number().nullish().transform(nullToUndefined),
    usage: z.number().nullish().transform(nullToUndefined),
    storageLimit: z.number().nullish().transform(nullToUndefined),
});

export type FamilyMember = z.infer<typeof FamilyMember>;

const StorageBonus = z.object({
    storage: z.number(),
    type: z.string(),
    createdAt: z.number(),
    validTill: z.number(),
    isRevoked: z.boolean(),
});

export type StorageBonus = z.infer<typeof StorageBonus>;

const TokenData = z.object({
    creationTime: z.number(),
    lastUsedTime: z.number(),
    ua: z.string(),
    isDeleted: z.boolean(),
    app: z.string(),
});

export type TokenData = z.infer<typeof TokenData>;

const Subscription = z.object({
    productID: z.string(),
    paymentProvider: z.string(),
    storage: z.number(),
    originalTransactionID: z.string(),
    expiryTime: z.number(),
    userID: z.number(),
    attributes: z.object({
        customerID: z.string().optional(),
        stripeAccountCountry: z.string().optional(),
    }),
});

export type Subscription = z.infer<typeof Subscription>;

const FamilyData = z
    .object({ members: z.array(FamilyMember) })
    .nullish()
    .transform(nullToUndefined);

const BonusData = z
    .object({
        storageBonuses: z
            .array(StorageBonus)
            .nullish()
            .transform(nullishToEmpty),
    })
    .nullish()
    .transform(nullToUndefined);

const UserDetails = z
    .object({
        usage: z.number(),
        storageBonus: z.number().nullish().transform(nullishToZero),
        profileData: UserProfileData.nullish().transform(nullToUndefined),
        familyData: FamilyData,
        bonusData: BonusData,
    })
    .nullish()
    .transform(nullToUndefined);

const UserResponse = z.object({
    user: z.object({
        ID: z.number(),
        email: z.string(),
        creationTime: z.number(),
    }),
    subscription: Subscription.nullish().transform(nullToUndefined),
    authCodes: z.number().nullish().transform(nullishToZero),
    tokens: z.array(TokenData).nullish().transform(nullishToEmpty),
    details: UserDetails,
});

export type UserResponse = z.infer<typeof UserResponse>;

const ScheduledDeletionResponse = z.object({
    scheduledDeletions: z.array(
        z.object({
            userID: z.number(),
            userCreatedAt: z.number(),
            scheduledAt: z.number(),
            deletionStartsAt: z.number(),
            storageConsumed: z.number(),
            authenticatorEntryCount: z.number(),
        }),
    ),
});

export type ScheduledDeletion = z.infer<
    typeof ScheduledDeletionResponse
>["scheduledDeletions"][number];

interface AddOTTRequest {
    email: string;
    code: string;
    app: string;
    expiryTime: number;
}

export interface UpdateSubscriptionRequest {
    userID: number;
    storage: number;
    expiryTime: number;
    productID: string;
    paymentProvider: string;
    transactionID: string;
    attributes: { customerID: string; stripeAccountCountry: string };
}

const userSearchQuery = (input: string) => {
    const trimmedInput = input.trim();
    if (/^\d+$/.test(trimmedInput)) {
        return { id: trimmedInput };
    }
    return { email: trimmedInput };
};

export const getUser = async (
    session: Pick<StaffSession, "token">,
    input: string,
) => {
    if (!input.trim()) {
        throw new Error("Enter an email or user ID");
    }

    const response = await fetch(
        apiURL("/admin/user", userSearchQuery(input)),
        { headers: staffJSONRequestHeaders(session) },
    );
    if (response.status === 401) {
        throw new Error("Invalid token");
    }
    if (response.status === 403) {
        throw new Error("Insufficient permissions");
    }
    if (response.status === 404) {
        throw new Error("User not found");
    }

    await ensureOk(response, "Network response was not ok");
    return UserResponse.parse(await response.json());
};

export const getScheduledDeletions = async (
    session: Pick<StaffSession, "token">,
    email: string,
) => {
    const response = await fetch(
        apiURL("/admin/user/scheduled-deletions", { email }),
        { headers: staffJSONRequestHeaders(session) },
    );
    await ensureOk(response, "Failed to fetch scheduled deletions");
    return ScheduledDeletionResponse.parse(await response.json())
        .scheduledDeletions;
};

export const recoverScheduledDeletion = async (
    session: Pick<StaffSession, "token">,
    userID: number,
    emailID: string,
) => {
    const response = await fetch(apiURL("/admin/user/recover"), {
        method: "POST",
        headers: staffJSONRequestHeaders(session),
        body: JSON.stringify({ userID, emailID }),
    });
    await ensureOk(response, "Failed to recover account");
};

export const unblockStorageWarningLogin = async (
    session: Pick<StaffSession, "token">,
    userID: number,
) => {
    const response = await fetch(
        apiURL("/admin/user/unblock-storage-warning-login"),
        {
            method: "POST",
            headers: staffJSONRequestHeaders(session),
            body: JSON.stringify({ userID }),
        },
    );
    await ensureOk(response, "Failed to unblock storage-warning login");
};

export const getSelectedUser = async (session: StaffSession) => {
    const response = await fetch(
        apiURL("/admin/user", { email: requireEmail(session) }),
        { headers: staffJSONRequestHeaders(session) },
    );
    await ensureOk(response, "Failed to fetch user data");
    return UserResponse.parse(await response.json());
};

export const getSelectedUserID = async (session: StaffSession) => {
    const userData = await getSelectedUser(session);
    const userID = userData.subscription?.userID;
    if (userID === undefined) throw new Error("User ID not found");
    return userID;
};

export const getSelectedSubscription = async (session: StaffSession) => {
    const userData = await getSelectedUser(session);
    if (!userData.subscription) {
        throw new Error("Subscription data not found");
    }
    return userData.subscription;
};

export const getFamilyMembers = async (session: StaffSession) => {
    const userData = await getSelectedUser(session);
    return userData.details?.familyData?.members ?? [];
};

export const getStorageBonuses = async (session: StaffSession) => {
    const userData = await getSelectedUser(session);
    return userData.details?.bonusData?.storageBonuses ?? [];
};

export const getTokens = async (session: StaffSession) => {
    const userData = await getSelectedUser(session);
    return userData.tokens;
};

export const addOTT = async (
    session: StaffSession,
    { app, code, email, expiryTime }: AddOTTRequest,
) => {
    const response = await fetch(apiURL("/admin/user/add-ott"), {
        method: "POST",
        headers: staffJSONRequestHeaders(session),
        body: JSON.stringify({ email, code, app, expiryTime }),
    });
    await ensureOk(response, "Failed to create OTT");
};

export const changeUserEmail = async (
    session: StaffSession,
    userID: number,
    email: string,
) => {
    const response = await fetch(apiURL("/admin/user/change-email"), {
        method: "PUT",
        headers: staffJSONRequestHeaders(session),
        body: JSON.stringify({ userID, email }),
    });
    await ensureOk(response, "Network response was not ok");
};

export const closeFamily = async (session: StaffSession) => {
    const userID = await getSelectedUserID(session);
    const response = await fetch(apiURL("/admin/user/close-family"), {
        method: "POST",
        headers: staffJSONRequestHeaders(session),
        body: JSON.stringify({ userID }),
    });
    await ensureOk(response, "Failed to close family");
};

export const deleteAccount = async (session: StaffSession) => {
    const response = await fetch(
        apiURL("/admin/user/delete", { email: requireEmail(session) }),
        { method: "DELETE", headers: staffRequestHeaders(session) },
    );
    await ensureOk(response, "Failed to delete user account");
};

export const disable2FA = async (session: StaffSession) => {
    const userID = await getSelectedUserID(session);
    const response = await fetch(apiURL("/admin/user/disable-2fa"), {
        method: "POST",
        headers: staffJSONRequestHeaders(session),
        body: JSON.stringify({ userID }),
    });
    await ensureOk(response, "Failed to disable 2FA");
};

export const disablePasskeys = async (session: StaffSession) => {
    const userID = await getSelectedUserID(session);
    const response = await fetch(apiURL("/admin/user/disable-passkeys"), {
        method: "POST",
        headers: staffJSONRequestHeaders(session),
        body: JSON.stringify({ userID }),
    });
    await ensureOk(response, "Failed to disable passkeys");
};

export const updateEmailMFA = async (
    session: StaffSession,
    emailMFA: boolean,
) => {
    const userID = await getSelectedUserID(session);
    const response = await fetch(apiURL("/admin/user/update-email-mfa"), {
        method: "POST",
        headers: staffJSONRequestHeaders(session),
        body: JSON.stringify({ userID, emailMFA }),
    });
    await ensureOk(response, "Failed to update Email MFA");
};

export const updateUserSubscription = async (
    session: StaffSession,
    request: UpdateSubscriptionRequest,
) => {
    const response = await fetch(apiURL("/admin/user/subscription"), {
        method: "PUT",
        headers: staffJSONRequestHeaders(session),
        body: JSON.stringify(request),
    });
    await ensureOk(response, "Network response was not ok");
};
