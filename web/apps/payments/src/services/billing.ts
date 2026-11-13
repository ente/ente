import { loadStripe } from "@stripe/stripe-js";

export const parseAndHandleRequest = async () => {
    if (window.location.pathname == "/desktop-redirect") {
        const desktopRedirectURL = new URL("ente://app/gallery");
        desktopRedirectURL.search = new URL(window.location.href).search;
        window.location.href = desktopRedirectURL.href;
        return;
    }

    try {
        const urlParams = new URLSearchParams(window.location.search);
        const paymentIntentClientSecret = urlParams.get(
            "payment_intent_client_secret",
        );
        const productID = urlParams.get("productID");
        const paymentToken = urlParams.get("paymentToken");
        const action = urlParams.get("action");
        const redirectURL = urlParams.get("redirectURL");
        const accountCountry = urlParams.get("accountCountry");

        if (paymentIntentClientSecret) {
            const pendingPaymentContext = getPendingPaymentContext();
            const clientRedirectURL =
                redirectURL ?? pendingPaymentContext?.redirectURL ?? null;
            const clientAccountCountry = isStripeAccountCountry(accountCountry)
                ? accountCountry
                : (pendingPaymentContext?.accountCountry ?? null);
            try {
                await handlePaymentIntentRedirect(
                    paymentIntentClientSecret,
                    clientAccountCountry,
                    clientRedirectURL,
                );
            } catch (error) {
                console.error(error);
                clearPendingPaymentContext();
                if (clientRedirectURL) {
                    redirectToApp(clientRedirectURL, "fail", "server_error");
                    return;
                }
                throw ensureError(error);
            }
            return;
        }

        if (!action && !paymentToken && !productID && !redirectURL) {
            console.log(
                "None of the required query parameters were supplied, redirecting to the ente.com",
            );
            redirectHome();
            return;
        }

        if (!action || !paymentToken || !productID || !redirectURL) {
            throw Error("Required query parameter was not provided");
        }

        switch (action) {
            case "buy":
                await buySubscription(productID, paymentToken, redirectURL);
                break;
            case "update":
                await updateSubscription(productID, paymentToken, redirectURL);
                break;
            default:
                throw Error(`Unsupported action ${action}`);
        }
    } catch (e) {
        console.error(e);
        throw ensureError(e);
    }
};

const apiOrigin = import.meta.env.VITE_ENTE_ENDPOINT ?? "https://api.ente.com";
const paymentIntentPollIntervalMs = 2_000;
const paymentIntentPollTimeoutMs = 300_000;
const pendingPaymentContextStorageKey = "ente.payments.pending-context";

type StripeJS = NonNullable<Awaited<ReturnType<typeof loadStripe>>>;

const ensureError = (error: unknown) =>
    error instanceof Error ? error : new Error(String(error));

type StripeAccountCountry = "US" | "IN";

interface PendingPaymentContext {
    accountCountry: StripeAccountCountry;
    redirectURL: string;
}

const isStripeAccountCountry = (c: unknown): c is StripeAccountCountry =>
    c == "US" || c == "IN";

const stripePublishableKey = (accountCountry: StripeAccountCountry) => {
    switch (accountCountry) {
        case "US":
            return (
                import.meta.env.VITE_STRIPE_US_PUBLISHABLE_KEY ??
                "pk_live_51LZ9P4G1ITnQlpAnrP6pcS7NiuJo3SnJ7gibjJlMRatkrd2EY1zlMVTVQG5RkSpLPbsHQzFfnEtgHnk1PiylIFkk00tC0LWXwi"
            );
        case "IN":
            return (
                import.meta.env.VITE_STRIPE_IN_PUBLISHABLE_KEY ??
                "pk_live_51HAhqDK59oeucIMOiTI6MDDM2UWUbCAJXJCGsvjJhiO8nYJz38rQq5T4iyQLDMKxqEDUfU5Hopuj4U5U4dff23oT00fHvZeodC"
            );
    }
};

const getUserStripeAccountCountry = async (paymentToken: string) => {
    const url = `${apiOrigin}/billing/stripe-account-country`;
    const res = await fetch(url, { headers: { "X-Auth-Token": paymentToken } });
    if (!res.ok) throw new Error(`Failed to fetch ${url}: HTTP ${res.status}`);
    const json: unknown = await res.json();
    if (json && typeof json === "object" && "stripeAccountCountry" in json) {
        const c = json.stripeAccountCountry;
        if (isStripeAccountCountry(c)) return c;
    }
    throw new Error(`Unexpected response for ${url}: ${JSON.stringify(json)}`);
};

const getStripe = async (
    redirectURL: string,
    accountCountry: StripeAccountCountry,
) => {
    const publishableKey = stripePublishableKey(accountCountry);
    try {
        const stripe = await loadStripe(publishableKey);
        if (!stripe) throw new Error("Failed to load Stripe");
        return stripe;
    } catch (e) {
        redirectToApp(redirectURL, "fail", "stripe_error");
        throw ensureError(e);
    }
};

