const partBytes = 16 * 1024 * 1024;

const editorOrigins = new Set(["https://photobook.ente.com", "http://localhost:3014", "http://127.0.0.1:3014"]);
const textEncoder = new TextEncoder();

async function hmacKey(secret) {
    return crypto.subtle.importKey("raw", textEncoder.encode(secret),
        { name: "HMAC", hash: "SHA-256" }, false, ["sign", "verify"]);
}

async function sign(secret, message) {
    const bytes = new Uint8Array(await crypto.subtle.sign(
        "HMAC", await hmacKey(secret), textEncoder.encode(message)));
    return Array.from(bytes, b => b.toString(16).padStart(2, "0")).join("");
}

async function validSignature(secret, message, signature) {
    if (!/^[a-f0-9]{64}$/.test(signature || "")) return false;
    const bytes = Uint8Array.from(signature.match(/../g), hex => parseInt(hex, 16));
    return crypto.subtle.verify("HMAC", await hmacKey(secret), bytes, textEncoder.encode(message));
}

function downloadMessage(url, key, expires) {
    return ["read-pdf", url.origin, url.pathname, key, expires].join("\n");
}

const orderLinkSeconds = 7 * 24 * 60 * 60;

async function signedLink(origin, secret, id) {
    const url = new URL("/prodigi-source/books/" + id + ".pdf", origin);
    const expires = String(Math.floor(Date.now() / 1000) + orderLinkSeconds);
    url.searchParams.set("expires", expires);
    url.searchParams.set("sig", await sign(secret, downloadMessage(url, "books/" + id + ".pdf", expires)));
    return url.href;
}

async function download(request, env, url, id) {
    if (!["GET", "HEAD"].includes(request.method)) return new Response(null, {status:405});
    const expires = url.searchParams.get("expires");
    const key = "books/" + id + ".pdf";
    const secret = env.BOOK_SECRET;
    if (!secret || !/^\d{10}$/.test(expires || "") || Number(expires) <= Date.now() / 1000 ||
        !await validSignature(secret, downloadMessage(url, key, expires), url.searchParams.get("sig"))) {
        return new Response("Invalid or expired download link.", {status:403, headers: {"Cache-Control":"no-store"}});
    }
    const headers = new Headers({
        "Content-Type": "application/pdf", "Accept-Ranges": "bytes",
        "Cache-Control": "private, no-store", "Referrer-Policy": "no-referrer",
        "Content-Disposition": 'inline; filename="photobook.pdf"',
    });
    const metadata = await env.BOOKS.head(key);
    if (!metadata) return new Response("PDF missing.", {status:404});
    const size = metadata.size;
    const range = request.method === "GET" && request.headers.get("Range");
    let options;
    if (range) {
        const match = /^bytes=(\d*)-(\d*)$/i.exec(range);
        const start = match && match[1] ? Number(match[1]) :
            Math.max(0,size - Number(match?.[2]));
        const end = match && match[1] && match[2] ?
            Math.min(size - 1, Number(match[2])) : size - 1;
        if (!match || !(match[1] || match[2]) || !Number.isSafeInteger(start) ||
            start < 0 || start > end) {
            headers.set("Content-Range", "bytes */" + size);
            return new Response(null, {status:416, headers});
        }
        options = {range: {offset:start, length:end - start + 1}};
        headers.set("Content-Range", "bytes " + start + "-" + end + "/" + size);
    }
    const object = request.method === "HEAD" ? metadata : await env.BOOKS.get(key, options);
    if (!object || object.size !== size) return new Response("PDF missing.", {status:404});
    headers.set("Content-Length", String(options?.range.length ?? object.size));
    headers.set("ETag", object.httpEtag);
    return new Response(object.body ?? null, {headers, status:options ? 206 : 200});
}

const products = new Map([
    ["layflat", { sku: "BOOK-FE-8_3-SQ-LF-G", minPages: 24, price: "99.00" }],
    ["softcover", { sku: "BOOK-FE-8_3-SQ-SOFT-G", minPages: 24, price: "49.00" }],
]);
const orderApi = "https://api.prodigi.com/v5/orders";

function variantIdFor(cover, env) {
    return cover === "layflat" ? env.SHOPIFY_LAYFLAT_VARIANT_ID : env.SHOPIFY_SOFTCOVER_VARIANT_ID;
}

function validPageCount(product, pages) {
    return product && Number.isInteger(pages) && pages >= product.minPages && pages <= 100 && pages % 2 === 0;
}

function validDestination(destination) {
    return typeof destination?.countryCode === "string" && /^[A-Z]{2}$/.test(destination.countryCode) &&
        typeof destination.postalCode === "string" && destination.postalCode.length <= 20;
}

