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

/**
 * Validity of the plan.
 */
export type PlanPeriod = "month" | "year";

const Subscription = z.object({
    /**
     * Store-specific ID of the product ("plan") that the user has subscribed
     * to. e.g. if the user has subscribed to a plan using Stripe, then this
     * will be the stripeID of the corresponding {@link Plan}.
     *
     * For free plans, the productID will be the constant "free".
     */
    productID: z.string(),
    /**
     * Storage (in bytes) that the user can use.
     */
    storage: z.number(),
    /**
     * Epoch microseconds indicating the time until which the user's
     * subscription is valid.
     */
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

/**
 * Details about the user's subscription.
 */
export type Subscription = z.infer<typeof Subscription>;

const FamilyMember = z.object({
    /**
     * ID of the family membership.
     */
    id: z.string(),
    /**
     * Email address of the family member.
     */
    email: z.string(),
    status: z.enum(["SELF", "INVITED", "ACCEPTED"]),
    /**
     * ID of the family member's Ente account.
     *
     * This is not available until the member joins the family.
     */
    userID: z.number().nullish().transform(nullToUndefined),
    /**
     * `true` if this is the admin.
     *
     * This field will not be sent for invited members until they accept.
     */
    isAdmin: z.boolean().nullish().transform(nullToUndefined),
    /**
     * Storage used by the family member.
     *
     * This field will not be present for invited members until they accept.
     */
    usage: z.number().nullish().transform(nullToUndefined),
    /**
     * Storage limit allocated to the family member.
     *
     * This field will not be present unless the admin for the family plan has
     * configured a member specific limit, in which case this will be the limit
     * (in bytes) specifying the storage which this member can use.
     */
    storageLimit: z.number().nullish().transform(nullToUndefined),
});

export type FamilyMember = z.infer<typeof FamilyMember>;

/**
 * Zod schema for details about the family plan (if any) that the user is a part
 * of.
 */
const FamilyData = z.object({
    members: z.array(FamilyMember),
    /**
     * Family admin subscription storage capacity.
     *
     * This excludes add-on and any other bonus storage.
     */
    storage: z.number(),
});

/**
 * Details about the family plan (if any) that the user is a part of.
 */
export type FamilyData = z.infer<typeof FamilyData>;

const Bonus = z.object({
    /**
     * The type of the bonus.
     */
    type: z.string(),
    /**
     * Amount of storage bonus (in bytes) added to the account.
     */
    storage: z.number(),
    /**
     * Validity of the storage bonus. If it is 0, it is valid forever.
     */
    validTill: z.number(),
});

/**
 * Details about an individual bonus applied for the user.
 */
export type Bonus = z.infer<typeof Bonus>;

const BonusData = z.object({
    /**
     * List of bonuses applied for the user.
     */
    storageBonuses: Bonus.array().nullish().transform(nullishToEmpty),
});

/**
 * Information about bonuses applied for the user.
 */
export type BonusData = z.infer<typeof BonusData>;

/**
 * Zod schema for {@link UserDetails}
 */
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

/**
 * Internal in-memory state shared by the functions in this module.
 *
 * This entire object will be reset on logout.
 */
class UserDetailsState {
    /**
     * Subscriptions to {@link UserDetails} updates attached using
     * {@link userDetailsSubscribe}.
     */
    userDetailsListeners: (() => void)[] = [];

    /**
     * Snapshot of the {@link UserDetails} returned by the
     * {@link userDetailsSnapshot} function.
     */
    userDetailsSnapshot: UserDetails | undefined;
}

/**
 * State shared by the functions in this module. See {@link UserDetailsState}.
 */
let _state = new UserDetailsState();

export const logoutUserDetails = () => {
    _state = new UserDetailsState();
};

/**
 * Read in the locally persisted user details into memory and return them.
 *
 * If there are no compatible locally persisted values, initiate a network
 * request to fetch the latest values (but don't wait for it to complete).
 *
 * This assumes that the user is already logged in.
 */
export const savedUserDetailsOrTriggerPull = async () => {
    const saved = UserDetails.safeParse(await getKV("userDetails"));
    if (saved.success) {
        setUserDetailsSnapshot(saved.data);
        return saved.data;
    }

    void pullUserDetails();
    return undefined;
};

/**
 * A function that can be used to subscribe to updates to {@link UserDetails}.
 *
 * [Note: Snapshots and useSyncExternalStore]
 *
 * This subscribe function, along with {@link userDetailsSnapshot}, is meant to
 * be used as arguments to React's {@link useSyncExternalStore}.
 *
 * @param callback A function that will be invoked whenever the result of
 * {@link userDetailsSnapshot} changes.
 *
 * @returns A function that can be used to clear the subscription.
 */
export const userDetailsSubscribe = (onChange: () => void): (() => void) => {
    _state.userDetailsListeners.push(onChange);
    return () => {
        _state.userDetailsListeners = _state.userDetailsListeners.filter(
            (l) => l != onChange,
        );
    };
};

/**
 * Return the last known, cached {@link UserDetails}.
 *
 * This, along with {@link userDetailsSubscribe}, is meant to be used as
 * arguments to React's {@link useSyncExternalStore}.
 */
export const userDetailsSnapshot = () => _state.userDetailsSnapshot;

const setUserDetailsSnapshot = (snapshot: UserDetails) => {
    _state.userDetailsSnapshot = snapshot;
    _state.userDetailsListeners.forEach((l) => l());
};

/**
 * Fetch the user's details from remote and save them in local storage for
 * subsequent lookup, and also update our in-memory snapshots.
 */
export const pullUserDetails = async () => {
    const userDetails = await getUserDetails();
    await setKV("userDetails", userDetails);

    // Update the email for the local storage user if needed (the user might've
    // changed their email on a different client).
    const { email } = userDetails;
    if (ensureLocalUser().email != email) {
        log.info("Updating user email to match fetched user details");
        updateSavedLocalUser({ email });
    }

    // The gallery listens for updates to userDetails, so a special case, do a
    // deep equality check so as to not rerender it on redundant updates.
    //
    // [Note: Deep equal check]
    //
    // React uses `Object.is` to detect changes, which changes for arrays,
    // objects and combinations thereof even if the underlying data is the same.
    //
    // In many cases, the code can be restructured to avoid this being a
    // problem, or the rerender might be infrequent enough that it is not a
    // problem.
    //
    // However, when used with useSyncExternalStore, there is an easy way to
    // prevent this, by doing a preflight deep equality comparison.
    //
    // There are arguably faster libraries out there that'll do the deep
    // equality check for us, but since it is an infrequent pattern in our code
    // base currently, we just use the JSON serialization.
    //
    // Mark all cases that do this using this note's title so we can audit them
    // if we move to a deep equality comparison library in the future.

    if (JSON.stringify(userDetails) != JSON.stringify(userDetailsSnapshot())) {
        setUserDetailsSnapshot(userDetails);
    }
};

/**
 * Fetch the user details for the currently logged in user from remote.
 */
const getUserDetails = async () => {
    const res = await fetch(await apiURL("/users/details/v2"), {
        headers: await authenticatedRequestHeaders(),
    });
    ensureOk(res);
    return UserDetails.parse(await res.json());
};

/**
 * Zod schema for an individual plan received in the list of plans.
 */
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

/**
 * An individual plan received in the list of plans from remote.
 */
export type Plan = z.infer<typeof Plan>;

const PlansData = z.object({
    freePlan: z.object({
        /* Number of bytes available in the free plan. */
        storage: z.number(),
    }),
    plans: z.array(Plan),
});

export type PlansData = z.infer<typeof PlansData>;

/**
 * Fetch the list of plans from remote.
 */
export const getPlansData = async (): Promise<PlansData> => {
    const res = await fetch(await apiURL("/billing/user-plans"), {
        headers: await authenticatedRequestHeaders(),
    });
    ensureOk(res);
    return PlansData.parse(await res.json());
};

/**
 * Derive the total usage for the user both when they are on an individual plan,
 * or on a family plan.
 */
export const planUsage = (userDetails: UserDetails) =>
    isPartOfFamily(userDetails) ? familyUsage(userDetails) : userDetails.usage;

/**
 * Ask remote to acknowledge a subscription that was completed via Stripe,
 * updating our local state to reflect the new subscription on successful
 * verification.
 *
 * @param sessionID Arbitrary and optional string passed on completion of the
 * flow. It is forwarded as the verification data to remote.
 */
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

/**
 * Ask remote to reactivate the user's current Stripe subscription (that user
 * had previously cancelled), updating our local state to reflect the changes on
 * success.
 */
export const activateStripeSubscription = async () => {
    ensureOk(
        await fetch(await apiURL("/billing/stripe/activate-subscription"), {
            method: "POST",
            headers: await authenticatedRequestHeaders(),
        }),
    );
    return pullUserDetails();
};

/**
 * Ask remote to cancel the user's current Stripe subscription, updating our
 * local state to reflect the changes on success.
 */
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

/**
 * Start the flow to purchase or update a subscription by redirecting the user
 * to the payments app.
 *
 * @param productID The Stripe product ID of the plan to purchase.
 *
 * @param action buy or update.
 */
export const redirectToPaymentsApp = async (
    productID: string,
    action: "buy" | "update",
) => {
    const paymentToken = await getPaymentToken();
    const redirectURL = paymentCompletionRedirectURL();
    window.location.href = `${paymentsAppOrigin}?productID=${productID}&paymentToken=${paymentToken}&action=${action}&redirectURL=${redirectURL}`;
};

/**
 * Return the URL to which the payments app should redirect back on completion
 * of the flow.
 */
const paymentCompletionRedirectURL = () =>
    isDesktop
        ? `${paymentsAppOrigin}/desktop-redirect`
        : `${window.location.origin}/gallery`;

/**
 * Fetch and return a one-time token that can be used to authenticate user's
 * requests to the payments app.
 */
const getPaymentToken = async () => {
    const res = await fetch(await apiURL("/users/payment-token"), {
        headers: await authenticatedRequestHeaders(),
    });
    ensureOk(res);
    return z.object({ paymentToken: z.string() }).parse(await res.json())
        .paymentToken;
};

/**
 * Redirect to the Stripe customer portal / dashboard where the user can view
 * details about their subscription and modify their payment method.
 */
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

/**
 * Return true if the given {@link Subscription} has not expired.
 */
export const isSubscriptionActive = (subscription: Subscription) =>
    subscription.expiryTime > Date.now() * 1000;

/**
 * Return true if the given {@link Subscription} is active and for a paid plan.
 */
export const isSubscriptionActivePaid = (subscription: Subscription) =>
    isSubscriptionActive(subscription) && subscription.productID != "free";

/**
 * Return true if the given {@link Subscription} is for a free plan.
 */
export const isSubscriptionFree = (subscription: Subscription) =>
    subscription.productID == "free";

/**
 * Return true if the given {@link Subscription} is active and for the given
 * {@link Plan}.
 */
export const isSubscriptionForPlan = (subscription: Subscription, plan: Plan) =>
    plan.stripeID === subscription.productID ||
    plan.iosID === subscription.productID ||
    plan.androidID === subscription.productID;

/**
 * Return true if the given {@link Subscription} is using Stripe.
 */
export const isSubscriptionStripe = (subscription: Subscription) =>
    subscription.paymentProvider == "stripe";

/**
 * Return true if the given {@link Subscription} has the cancelled attribute.
 */
export const isSubscriptionCancelled = (subscription: Subscription) =>
    subscription.attributes?.isCancelled;

/**
 * Return true if the user (represented by the given {@link userDetails}) is
 * part of a family plan.
 */
export const isPartOfFamily = (userDetails: UserDetails) =>
    (userDetails.familyData?.members.length ?? 0) > 0;

/**
 * Return true if the user (represented by the given {@link userDetails}) is
 * part of a family plan which has members in the family.
 */
export const isPartOfFamilyWithOtherMembers = (userDetails: UserDetails) =>
    (userDetails.familyData?.members.length ?? 0) > 1;

/**
 * Return true if the user (represented by the given {@link userDetails}) is the
 * admin for the family plan.
 */
export const isFamilyAdmin = (userDetails: UserDetails) =>
    userDetails.email == familyAdminEmail(userDetails);

/**
 * Return the member specific storage limit for the user (represented by the
 * given {@link userDetails}).
 */
export const familyMemberStorageLimit = (userDetails: UserDetails) =>
    userDetails.familyData?.members.find((m) => m.email == userDetails.email)
        ?.storageLimit;

/**
 * Return the email of the admin for the family plan, if any, that the user
 * (represented by the given {@link userDetails}) is a part of.
 */
export const familyAdminEmail = (userDetails: UserDetails) =>
    userDetails.familyData?.members.find((x) => x.isAdmin)?.email;

/**
 * Return the combined usage of all the family members.
 */
export const familyUsage = (userDetails: UserDetails) =>
    (userDetails.familyData?.members ?? []).reduce(
        (sum, { usage }) => sum + (usage ?? 0),
        0,
    );

/**
 * Update remote to indicate that the user wants to leave the family plan that
 * they are part of, then update our local user details by pulling the latest
 * ones from remote.
 */
export const leaveFamily = async () => {
    ensureOk(
        await fetch(await apiURL("/family/leave"), {
            method: "DELETE",
            headers: await authenticatedRequestHeaders(),
        }),
    );
    return pullUserDetails();
};

/**
 * Return true if the given {@link Subscription} has expired, and is also beyond
 * the grace period.
 */
export const isSubscriptionPastDue = (subscription: Subscription) => {
    const thirtyDaysMicroseconds = 30 * 24 * 60 * 60 * 1000 * 1000;
    const currentTime = Date.now() * 1000;
    return (
        !isSubscriptionCancelled(subscription) &&
        subscription.expiryTime < currentTime &&
        subscription.expiryTime >= currentTime - thirtyDaysMicroseconds
    );
};

/**
 * Return the bonuses whose type starts with "ADD_ON" applicable for the user
 * (represented by the given {@link userDetails}).
 */
export const userDetailsAddOnBonuses = (userDetails: UserDetails) =>
    userDetails.bonusData?.storageBonuses.filter((bonus) =>
        bonus.type.startsWith("ADD_ON"),
    ) ?? [];

/**
 * Return true if the user (represented by the given {@link userDetails}) has a
 * exceeded their storage quota (individual or of the family plan they are a
 * part of).
 */
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
