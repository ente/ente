import { updateSavedLocalUser } from "ente-accounts/services/accounts-db";
import { ensureLocalUser } from "ente-accounts/services/user";
import { isDesktop } from "ente-base/app";
import { authenticatedRequestHeaders, ensureOk } from "ente-base/http";
import { getKV, setKV } from "ente-base/kv";
import log from "ente-base/log";
import { apiURL } from "ente-base/origins";
import {
    nullishToEmpty,
    nullishToZero,
    nullToUndefined,
} from "ente-utils/transform";
import { z } from "zod";

export type PlanPeriod = "month" | "year";

const Subscription = z.object({
    productID: z.string(),
    storage: z.number(),
    // Epoch microseconds.
    expiryTime: z.number(),
    paymentProvider: z.string(),
    price: z.string(),
    period: z
        .string()
        .transform((p) => (p == "month" || p == "year" ? p : undefined)),
    attributes: z
        .object({
            isCancelled: z.boolean().nullish().transform(nullToUndefined),
        })
        .nullish()
        .transform(nullToUndefined),
});

export type Subscription = z.infer<typeof Subscription>;

const FamilyMember = z.object({
    // Family membership ID, not the Ente user ID.
    id: z.string(),
    email: z.string(),
    status: z.enum(["SELF", "INVITED", "ACCEPTED"]),
    // Invited members lack these fields until they accept.
    userID: z.number().nullish().transform(nullToUndefined),
    isAdmin: z.boolean().nullish().transform(nullToUndefined),
    usage: z.number().nullish().transform(nullToUndefined),
    storageLimit: z.number().nullish().transform(nullToUndefined),
});

export type FamilyMember = z.infer<typeof FamilyMember>;

const FamilyData = z.object({
    members: z.array(FamilyMember),
    // Admin subscription capacity only; excludes bonuses and add-ons.
    storage: z.number(),
});

export type FamilyData = z.infer<typeof FamilyData>;

const Bonus = z.object({
    type: z.string(),
    storage: z.number(),
    // Zero means the bonus never expires.
    validTill: z.number(),
});

export type Bonus = z.infer<typeof Bonus>;

const BonusData = z.object({
    storageBonuses: Bonus.array().nullish().transform(nullishToEmpty),
});

export type BonusData = z.infer<typeof BonusData>;

const UserDetails = z.object({
    email: z.string(),
    usage: z.number(),
    fileCount: z.number().nullish().transform(nullishToZero),
    subscription: Subscription,
    familyData: FamilyData.nullish().transform(nullToUndefined),
    storageBonus: z.number().nullish().transform(nullishToZero),
    bonusData: BonusData.nullish().transform(nullToUndefined),
});

export type UserDetails = z.infer<typeof UserDetails>;

class UserDetailsState {
    userDetailsListeners: (() => void)[] = [];
    userDetailsSnapshot: UserDetails | undefined;
}

let _state = new UserDetailsState();

export const logoutUserDetails = () => {
    _state = new UserDetailsState();
};

export const savedUserDetailsOrTriggerPull = async () => {
    const saved = UserDetails.safeParse(await getKV("userDetails"));
    if (saved.success) {
        setUserDetailsSnapshot(saved.data);
        return saved.data;
    }

    // Missing or obsolete local data starts a pull without blocking startup.
    void pullUserDetails();
    return undefined;
};

export const userDetailsSubscribe = (onChange: () => void): (() => void) => {
    _state.userDetailsListeners.push(onChange);
    return () => {
        _state.userDetailsListeners = _state.userDetailsListeners.filter(
            (l) => l != onChange,
        );
    };
};

export const userDetailsSnapshot = () => _state.userDetailsSnapshot;

const setUserDetailsSnapshot = (snapshot: UserDetails) => {
    _state.userDetailsSnapshot = snapshot;
    _state.userDetailsListeners.forEach((l) => l());
};

export const pullUserDetails = async () => {
    const userDetails = await getUserDetails();
    await setKV("userDetails", userDetails);

    // Email may have changed on another client.
    const { email } = userDetails;
    if (ensureLocalUser().email != email) {
        log.info("Updating user email to match fetched user details");
        updateSavedLocalUser({ email });
    }

    // useSyncExternalStore treats equivalent object identities as changes.
    if (JSON.stringify(userDetails) != JSON.stringify(userDetailsSnapshot())) {
        setUserDetailsSnapshot(userDetails);
    }
};

const getUserDetails = async () => {
    const res = await fetch(await apiURL("/users/details/v2"), {
        headers: await authenticatedRequestHeaders(),
    });
    ensureOk(res);
    return UserDetails.parse(await res.json());
};

const Plan = z.object({
    id: z.string(),
    androidID: z.string().nullish().transform(nullToUndefined),
    iosID: z.string().nullish().transform(nullToUndefined),
    stripeID: z.string().nullish().transform(nullToUndefined),
    storage: z.number(),
    price: z.string(),
    period: z
        .string()
        .transform((p) => (p == "month" || p == "year" ? p : undefined)),
});

export type Plan = z.infer<typeof Plan>;

const PlansData = z.object({
    freePlan: z.object({ storage: z.number() }),
    plans: z.array(Plan),
});

export type PlansData = z.infer<typeof PlansData>;

export const getPlansData = async (): Promise<PlansData> => {
    const res = await fetch(await apiURL("/billing/user-plans"), {
        headers: await authenticatedRequestHeaders(),
    });
    ensureOk(res);
    return PlansData.parse(await res.json());
};