async function checkDelivery(request, env) {
    const input = await request.json().catch(() => null);
    const product = products.get(input?.cover);
    if (!validPageCount(product, input?.pages) || !validDestination(input?.destination)) {
        return new Response("Check the book and delivery details.", { status: 400 });
    }
    const { countryCode, postalCode } = input.destination;
    const unavailable = () => new Response("Standard delivery is unavailable for this book at this destination.", { status: 422 });
    const response = await fetch("https://api.prodigi.com/v5/quotes/shipping", {
        method: "POST", redirect: "manual", signal: AbortSignal.timeout(60000),
        headers: { "Content-Type": "application/json", "X-API-Key": env.PRODIGI_LIVE_KEY },
        body: JSON.stringify({
            destination: { countryCode, postalOrZipCode: postalCode.trim() || undefined },
            items: [{ catalogueVariantId: product.sku, quantity: 1,
                assets: [{ printArea: "default", pageCount: input.pages }] }],
        }),
    });
    const quote = await response.json();
    if (response.status === 422 && quote.type === "quote_unavailable") return unavailable();
    if (!response.ok || !Array.isArray(quote.data?.options)) {
        return new Response("Couldn’t check delivery right now. Please try again.", { status: 503 });
    }
    return quote.data.options.some(option => option.method?.toLowerCase() === "standard")
        ? new Response(null, { status: 204 }) : unavailable();
}

function printItem(sku, pdfUrl, book) {
    return {
        sku, quantity: 1,
        assets: [{ printArea: "default", url: pdfUrl, pageCount: book.pages }],
        spineDetails: { dynamicSpineDetails: {
            spineText: book.title || undefined, spineTextFont: "Brandon", spineTextSize: 20,
            spineTextColor: "#000000", spineColorHex: "#FFFFFF",
        } },
    };
}

async function shopifyAdmin(env) {
    const shop = env.SHOPIFY_SHOP_DOMAIN?.trim();
    if (!/^[a-z0-9][a-z0-9-]*\.myshopify\.com$/.test(shop ?? "") || !env.SHOPIFY_CLIENT_ID || !env.SHOPIFY_CLIENT_SECRET) {
        throw new Error("Check the Shopify domain and app credentials in the Worker settings.");
    }
    const auth = await fetch("https://" + shop + "/admin/oauth/access_token", {
        method: "POST", redirect: "manual", signal: AbortSignal.timeout(15000),
        body: new URLSearchParams({ grant_type: "client_credentials", client_id: env.SHOPIFY_CLIENT_ID,
            client_secret: env.SHOPIFY_CLIENT_SECRET }),
    });
    if (!auth.ok) throw new Error("Shopify authentication HTTP " + auth.status + ". Check the app installation and credentials.");
    const { access_token } = await auth.json();
    if (!access_token) throw new Error("Shopify returned no access token.");
    return async (query, variables) => {
        const result = await fetch("https://" + shop + "/admin/api/2026-10/graphql.json", {
            method: "POST", redirect: "manual", signal: AbortSignal.timeout(15000),
            headers: { "Content-Type": "application/json", "X-Shopify-Access-Token": access_token },
            body: JSON.stringify({ query, variables }),
        });
        if (!result.ok) throw new Error("Shopify Admin API HTTP " + result.status);
        const { data, errors } = await result.json();
        if (errors?.length) throw new Error(errors.map(error => error.message).join("\n"));
        return data;
    };
}

const fulfillmentQuery = `query OrderForShipment($id: ID!) {
    order(id: $id) {
        name cancelledAt displayFinancialStatus
        lineItems(first: 2) { nodes { id currentQuantity variant { id } customAttributes { key value } } }
        fulfillmentOrders(first: 20) { nodes {
            id supportedActions { action }
            lineItems(first: 2) { nodes { id remainingQuantity lineItem { id } } }
        } }
        fulfillments(first: 20) {
            id status trackingInfo { company number url }
            fulfillmentLineItems(first: 2) { nodes { lineItem { id } } }
        }
    }
}`;

async function readDispatch(receipt, key) {
    const url = new URL("https://api.prodigi.com/v4.0/orders");
    url.searchParams.set("merchantReferences", receipt.reference);
    url.searchParams.set("top", "2");
    const response = await fetch(url, {
        headers: { "X-API-Key": key.slice("live_".length), Accept: "application/json" },
        redirect: "manual", signal: AbortSignal.timeout(15000),
    });
    if (!response.ok) throw new Error("Prodigi fulfillment lookup returned HTTP " + response.status + ".");
    const { orders, hasMore } = await response.json();
    if (!Array.isArray(orders)) throw new Error("Prodigi did not return a fulfillment order list.");
    if (!orders.length) return;
    const [order] = orders;
    if (hasMore || orders.length !== 1 || order.merchantReference !== receipt.reference ||
        order.items?.length !== 1 || order.items[0].sku?.toUpperCase() !== receipt.sku || order.items[0].copies !== 1) {
        throw new Error("Fulfillment order does not uniquely match the receipt.");
    }
    const shipped = (order.shipments ?? []).filter(s => s.status !== "Cancelled" &&
        (s.status === "Shipped" || s.dispatchDate) &&
        (!s.items?.length || s.items.some(i => i.itemId === order.items[0].id)));
    if (shipped.length > 1) throw new Error("Multiple dispatched shipments for the book.");
    return shipped[0];
}