const buySubscription = async (
    productID: string,
    paymentToken: string,
    redirectURL: string,
) => {
    try {
        const accountCountry = await getUserStripeAccountCountry(paymentToken);
        const stripe = await getStripe(redirectURL, accountCountry);
        const sessionId = await createCheckoutSession(
            productID,
            paymentToken,
            redirectURL,
        );
        await stripe.redirectToCheckout({ sessionId });
    } catch (e) {
        redirectToApp(redirectURL, "fail", "server_error");
        throw ensureError(e);
    }
};

const createCheckoutSession = async (
    productID: string,
    paymentToken: string,
    redirectURL: string,
): Promise<string> => {
    const params = new URLSearchParams({ productID, redirectURL });
    const url = `${apiOrigin}/billing/stripe/checkout-session?${params.toString()}`;
    const res = await fetch(url, { headers: { "X-Auth-Token": paymentToken } });
    if (!res.ok) throw new Error(`Failed to fetch ${url}: HTTP ${res.status}`);
    const json: unknown = await res.json();
    if (json && typeof json == "object" && "sessionID" in json) {
        const sid = json.sessionID;
        if (typeof sid == "string") return sid;
    }
    throw new Error(`Unexpected response for ${url}: ${JSON.stringify(json)}`);
};

const updateSubscription = async (
    productID: string,
    paymentToken: string,
    redirectURL: string,
) => {
    try {
        const accountCountry = await getUserStripeAccountCountry(paymentToken);
        const stripe = await getStripe(redirectURL, accountCountry);
        const { status, clientSecret } = await updateStripeSubscription(
            paymentToken,
            productID,
        );
        switch (status) {
            case "success": {
                redirectToApp(redirectURL, "success");
                return;
            }

            case "requires_payment_method":
                redirectToApp(redirectURL, "fail", "requires_payment_method");
                return;

            case "requires_action": {
                setPendingPaymentContext({ accountCountry, redirectURL });
                const result = await stripe.confirmPayment({
                    clientSecret,
                    confirmParams: {
                        return_url: stripeConfirmationReturnURL(
                            redirectURL,
                            accountCountry,
                        ),
                    },
                    redirect: "if_required",
                });
                if (result.error) {
                    clearPendingPaymentContext();
                    const { error } = result;
                    console.error("Failed to confirm payment", error);
                    if (error.type == "card_error") {
                        redirectToApp(
                            redirectURL,
                            "fail",
                            "requires_payment_method",
                        );
                    } else if (
                        error.type == "authentication_error" ||
                        error.code == "payment_intent_authentication_failure"
                    ) {
                        redirectToApp(
                            redirectURL,
                            "fail",
                            "authentication_failed",
                        );
                    } else {
                        redirectToApp(redirectURL, "fail");
                    }
                    return;
                }

                const status = await waitForTerminalPaymentIntentStatus(
                    stripe,
                    clientSecret,
                    result.paymentIntent.status,
                );
                clearPendingPaymentContext();
                redirectForPaymentIntentStatus(redirectURL, status);
                return;
            }
        }
    } catch (e) {
        redirectToApp(redirectURL, "fail", "server_error");
        throw ensureError(e);
    }
};

type PaymentStatus = "success" | "requires_action" | "requires_payment_method";

const isPaymentStatus = (s: unknown): s is PaymentStatus =>
    s == "success" || s == "requires_action" || s == "requires_payment_method";

interface UpdateStripeSubscriptionResponse {
    status: PaymentStatus;
    clientSecret: string;
}

const handlePaymentIntentRedirect = async (
    clientSecret: string,
    accountCountry: StripeAccountCountry | null,
    redirectURL: string | null,
) => {
    if (!accountCountry || !redirectURL) {
        throw new Error(
            "Required query parameter was not provided for payment confirmation",
        );
    }

    const stripe = await getStripe(redirectURL, accountCountry);
    const result = await stripe.retrievePaymentIntent(clientSecret);
    if (result.error) throw ensureError(result.error);
    const status = await waitForTerminalPaymentIntentStatus(
        stripe,
        clientSecret,
        result.paymentIntent.status,
    );
    clearPendingPaymentContext();
    redirectForPaymentIntentStatus(redirectURL, status);
};

const waitForTerminalPaymentIntentStatus = async (
    stripe: StripeJS,
    clientSecret: string,
    initialStatus: string,
) => {
    let status = initialStatus;
    const deadline = Date.now() + paymentIntentPollTimeoutMs;

    while (status == "processing" && Date.now() < deadline) {
        await delay(paymentIntentPollIntervalMs);
        const result = await stripe.retrievePaymentIntent(clientSecret);
        if (result.error) throw ensureError(result.error);
        status = result.paymentIntent.status;
    }

    return status;
};

