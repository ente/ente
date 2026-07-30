/**
 * Forward a tunneled request from our clients to our Sentry instance.
 *
 * The client use a Sentry "tunnel" that connects to where this worker listens.
 * Requests to this tunnel endpoint contain the original crash report wrapped in
 * an envelope. This worker extracts the original Sentry request from the
 * envelope, forwards it our Sentry instance, and proxies back the response.
 *
 * It also replaces the replace the DSN in the POST body with the latest one.
 * This allows us to hardcode the DSN in the clients, without needing to update
 * them if the DSN changes on our self-hosted Sentry's side (e.g. if we recreate
 * these projects from scratch in the Sentry instance).
 */
export default {
    async fetch(request: Request) {
        switch (request.method) {
            case "POST":
                return handlePOST(request);
            default:
                return new Response(null, { status: 405 });
        }
    },
} satisfies ExportedHandler;

const handlePOST = async (request: Request) => {
    const originalBody = await request.text();
    const originalDSNString = extractDSN(originalBody);
    const { body, dsn } = mapDSN(originalBody, originalDSNString);
    if (!isEnteSentryDSN(dsn)) return new Response(null, { status: 400 });

    const projectId = parseInt(dsn.pathname?.slice(1)?.split("/")[0] ?? "1");

    // Proxy request to Sentry ingest
    return fetch(`https://${dsn.host}/api/${projectId}/envelope/`, {
        method: "POST",
        headers: {
            "Content-Type": "application/octet-stream",
        },
        body,
    });
};

/** Parse the POST body sent by Sentry client to extract the DSN therein */
const extractDSN = (body: string) => {
    // The body consists of 3 lines, each a JSON string. The first line is the
    // envelope header.
    const [envelopeHeaderString] = body.split("\n", 1);
    if (!envelopeHeaderString) throw new Error(`Missing DSN`);
    const envelopeHeader = JSON.parse(envelopeHeaderString ?? "");
    const dsn = envelopeHeader["dsn"];
    if (typeof dsn !== "string") throw new Error(`Unexpected DSN ${dsn}`);
    return dsn;
};

/**
 * If {@link originalDSNString} matches one of the known DSNs that we want to
 * map, perform a textual search and replace of the DSN and public_key fields in
 * the body of the request.
 *
 * @returns the (possibly) modified body and DSN.
 */
const mapDSN = (originalBody: string, originalDSNString: string) => {
    const originalDSN = new URL(originalDSNString);

    const dsnString = dsnMappings[originalDSNString];
    if (dsnString === undefined) {
        // We don't have a mapping for this DSN, return the originals unchanged.
        return { body: originalBody, dsn: originalDSN };
    }

    const dsn = new URL(dsnString);

    // Extract the public_key part from the URLs. We need to do two
    // substitutions, first for the entire DSN, and then for the public key.
    const originalPublicKey = originalDSN.username;
    const publicKey = dsn.username;

    let body = originalBody.replaceAll(originalDSNString, dsnString);
    if (originalPublicKey) {
        body = body.replaceAll(originalPublicKey, publicKey);
    }

    return { body, dsn };
};

const isEnteSentryDSN = (dsn: URL) =>
    dsn.protocol === "https:" &&
    (dsn.host === "sentry.ente.com" || dsn.host === "sentry.ente.io");

const dsnMappings: Record<string, string> = {
    // photos-mobile
    "https://2235e5c99219488ea93da34b9ac1cb68@sentry.ente.io/4":
        "https://1b13ae41ee7c898ce3c49d04781eb908@sentry.ente.io/2",

    // photos-mobile-debug
    // Nb: Maps to the same project in Sentry.
    "https://ca5e686dd7f149d9bf94e620564cceba@sentry.ente.io/3":
        "https://1b13ae41ee7c898ce3c49d04781eb908@sentry.ente.io/2",

    // auth-mobile
    "https://ed4ddd6309b847ba8849935e26e9b648@sentry.ente.io/9":
        "https://47c2aa45d5e359ada9f5fe3c44c98f12@sentry.ente.io/3",
};