async function syncOneShipment(env, prefix, bookId, receipt, priorFulfillmentId, event) {
    const ticket = await (await env.BOOKS.get(prefix + "draft.json")).json();
    const key = env.PRODIGI_LIVE_KEY?.trim();
    if (!/^live_\S+$/.test(key ?? "")) throw new Error("Shipment sync requires PRODIGI_LIVE_KEY.");
    const expectedSku = products.get(ticket.cover)?.sku;
    if (ticket.shop !== env.SHOPIFY_SHOP_DOMAIN?.trim() || expectedSku !== receipt.sku ||
        receipt.reference !== "ente-shopify-" + receipt.shopifyOrderId) throw new Error("Mismatched receipt.");
    const result = await fetch(orderApi + "/" + encodeURIComponent(receipt.prodigiOrderId), {
        headers: { "X-API-Key": key, Accept: "application/json" }, redirect: "manual", signal: AbortSignal.timeout(15000),
    });
    if (!result.ok) throw new Error("Prodigi order " + receipt.prodigiOrderId + " returned HTTP " + result.status);
    const { data: printed } = await result.json();
    const item = printed?.items?.[0];
    if (printed?.id !== receipt.prodigiOrderId || printed.merchantReference !== receipt.reference ||
        printed.items?.length !== 1 || item.sku !== receipt.sku || item.quantity !== 1) {
        throw new Error("Prodigi order does not match the R2 receipt.");
    }
    const label = "Prodigi " + printed.id;
    if (["cancelled", "failed"].includes(printed.status)) return { done: true, message: label + " is " + printed.status + "." };
    const parcels = (printed.shipments ?? []).filter(s => s.status !== "cancelled" &&
        (!s.items?.length || s.items.some(i => i.itemId === item.id)));
    const shipped = parcels.filter(s => s.dispatchedAt || s.deliveredAt ||
        ["dispatched", "in_transit", "shipped", "delivered"].includes(s.status));
    const wholeOrderShipped = ["shipped", "completed"].includes(printed.status);
    if (shipped.length > 1 || (!shipped.length && parcels.length > 1)) throw new Error(label + " has multiple parcels for one book. Check the order.");
    const parcel = shipped[0] ?? parcels[0];
    const dispatched = wholeOrderShipped || shipped.length > 0;
    const needsTracking = (dispatched && (!parcel?.trackingNumber || !parcel?.trackingUrl)) ||
        (event?.trackingNumber && event.trackingNumber !== parcel?.trackingNumber) ||
        (event?.trackingUrl && event.trackingUrl !== parcel?.trackingUrl);
    const fulfillmentShipment = (needsTracking || (event?.dispatch && !dispatched))
        ? await readDispatch(receipt, key) : undefined;
    if (!dispatched && !fulfillmentShipment) {
        if (event?.dispatch) throw new Error("Dispatch callback arrived before the order showed dispatch.");
        const artwork = item.assets?.find(asset => asset.printArea === "default")?.status ?? "unknown";
        const issueCodes = (printed.issues ?? []).map(issue => issue.code ?? "unspecified");
        const message = [label + " is " + printed.status + ". Awaiting dispatch.", "Artwork: " + artwork,
            "Shipments: " + parcels.length, "Issues: " + (issueCodes.join(", ") || "none reported")].join(" · ");
        return { done: false, message };
    }
    const number = fulfillmentShipment?.tracking?.number || parcel?.trackingNumber;
    const sameNumber = number && number === parcel?.trackingNumber;
    const tracking = number ? { number } : null;
    const carrier = fulfillmentShipment?.carrier?.name || (sameNumber && parcel.carrier);
    const carrierUrl = (fulfillmentShipment?.tracking?.number === number && fulfillmentShipment?.tracking?.url) ||
        (sameNumber && parcel.trackingUrl);
    if (tracking && carrier) tracking.company = carrier;
    if (tracking && /^https?:\/\//i.test(carrierUrl || "")) tracking.url = carrierUrl;
    if ((event?.trackingNumber && !tracking) || (event?.trackingUrl && !tracking?.url)) {
        throw new Error(label + " has not exposed the callback's tracking number or link on its authenticated order lookups yet.");
    }

    const query = await shopifyAdmin(env);
    const { order } = await query(fulfillmentQuery, { id: "gid://shopify/Order/" + receipt.shopifyOrderId });
    if (!order) throw new Error("Shopify did not return the order. Check read_orders access.");
    if (order.cancelledAt) return { done: true, message: "Shopify " + order.name + " was cancelled." };
    const lines = order.lineItems.nodes;
    const attrs = new Map((lines[0]?.customAttributes ?? []).map(a => [a.key, a.value]));
    if (order.displayFinancialStatus !== "PAID" ||
        lines.length !== 1 || lines[0].currentQuantity !== 1 ||
        attrs.get("_book_id") !== bookId || attrs.get("Pages") !== String(receipt.pages) ||
        lines[0].variant?.id !== ticket.variantId) {
        throw new Error("Shopify " + order.name + " no longer matches the paid book.");
    }
    const lineId = lines[0].id;
    const existing = order.fulfillments.filter(f => f.status !== "CANCELLED" &&
        f.fulfillmentLineItems.nodes.some(l => l.lineItem.id === lineId));
    if (existing.length > 1) throw new Error("Review multiple fulfillments for Shopify " + order.name + ".");
    let fulfillment = existing[0];
    let change;
    if (!fulfillment) {
        if (priorFulfillmentId) throw new Error("Previously recorded Shopify fulfillment is not visible for " + order.name + ".");
        const eligible = order.fulfillmentOrders.nodes.filter(f => f.supportedActions.some(a => a.action === "CREATE_FULFILLMENT"));
        const candidates = eligible.flatMap(f => f.lineItems.nodes.filter(l =>
            l.lineItem.id === lineId && l.remainingQuantity === 1).map(l => ({
                fulfillmentOrderId: f.id, fulfillmentOrderLineItems: [{ id: l.id, quantity: 1 }],
            })));
        if (candidates.length !== 1) throw new Error("No single fulfillable book line for " + order.name + ". Check its assigned location, holds, and the app's merchant-managed fulfillment permission.");
        const input = { lineItemsByFulfillmentOrder: candidates, notifyCustomer: true };
        if (tracking) input.trackingInfo = tracking;
        const data = await query(`mutation ShipBook($input: FulfillmentInput!) {
            fulfillmentCreate(fulfillment: $input) { fulfillment { id } userErrors { message } }
        }`, { input });
        change = data.fulfillmentCreate;
    } else {
        if (fulfillment.status !== "SUCCESS") throw new Error("Shopify fulfillment for " + order.name + " is " + fulfillment.status + ".");
        const current = fulfillment.trackingInfo.find(t => t.number === tracking?.number);
        if (tracking && (!current || (tracking.url && current.url !== tracking.url) ||
            (tracking.company && current.company?.toLowerCase() !== tracking.company.toLowerCase()))) {
            const data = await query(`mutation TrackBook($id: ID!, $tracking: FulfillmentTrackingInput!) {
                fulfillmentTrackingInfoUpdate(fulfillmentId: $id, trackingInfoInput: $tracking, notifyCustomer: true) {
                    fulfillment { id } userErrors { message }
                }
            }`, { id: fulfillment.id, tracking });
            change = data.fulfillmentTrackingInfoUpdate;
        }
    }
    if (change) {
        if (change.userErrors.length) throw new Error(change.userErrors.map(e => e.message).join("\n"));
        fulfillment = change.fulfillment;
    }
    if (!fulfillment?.id) throw new Error("Shopify did not confirm fulfillment for " + order.name + ".");
    const terminal = printed.status === "completed" || parcel?.status === "delivered" || Boolean(parcel?.deliveredAt);
    return {
        done: terminal || Boolean(tracking?.url),
        fulfillmentId: fulfillment.id,
        message: "Shopify " + order.name + " fulfilled · " + label + (tracking ?
            " · Tracking " + tracking.number : " · No carrier tracking number supplied."),
    };
}

async function syncShipment(env, bookId, receipt, event) {
    const prefix = "orders/" + bookId + "/";
    const stateKey = prefix + "shipment-sync.json";
    const prior = await env.BOOKS.get(stateKey);
    const state = prior ? await prior.json() : {};
    if (event && event.id === state.lastEventId) return state;
    if (state.until > Date.now()) return { busy: true, message: "Shipment check in progress." };
    const lease = await env.BOOKS.put(stateKey, JSON.stringify({
        ...state, until: Date.now() + 180000, run: crypto.randomUUID(),
    }), { onlyIf: prior ? { etagMatches: prior.etag } : new Headers({ "If-None-Match": "*" }) });
    if (!lease) return { busy: true, message: "Shipment check in progress." };
    let next;
    try {
        next = await syncOneShipment(env, prefix, bookId, receipt, state.fulfillmentId, event);
    } catch (error) {
        await env.BOOKS.put(stateKey, JSON.stringify({ ...state, until: 0 }), { onlyIf: { etagMatches: lease.etag } });
        throw error;
    }
    next.lastEventId = event?.id ?? state.lastEventId;
    next.fulfillmentId ??= state.fulfillmentId;
    const saved = await env.BOOKS.put(stateKey, JSON.stringify(next), { onlyIf: { etagMatches: lease.etag } });
    if (!saved) throw new Error("Shipment check changed concurrently. Retry this check.");
    return next;
}

async function prodigiCallback(request, env, bookId, url) {
    if (request.method !== "POST") return new Response(null, { status: 405, headers: { Allow: "POST" } });
    if (!env.BOOK_SECRET) return new Response("Missing signing secret.", { status: 503 });
    if (!await validSignature(env.BOOK_SECRET, "prodigi-callback:" + bookId, url.searchParams.get("sig"))) {
        return new Response("Invalid callback signature.", { status: 403 });
    }
    let body;
    try { body = await request.json(); }
    catch { return new Response("Invalid callback JSON.", { status: 400 }); }
    if (typeof body?.id !== "string" || !body.id || typeof body.type !== "string" || !body.type.startsWith("com.prodigi.")) {
        return new Response("Expected a Prodigi CloudEvent.", { status: 400 });
    }
    const reported = body.data?.order;
    const parcels = Array.isArray(reported?.shipments) ? reported.shipments : [];
    const tracking = parcels.find(s => s?.status !== "Cancelled" && s?.tracking?.number)?.tracking;
    await env.EVENTS.send({
        type: "shipment", bookId, reference: reported?.merchantReference,
        event: {
            id: body.id,
            dispatch: body.type === "com.prodigi.order.shipments.shipment#Complete" ||
                body.type === "com.prodigi.order.status.stage.changed#Complete" || parcels.some(s => s?.dispatchDate),
            trackingNumber: tracking?.number, trackingUrl: tracking?.url,
        },
    });
    return new Response(null, { status: 204 });
}

const uuid = /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/;
const maxBytes = 2 * 1024 ** 3;
const createOnly = () => new Headers({ "If-None-Match": "*" });

function ready(env, cover) {
    return env.BOOKS && env.EVENTS && env.PUBLIC_ORIGIN && env.BOOK_SECRET && env.SHOPIFY_WEBHOOK_SECRET &&
        env.SHOPIFY_CLIENT_ID && env.SHOPIFY_CLIENT_SECRET && env.SHOPIFY_SHOP_DOMAIN &&
        /^live_\S+$/.test(env.PRODIGI_LIVE_KEY ?? "") &&
        /^\d+$/.test(variantIdFor(cover, env) ?? "");
}

async function startUpload(request, env) {
    const book = await request.json().catch(() => null);
    if (!validPageCount(products.get(book?.cover), book?.pages) ||
        !Number.isSafeInteger(book.bytes) || book.bytes < 5 || book.bytes > maxBytes ||
        typeof book.title !== "string" || !book.title.trim() || [...book.title].length > 150) {
        return new Response("Check the spine title, page count and PDF size (up to 2 GiB).", { status: 400 });
    }
    if (!ready(env, book.cover)) return new Response("Checkout is unavailable for this cover.", { status: 503 });
    const id = crypto.randomUUID();
    const upload = await env.BOOKS.createMultipartUpload("books/" + id + ".pdf", {
        httpMetadata: { contentType: "application/pdf" },
        customMetadata: { cover: book.cover, pages: String(book.pages), bytes: String(book.bytes), title: encodeURIComponent(book.title.trim()) },
    });
    const claim = [Math.floor(Date.now() / 1000) + 86400, book.bytes].join(".");
    const signature = await sign(env.BOOK_SECRET, ["upload", id, claim].join("\n"));
    return Response.json({ id, uploadId: upload.uploadId, token: claim + "." + signature });
}

async function uploads(request, env, url) {
    if (url.pathname === "/uploads" && request.method === "POST") return startUpload(request, env);
    const match = /^\/uploads\/([\da-f-]{36})(\/checkout)?$/.exec(url.pathname);
    if (!match || !uuid.test(match[1])) return new Response(null, { status: 404 });
    const [, id, checkout] = match;
    const token = request.headers.get("X-Upload-Token") ?? "";
    const [expires, bytes, signature] = token.split(".");
    if (Number(expires) <= Date.now() / 1000 || !await validSignature(env.BOOK_SECRET,
        ["upload", id, expires + "." + bytes].join("\n"), signature)) {
        return new Response("Upload session expired. Reopen checkout to upload again.", { status: 403 });
    }
    if (checkout && request.method === "POST") {
        const destination = request.body ? await request.json().catch(() => null) : undefined;
        if (destination !== undefined && !validDestination(destination)) {
            return new Response("Check the delivery details.", { status: 400 });
        }
        return openCheckout(env, id, destination);
    }
    const uploadId = url.searchParams.get("uploadId");
    if (checkout || !uploadId) return new Response(null, { status: 400 });
    const key = "books/" + id + ".pdf";
    const upload = env.BOOKS.resumeMultipartUpload(key, uploadId);
    const count = Math.ceil(Number(bytes) / partBytes);
    if (request.method === "PUT") {
        const n = Number(url.searchParams.get("part"));
        const length = Math.min(partBytes, Number(bytes) - (n - 1) * partBytes);
        if (!Number.isInteger(n) || n < 1 || n > count || !request.body || Number(request.headers.get("Content-Length")) !== length) {
            return new Response("Invalid upload part.", { status: 400 });
        }
        return Response.json(await upload.uploadPart(n, request.body));
    }
    if (request.method === "DELETE") {
        await upload.abort();
        return new Response(null, { status: 204 });
    }
    if (request.method !== "POST") return new Response(null, { status: 405 });
    const parts = await request.json().catch(() => null);
    if (!Array.isArray(parts) || parts.length !== count || parts.some((p, i) => p?.partNumber !== i + 1 || typeof p.etag !== "string")) {
        return new Response("Incomplete upload.", { status: 400 });
    }
    let object;
    try {
        object = await upload.complete(parts);
    } catch (error) {
        object = await env.BOOKS.head(key);
        if (!object) throw error;
    }
    return Response.json({ bytes: object.size });
}

async function openCheckout(env, id, destination) {
    const key = "orders/" + id + "/draft.json";
    const previous = await env.BOOKS.get(key);
    const draft = previous && await previous.json();
    if (draft?.checkout) return Response.json({ checkout: draft.checkout });
    if (draft?.until > Date.now()) return new Response("Checkout is being prepared. Try again shortly.", { status: 409 });
    const pdf = await env.BOOKS.get("books/" + id + ".pdf", { range: { suffix: 32768 } });
    const meta = pdf?.customMetadata;
    const product = products.get(meta?.cover);
    const pages = Number(meta?.pages);
    if (!pdf || pdf.size !== Number(meta?.bytes) || !validPageCount(product, pages)) {
        return new Response("Upload the complete photobook before checkout.", { status: 409 });
    }
    const tail = new Uint8Array(await pdf.arrayBuffer());
    const end = new TextDecoder("latin1").decode(tail);
    const tailOffset = pdf.size - tail.byteLength;
    const xref = /startxref\n(\d+)\n%%EOF\s*$/.exec(end);
    const tableOffset = Number(xref?.[1]) - tailOffset;
    const table = tableOffset >= 0 ? /^xref\n0 \d+\n0000000000 65535 f \n\d{10} 00000 n \n(\d{10}) 00000 n /.exec(end.slice(tableOffset)) : null;
    const pageOffset = Number(table?.[1] ?? NaN) - tailOffset;
    const tree = /^2 0 obj\n<< \/Type \/Pages \/Kids \[([\d R]+)\] \/Count (\d+) >>\nendobj/.exec(pageOffset >= 0 ? end.slice(pageOffset) : "");
    if (Number(tree?.[2]) !== pages || tree[1].split(" 0 R").length - 1 !== pages) {
        return new Response("The exported PDF page count does not match this book. Export it again.", { status: 422 });
    }
    if (!ready(env, meta.cover)) return new Response("Checkout is unavailable for this cover.", { status: 503 });
    const lease = await env.BOOKS.put(key, JSON.stringify({ until: Date.now() + 90000 }), {
        onlyIf: previous ? { etagMatches: previous.etag } : createOnly(),
    });
    if (!lease) return new Response("Checkout is being prepared. Try again shortly.", { status: 409 });
    try {
        const variantId = "gid://shopify/ProductVariant/" + variantIdFor(meta.cover, env);
        const query = await shopifyAdmin(env);
        const { draftOrderCreate } = await query(`mutation PhotobookCheckout($input: DraftOrderInput!) {
            draftOrderCreate(input: $input) { draftOrder { id invoiceUrl } userErrors { message } }
        }`, { input: {
            presentmentCurrencyCode: "USD", tags: ["ente-photobook"],
            shippingAddress: destination && { countryCode: destination.countryCode, zip: destination.postalCode || undefined },
            allowDiscountCodesInCheckout: false, acceptAutomaticDiscounts: false,
            lineItems: [{ variantId, quantity: 1, priceOverride: { amount: product.price, currencyCode: "USD" },
                customAttributes: [{ key: "_book_id", value: id }, { key: "Pages", value: String(pages) }] }],
        } });
        if (draftOrderCreate.userErrors.length) throw new Error(draftOrderCreate.userErrors.map(e => e.message).join(", "));
        const checkout = draftOrderCreate.draftOrder?.invoiceUrl;
        if (!checkout?.startsWith("https://")) throw new Error("Missing Shopify invoice URL.");
        const ticket = { checkout, draftId: draftOrderCreate.draftOrder.id, shop: env.SHOPIFY_SHOP_DOMAIN,
            cover: meta.cover, variantId, pages, price: product.price, title: decodeURIComponent(meta.title) };
        if (!await env.BOOKS.put(key, JSON.stringify(ticket), { onlyIf: { etagMatches: lease.etag } })) {
            throw new Error("Checkout changed while creating draft.");
        }
        return Response.json({ checkout });
    } catch (error) {
        await env.BOOKS.put(key, "{}", { onlyIf: { etagMatches: lease.etag } });
        throw error;
    }
}

async function paidWebhook(request, env) {
    if (request.method !== "POST") return new Response(null, { status: 405 });
    const signature = request.headers.get("X-Shopify-Hmac-Sha256") ?? "";
    if (!/^[A-Za-z0-9+/]{43}=$/.test(signature)) return new Response(null, { status: 401 });
    const raw = await request.arrayBuffer();
    if (!env.SHOPIFY_WEBHOOK_SECRET || !await crypto.subtle.verify("HMAC", await hmacKey(env.SHOPIFY_WEBHOOK_SECRET),
        Uint8Array.from(atob(signature), c => c.charCodeAt(0)), raw)) return new Response(null, { status: 401 });
    if (request.headers.get("X-Shopify-Shop-Domain") !== env.SHOPIFY_SHOP_DOMAIN) return new Response(null, { status: 403 });
    const order = JSON.parse(new TextDecoder().decode(raw));
    const line = order.line_items?.[0];
    const bookId = line?.properties?.find(p => p.name === "_book_id")?.value;
    if (request.headers.get("X-Shopify-Topic") === "orders/paid" && order.test === false && !order.cancelled_at &&
        order.financial_status === "paid" && order.tags?.split(",").some(tag => tag.trim() === "ente-photobook") &&
        order.line_items.length === 1 && line.quantity === 1 && uuid.test(bookId) &&
        /^gid:\/\/shopify\/Order\/\d+$/.test(order.admin_graphql_api_id)) {
        const shipping = order.shipping_address;
        const address = shipping && {
            name: shipping.name || [shipping.first_name, shipping.last_name].filter(Boolean).join(" "),
            line1: shipping.address1, line2: shipping.address2 || undefined,
            townOrCity: shipping.city, stateOrCounty: shipping.province_code || shipping.province || undefined,
            postalOrZipCode: shipping.zip ?? "", countryCode: shipping.country_code,
        };
        if (!address?.name || !address.line1 || !address.townOrCity || !address.countryCode) {
            console.error("Missing shipping address on paid photobook", order.admin_graphql_api_id);
            return new Response("Missing delivery address.", { status: 503 });
        }
        await env.EVENTS.send({ type: "paid", bookId, orderId: order.admin_graphql_api_id, address });
    }
    return new Response(null, { status: 204 });
}

async function printPaidOrder(env, bookId, orderId, address) {
    const prefix = "orders/" + bookId + "/";
    if (await env.BOOKS.head(prefix + "result.json")) return;
    const entry = await env.BOOKS.get(prefix + "draft.json");
    if (!entry) throw new Error("Missing draft for paid book " + bookId);
    const ticket = await entry.json();
    const query = await shopifyAdmin(env);
    const { draftOrder } = await query(`query PaidPhotobook($id: ID!) {
        draftOrder(id: $id) { order { id test cancelledAt displayFinancialStatus
            lineItems(first: 2) { nodes { currentQuantity variant { id } customAttributes { key value }
                discountedUnitPriceAfterAllDiscountsSet { presentmentMoney { amount currencyCode } } } }
        } }
    }`, { id: ticket.draftId });
    const order = draftOrder?.order;
    if (!order) throw new Error("Shopify has not linked the paid order to its draft yet.");
    if (order.id !== orderId || order.test || order.cancelledAt) return;
    const line = order.lineItems.nodes[0];
    const price = line?.discountedUnitPriceAfterAllDiscountsSet?.presentmentMoney;
    const attributes = new Map(line?.customAttributes?.map(a => [a.key, a.value]));
    if (order.displayFinancialStatus !== "PAID" || ticket.shop !== env.SHOPIFY_SHOP_DOMAIN ||
        order.lineItems.nodes.length !== 1 || line.currentQuantity !== 1 || line.variant?.id !== ticket.variantId ||
        attributes.get("_book_id") !== bookId || attributes.get("Pages") !== String(ticket.pages) ||
        price?.currencyCode !== "USD" || Number(price.amount) !== Number(ticket.price)) {
        throw new Error("Paid book details changed. Review Shopify " + orderId);
    }
    if (!await env.BOOKS.head("books/" + bookId + ".pdf")) throw new Error("Missing PDF for paid book.");
    const key = env.PRODIGI_LIVE_KEY;
    if (!/^live_\S+$/.test(key ?? "")) throw new Error("Configure a live Prodigi key.");
    const shopifyOrderId = orderId.split("/").pop();
    const reference = "ente-shopify-" + shopifyOrderId;
    const callback = new URL("/prodigi/callback/" + bookId, env.PUBLIC_ORIGIN);
    callback.searchParams.set("sig", await sign(env.BOOK_SECRET, "prodigi-callback:" + bookId));
    const sku = products.get(ticket.cover).sku;
    const pdfUrl = await signedLink(env.PUBLIC_ORIGIN, env.BOOK_SECRET, bookId);
    const { name, ...deliveryAddress } = address;
    const response = await fetch(orderApi, {
        method: "POST", redirect: "manual", signal: AbortSignal.timeout(20000),
        headers: { "X-API-Key": key, "Content-Type": "application/json", "Idempotency-Key": reference },
        body: JSON.stringify({ merchantReference: reference, callbackUrl: callback.href, submit: true,
            shippingMethod: "standard", recipient: { name, address: deliveryAddress }, items: [printItem(sku, pdfUrl, ticket)] }),
    });
    if (!response.ok) throw new Error("Prodigi order HTTP " + response.status + " for " + reference);
    const { data } = await response.json();
    if (!data?.id) throw new Error("Missing Prodigi order ID for " + reference);
    const receipt = { shopifyOrderId, prodigiOrderId: data.id, reference, sku, pages: ticket.pages, bookId };
    await env.BOOKS.put(prefix + "result.json", JSON.stringify(receipt), { onlyIf: createOnly() });
    console.info("Photobook accepted", reference, data.id);
}

export default {
    async fetch(request, env) {
        const url = new URL(request.url);
        const cors = new Headers({ Vary: "Origin", "Cache-Control": "no-store" });
        try {
            if (url.pathname === "/shopify/orders-paid") return await paidWebhook(request, env);
            const callback = /^\/prodigi\/callback\/([\da-f-]{36})$/.exec(url.pathname);
            if (callback) return await prodigiCallback(request, env, callback[1], url);
            const pdf = /^\/prodigi-source\/books\/([\da-f-]{36})\.pdf$/.exec(url.pathname);
            if (pdf) return await download(request, env, url, pdf[1]);
            const origin = request.headers.get("Origin");
            if (!editorOrigins.has(origin)) return new Response(null, { status: 403 });
            cors.set("Access-Control-Allow-Origin", origin);
            if (request.method === "OPTIONS") {
                cors.set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE");
                cors.set("Access-Control-Allow-Headers", "Content-Type, X-Upload-Token");
                return new Response(null, { status: 204, headers: cors });
            }
            if (url.pathname === "/checkout" && request.method === "GET") {
                return Response.json({
                    prices: Object.fromEntries(Array.from(products, ([cover, product]) => [cover, product.price])),
                }, { headers: cors });
            }
            const response = url.pathname === "/checkout" && request.method === "POST"
                ? await checkDelivery(request, env) : await uploads(request, env, url);
            cors.forEach((value, header) => response.headers.set(header, value));
            return response;
        } catch (error) {
            console.error(request.method, url.pathname.split("/")[1], error.message);
            return new Response("Could not complete this request. Please try again.", { status: 503, headers: cors });
        }
    },
    async queue(batch, env) {
        for (const message of batch.messages) {
            const { type, bookId, orderId, address, reference, event } = message.body;
            try {
                if (type === "paid") await printPaidOrder(env, bookId, orderId, address);
                else if (type === "shipment") {
                    const stored = await env.BOOKS.get("orders/" + bookId + "/result.json");
                    if (!stored) throw new Error("Order receipt pending.");
                    const receipt = await stored.json();
                    if (reference && reference !== receipt.reference) throw new Error("Callback reference mismatch.");
                    const result = await syncShipment(env, bookId, receipt, event);
                    if (result.busy) throw new Error(result.message);
                    if (result.fulfillmentId) await env.BOOKS.delete("books/" + bookId + ".pdf");
                    console.info("Photobook shipment", receipt.reference, result.message);
                }
                message.ack();
            } catch (error) {
                console.error("Photobook event failed", type, bookId, error.message);
                message.retry({ delaySeconds: Math.min(3600, 15 * 2 ** Math.min(message.attempts, 8)) });
            }
        }
    },
};