const delay = (ms: number) =>
    new Promise((resolve) => {
        setTimeout(resolve, ms);
    });

const stripeConfirmationReturnURL = (
    redirectURL: string,
    accountCountry: StripeAccountCountry,
) => {
    const url = new URL(window.location.href);
    url.searchParams.delete("paymentToken");
    url.searchParams.delete("productID");
    url.searchParams.delete("action");
    url.searchParams.set("redirectURL", redirectURL);
    url.searchParams.set("accountCountry", accountCountry);
    return url.href;
};

const getPendingPaymentContext = (): PendingPaymentContext | null => {
    try {
        const value = sessionStorage.getItem(pendingPaymentContextStorageKey);
        if (!value) return null;
        const json: unknown = JSON.parse(value);
        if (
            json &&
            typeof json == "object" &&
            "accountCountry" in json &&
            "redirectURL" in json &&
            isStripeAccountCountry(json.accountCountry) &&
            typeof json.redirectURL == "string"
        ) {
            return {
                accountCountry: json.accountCountry,
                redirectURL: json.redirectURL,
            };
        }
    } catch (error) {
        console.error("Failed to read pending payment context", error);
    }

    return null;
};

const setPendingPaymentContext = (context: PendingPaymentContext) => {
    try {
        sessionStorage.setItem(
            pendingPaymentContextStorageKey,
            JSON.stringify(context),
        );
    } catch (error) {
        console.error("Failed to persist pending payment context", error);
    }
};

const clearPendingPaymentContext = () => {
    try {
        sessionStorage.removeItem(pendingPaymentContextStorageKey);
    } catch (error) {
        console.error("Failed to clear pending payment context", error);
    }
};

const redirectForPaymentIntentStatus = (
    redirectURL: string,
    status: string,
) => {
    switch (status) {
        case "succeeded":
            redirectToApp(redirectURL, "success");
            return;
        case "processing":
            redirectToApp(redirectURL, "fail", "server_error");
            return;
        case "requires_payment_method":
            redirectToApp(redirectURL, "fail", "requires_payment_method");
            return;
        case "requires_action":
            redirectToApp(redirectURL, "fail", "authentication_failed");
            return;
        case "canceled":
            redirectToApp(redirectURL, "fail", "canceled");
            return;
        default:
            console.error("Unhandled PaymentIntent status", status);
            redirectToApp(redirectURL, "fail");
    }
};

async function updateStripeSubscription(
    paymentToken: string,
    productID: string,
): Promise<UpdateStripeSubscriptionResponse> {
    const url = `${apiOrigin}/billing/stripe/update-subscription`;
    const res = await fetch(url, {
        method: "POST",
        headers: { "X-Auth-Token": paymentToken },
        body: JSON.stringify({ productID }),
    });
    if (!res.ok) throw new Error(`Failed to fetch ${url}: HTTP ${res.status}`);
    const json: unknown = await res.json();
    if (json && typeof json == "object" && "result" in json) {
        const result = json.result;
        if (
            result &&
            typeof result == "object" &&
            "status" in result &&
            "clientSecret" in result
        ) {
            const status = result.status;
            const clientSecret = result.clientSecret;
            if (isPaymentStatus(status) && typeof clientSecret == "string") {
                return { status, clientSecret };
            }
        }
    }
    throw new Error(`Unexpected response for ${url}: ${JSON.stringify(json)}`);
}

type RedirectStatus = "success" | "fail";

type FailureReason =
    | "authentication_failed"
    | "requires_payment_method"
    | "stripe_error"
    | "canceled"
    | "server_error";

const isEnteHostname = (hostname: string) =>
    hostname.endsWith(".ente.com") ||
    hostname.endsWith(".ente.io") ||
    hostname.endsWith(".ente.sh");

// Assigning window.location.href does not stop script execution; statements
// after a redirect still run, so callers must return explicitly.
const redirectToApp = (
    redirectURL: string,
    status: RedirectStatus,
    reason?: FailureReason,
) => {
    let url = new URL(redirectURL);
    if (url.protocol != "http:" && url.protocol != "https:") {
        throw new Error("Invalid payment redirect URL");
    }

    const isSameOrigin = url.origin == window.location.origin;
    const isDevURL =
        import.meta.env.DEV && url.hostname == window.location.hostname;
    const isEnteURL =
        url.protocol == "https:" &&
        url.port == "" &&
        isEnteHostname(url.hostname);
    const isAllowedURL = isSameOrigin || isDevURL || isEnteURL;
    if (!isAllowedURL) {
        throw new Error("Invalid payment redirect URL");
    }

    if (isSameOrigin && url.pathname == "/desktop-redirect") {
        url = new URL("ente://app/gallery");
    }

    url.searchParams.set("status", status);
    if (reason) url.searchParams.set("reason", reason);
    else url.searchParams.delete("reason");
    window.location.href = url.href;
};

const redirectHome = () => {
    window.location.href = "https://ente.com";
};