export const planUsage = (userDetails: UserDetails) =>
    isPartOfFamily(userDetails) ? familyUsage(userDetails) : userDetails.usage;

export const verifyStripeSubscription = async (
    sessionID: unknown,
): Promise<Subscription> => {
    ensureOk(
        await fetch(await apiURL("/billing/verify-subscription"), {
            method: "POST",
            headers: await authenticatedRequestHeaders(),
            body: JSON.stringify({
                paymentProvider: "stripe",
                productID: null,
                verificationData: sessionID,
            }),
        }),
    );
    await pullUserDetails();
    return userDetailsSnapshot()!.subscription;
};

export const activateStripeSubscription = async () => {
    ensureOk(
        await fetch(await apiURL("/billing/stripe/activate-subscription"), {
            method: "POST",
            headers: await authenticatedRequestHeaders(),
        }),
    );
    return pullUserDetails();
};

export const cancelStripeSubscription = async () => {
    ensureOk(
        await fetch(await apiURL("/billing/stripe/cancel-subscription"), {
            method: "POST",
            headers: await authenticatedRequestHeaders(),
        }),
    );
    return pullUserDetails();
};

const paymentsAppOrigin = "https://payments.ente.com";

export const redirectToPaymentsApp = async (
    productID: string,
    action: "buy" | "update",
) => {
    const paymentToken = await getPaymentToken();
    const redirectURL = paymentCompletionRedirectURL();
    window.location.href = `${paymentsAppOrigin}?productID=${productID}&paymentToken=${paymentToken}&action=${action}&redirectURL=${redirectURL}`;
};

const paymentCompletionRedirectURL = () =>
    isDesktop
        ? `${paymentsAppOrigin}/desktop-redirect`
        : `${window.location.origin}/gallery`;

const getPaymentToken = async () => {
    const res = await fetch(await apiURL("/users/payment-token"), {
        headers: await authenticatedRequestHeaders(),
    });
    ensureOk(res);
    return z.object({ paymentToken: z.string() }).parse(await res.json())
        .paymentToken;
};

export const redirectToCustomerPortal = async () => {
    const redirectURL = paymentCompletionRedirectURL();
    const res = await fetch(
        await apiURL("/billing/stripe/customer-portal", { redirectURL }),
        { headers: await authenticatedRequestHeaders() },
    );
    ensureOk(res);
    const portal = z.object({ url: z.string() }).parse(await res.json());
    window.location.href = portal.url;
};

export const isSubscriptionActive = (subscription: Subscription) =>
    subscription.expiryTime > Date.now() * 1000;

export const isSubscriptionActivePaid = (subscription: Subscription) =>
    isSubscriptionActive(subscription) && subscription.productID != "free";

export const isSubscriptionFree = (subscription: Subscription) =>
    subscription.productID == "free";

export const isSubscriptionForPlan = (subscription: Subscription, plan: Plan) =>
    plan.stripeID === subscription.productID ||
    plan.iosID === subscription.productID ||
    plan.androidID === subscription.productID;

export const isSubscriptionStripe = (subscription: Subscription) =>
    subscription.paymentProvider == "stripe";

export const isSubscriptionCancelled = (subscription: Subscription) =>
    subscription.attributes?.isCancelled;

export const isPartOfFamily = (userDetails: UserDetails) =>
    (userDetails.familyData?.members.length ?? 0) > 0;

export const isPartOfFamilyWithOtherMembers = (userDetails: UserDetails) =>
    (userDetails.familyData?.members.length ?? 0) > 1;

export const isFamilyAdmin = (userDetails: UserDetails) =>
    userDetails.email == familyAdminEmail(userDetails);

export const familyMemberStorageLimit = (userDetails: UserDetails) =>
    userDetails.familyData?.members.find((m) => m.email == userDetails.email)
        ?.storageLimit;

export const familyAdminEmail = (userDetails: UserDetails) =>
    userDetails.familyData?.members.find((x) => x.isAdmin)?.email;

export const familyUsage = (userDetails: UserDetails) =>
    (userDetails.familyData?.members ?? []).reduce(
        (sum, { usage }) => sum + (usage ?? 0),
        0,
    );

export const leaveFamily = async () => {
    ensureOk(
        await fetch(await apiURL("/family/leave"), {
            method: "DELETE",
            headers: await authenticatedRequestHeaders(),
        }),
    );
    return pullUserDetails();
};

export const isSubscriptionPastDue = (subscription: Subscription) => {
    const thirtyDaysMicroseconds = 30 * 24 * 60 * 60 * 1000 * 1000;
    const currentTime = Date.now() * 1000;
    return (
        !isSubscriptionCancelled(subscription) &&
        subscription.expiryTime < currentTime &&
        subscription.expiryTime >= currentTime - thirtyDaysMicroseconds
    );
};

export const userDetailsAddOnBonuses = (userDetails: UserDetails) =>
    userDetails.bonusData?.storageBonuses.filter((bonus) =>
        bonus.type.startsWith("ADD_ON"),
    ) ?? [];

export const hasExceededStorageQuota = (userDetails: UserDetails) => {
    let usage: number;
    let storage: number;
    if (isPartOfFamily(userDetails)) {
        usage = familyUsage(userDetails);
        storage = userDetails.familyData?.storage ?? 0;
    } else {
        usage = userDetails.usage;
        storage = userDetails.subscription.storage;
    }
    return usage > storage + userDetails.storageBonus;
};
