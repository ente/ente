import assert from "node:assert/strict";
import { createHmac } from "node:crypto";
import test from "node:test";
import worker from "./worker.js";

const origin = "https://photobook.ente.com";
const host = "https://orders.example";
const orderId = "gid://shopify/Order/123";
const variant = "gid://shopify/ProductVariant/22";

function fixture(t) {
    const records = new Map();
    const jobs = [];
    const calls = { drafts: [], prints: [], fulfillments: [] };
    let bookId;
    const env = {
        BOOK_SECRET: "signing", SHOPIFY_CLIENT_ID: "client", SHOPIFY_CLIENT_SECRET: "secret",
        SHOPIFY_WEBHOOK_SECRET: "webhook", PRODIGI_LIVE_KEY: "live_fixture",
        SHOPIFY_SHOP_DOMAIN: "example.myshopify.com", PUBLIC_ORIGIN: host,
        SHOPIFY_LAYFLAT_VARIANT_ID: "22", SHOPIFY_SOFTCOVER_VARIANT_ID: "11",
        EVENTS: { async send(event) { jobs.push(event); } },
        BOOKS: {
            async head(key) { return records.get(key); },
            async get(key) { return records.get(key); },
            async delete(key) { records.delete(key); },
            async put(key, value, { onlyIf }) {
                const prior = records.get(key);
                if (onlyIf?.etagMatches && prior?.etag !== onlyIf.etagMatches) return null;
                if (onlyIf instanceof Headers && prior) return null;
                const object = { etag: crypto.randomUUID(), json: async () => JSON.parse(value) };
                records.set(key, object);
                return object;
            },
            async createMultipartUpload(key, { customMetadata }) {
                const uploadId = crypto.randomUUID();
                bookId = key.split("/")[1].split(".")[0];
                records.set(uploadId, { customMetadata, key });
                return { uploadId };
            },
            resumeMultipartUpload(key, uploadId) {
                const upload = records.get(uploadId);
                assert.equal(upload.key, key);
                return {
                    async uploadPart(partNumber, body) {
                        upload.bytes = await new Response(body).arrayBuffer();
                        return { partNumber, etag: "part" };
                    },
                    async complete() {
                        const pdf = { size: upload.bytes.byteLength, arrayBuffer: async () => upload.bytes,
                            customMetadata: upload.customMetadata, body: upload.bytes, httpEtag: '"pdf"' };
                        records.set(key, pdf);
                        return pdf;
                    },
                };
            },
        },
    };
    const line = () => ({ id: "line", currentQuantity: 1, variant: { id: variant },
        customAttributes: [{ key: "_book_id", value: bookId }, { key: "Pages", value: "24" }],
        discountedUnitPriceAfterAllDiscountsSet: { presentmentMoney: { amount: "99.00", currencyCode: "USD" } } });
    t.mock.method(globalThis, "fetch", async (url, init) => {
        if (url.endsWith("/oauth/access_token")) return Response.json({ access_token: "mock" });
        if (url.endsWith("/graphql.json")) {
            const { query, variables } = JSON.parse(init.body);
            if (query.includes("mutation PhotobookCheckout")) {
                calls.drafts.push(variables.input);
                return Response.json({ data: { draftOrderCreate: { userErrors: [], draftOrder: { id: "draft", invoiceUrl: "https://shop.example/pay" } } } });
            }
            if (query.includes("query PaidPhotobook")) return Response.json({ data: { draftOrder: { order: {
                id: orderId, test: false, displayFinancialStatus: "PAID", lineItems: { nodes: [line()] },
            } } } });
            if (query.includes("query OrderForShipment")) return Response.json({ data: { order: {
                name: "#200", displayFinancialStatus: "PAID", lineItems: { nodes: [line()] },
                fulfillmentOrders: { nodes: [{ id: "fo", supportedActions: [{ action: "CREATE_FULFILLMENT" }],
                    lineItems: { nodes: [{ id: "fo-line", remainingQuantity: 1, lineItem: { id: "line" } }] } }] },
                fulfillments: calls.fulfillments.map(({ trackingInfo }) => ({ id: "f", status: "SUCCESS",
                    trackingInfo: [trackingInfo], fulfillmentLineItems: { nodes: [{ lineItem: { id: "line" } }] } })),
            } } });
            assert.match(query, /mutation ShipBook/);
            calls.fulfillments.push(variables.input);
            return Response.json({ data: { fulfillmentCreate: { fulfillment: { id: "f" }, userErrors: [] } } });
        }
        assert.equal(init.headers["X-API-Key"], "live_fixture");
        if (url === "https://api.prodigi.com/v5/orders") {
            assert.equal(init.headers["Idempotency-Key"], "ente-shopify-123");
            calls.prints.push(JSON.parse(init.body));
            return Response.json({ data: { id: "456" } });
        }
        assert.equal(url, "https://api.prodigi.com/v5/orders/456");
        return Response.json({ data: { id: "456", merchantReference: "ente-shopify-123", status: "shipped",
            items: [{ id: "item", sku: calls.prints[0].items[0].sku, quantity: 1 }],
            shipments: [{ status: "shipped", trackingNumber: "TRACK", trackingUrl: "https://carrier.example/track", carrier: "Carrier" }],
        } });
    });
    const request = (path, method, body, headers = {}) => worker.fetch(new Request(new URL(path, host), {
        headers: { Origin: origin, ...headers }, method, body,
    }), env);
    const webhook = (edit, signature) => {
        const body = JSON.stringify({ admin_graphql_api_id: orderId, financial_status: "paid", test: false, tags: "ente-photobook",
            shipping_address: { name: "Customer", address1: "1 Example St", city: "Cupertino", zip: "95014", country_code: "US" },
            line_items: [{ quantity: 1, properties: [{ name: "_book_id", value: bookId }] }], ...edit });
        return request("/shopify/orders-paid", "POST", body, { "X-Shopify-Hmac-Sha256": signature ??
            createHmac("sha256", env.SHOPIFY_WEBHOOK_SECRET).update(body).digest("base64"),
            "X-Shopify-Shop-Domain": env.SHOPIFY_SHOP_DOMAIN, "X-Shopify-Topic": "orders/paid" });
    };
    const consume = async body => {
        let acknowledged = false;
        await worker.queue({ messages: [{ body, attempts: 1, ack() { acknowledged = true; }, retry() {} }] }, env);
        assert.ok(acknowledged);
    };
    return { env, request, calls, jobs, webhook, consume, records };
}

function exportedTail(pages) {
    const header = "%PDF-1.6\n";
    const kids = Array.from({ length: pages }, (_, i) => (7 + 3 * i) + " 0 R").join(" ");
    const tree = "2 0 obj\n<< /Type /Pages /Kids [" + kids + "] /Count " + pages + " >>\nendobj\n";
    const table = "xref\n0 3\n0000000000 65535 f \n0000000000 00000 n \n" + String(header.length).padStart(10, "0") + " 00000 n \n";
    return header + tree + table + "trailer\n<< /Root 1 0 R >>\nstartxref\n" + (header.length + tree.length) + "\n%%EOF\n";
}

async function upload(request, pdf, cover = "layflat") {
    const start = await request("/uploads", "POST", JSON.stringify({ pages: 24, cover, title: "Italy Trip", bytes: pdf.length }));
    assert.equal(start.status, 200);
    const { id, uploadId, token } = await start.json();
    const path = "/uploads/" + id + "?uploadId=" + uploadId;
    const headers = { "X-Upload-Token": token };
    const part = await request(path + "&part=1", "PUT", pdf, { ...headers, "content-length": String(pdf.length) });
    assert.equal(part.status, 200);
    const complete = await request(path, "POST", JSON.stringify([await part.json()]), headers);
    assert.equal((await complete.json()).bytes, pdf.length);
    return { id, headers, checkout: "/uploads/" + id + "/checkout" };
}

test("paid draft submits the uploaded book once, dispatch notifies Shopify once, and the PDF is removed", async t => {
    const { request, jobs, webhook, consume, calls } = fixture(t);
    const pdf = exportedTail(24);
    const { id, checkout, headers } = await upload(request, pdf);
    assert.equal((await request(checkout, "POST")).status, 403);
    for (let i = 0; i < 2; i++) assert.equal((await (await request(checkout, "POST", null, headers)).json()).checkout, "https://shop.example/pay");
    assert.equal(calls.drafts.length, 1);
    assert.equal(calls.drafts[0].lineItems[0].variantId, variant);
    assert.deepEqual(calls.drafts[0].lineItems[0].priceOverride, { amount: "99.00", currencyCode: "USD" });
    assert.equal(calls.drafts[0].allowDiscountCodesInCheckout, false);
    assert.equal(calls.prints.length, 0);
    assert.equal((await webhook({}, "wrong")).status, 401);
    for (const edit of [{ test: true }, { tags: "merch" }, { financial_status: "pending" }]) await webhook(edit);
    assert.equal(jobs.length, 0);
    await webhook({});
    const paid = jobs.shift();
    await consume({ ...paid, orderId: "gid://shopify/Order/999" });
    assert.equal(calls.prints.length, 0);
    await consume(paid);
    await consume(paid);
    assert.equal(calls.prints.length, 1);
    const order = calls.prints[0];
    assert.equal(order.submit, true);
    assert.equal(order.items[0].sku, "BOOK-FE-8_3-SQ-LF-G");
    const spine = order.items[0].spineDetails.dynamicSpineDetails;
    assert.equal(spine.spineText, "Italy Trip");
    assert.equal(spine.spineTextFont, "Brandon");
    assert.equal(spine.spineTextSize, 20);
    assert.equal(order.recipient.address.postalOrZipCode, "95014");
    const pdfUrl = new URL(order.items[0].assets[0].url);
    assert.ok(pdfUrl.pathname.includes(id));
    assert.equal((await request(pdfUrl.pathname, "GET")).status, 403);
    assert.equal(await (await request(pdfUrl, "GET")).text(), pdf);
    for (const eventId of ["dispatch", "dispatch", "complete"]) {
        const callback = await request(order.callbackUrl, "POST", JSON.stringify({ id: eventId,
            type: "com.prodigi.order.status.stage.changed#Complete", data: { order: { merchantReference: order.merchantReference } } }));
        assert.equal(callback.status, 204);
        await consume(jobs.shift());
    }
    assert.equal(calls.fulfillments.length, 1);
    assert.equal(calls.fulfillments[0].notifyCustomer, true);
    assert.equal(calls.fulfillments[0].trackingInfo.url, "https://carrier.example/track");
    assert.equal((await request(pdfUrl, "GET")).status, 404);
});

test("reports prices and validates the live key and page count before charging", async t => {
    const { env, request, calls } = fixture(t);
    const spec = { cover: "softcover", pages: 100, bytes: 123, title: "Trip" };
    assert.deepEqual(await (await request("/checkout", "GET")).json(), { prices: { layflat: "99.00", softcover: "49.00" } });
    assert.equal((await request("/uploads", "POST", JSON.stringify({ ...spec, cover: "layflat", pages: 22 }))).status, 400);
    assert.equal((await request("/uploads", "POST", JSON.stringify({ ...spec, pages: 102 }))).status, 400);
    const bad = await upload(request, exportedTail(26), "softcover");
    assert.equal((await request(bad.checkout, "POST", null, bad.headers)).status, 422);
    const good = await upload(request, exportedTail(24), "softcover");
    assert.equal((await request(good.checkout, "POST", null, bad.headers)).status, 403);
    const destination = { countryCode: "NL", postalCode: "1012 JS" };
    assert.equal((await request(good.checkout, "POST", JSON.stringify(destination), good.headers)).status, 200);
    assert.deepEqual(calls.drafts[0].shippingAddress, { countryCode: "NL", zip: "1012 JS" });
    assert.equal(calls.drafts[0].lineItems[0].variantId, "gid://shopify/ProductVariant/" + env.SHOPIFY_SOFTCOVER_VARIANT_ID);
    assert.equal(calls.drafts[0].lineItems[0].priceOverride.amount, "49.00");
    env.PRODIGI_LIVE_KEY = "sandbox_fixture";
    assert.equal((await request("/uploads", "POST", JSON.stringify(spec))).status, 503);
    assert.equal(calls.prints.length, 0);
});

test("delivery check requires a Standard quote for the selected book and distinguishes outages", async t => {
    const { request, records } = fixture(t);
    const body = JSON.stringify({ cover: "softcover", pages: 36,
        destination: { countryCode: "NL", postalCode: "1012 JS" } });
    let quote = Response.json({ data: { options: [{ method: "Standard" }] } });
    t.mock.method(globalThis, "fetch", async (url, init) => {
        assert.equal(url, "https://api.prodigi.com/v5/quotes/shipping");
        assert.equal(init.headers["X-API-Key"], "live_fixture");
        assert.deepEqual(JSON.parse(init.body), { destination: { countryCode: "NL", postalOrZipCode: "1012 JS" },
            items: [{ catalogueVariantId: "BOOK-FE-8_3-SQ-SOFT-G", quantity: 1,
                assets: [{ printArea: "default", pageCount: 36 }] }] });
        return quote;
    });
    assert.equal((await request("/checkout", "POST", body)).status, 204);
    quote = Response.json({ data: { options: [{ method: "Express" }] } });
    assert.equal((await request("/checkout", "POST", body)).status, 422);
    quote = Response.json({ type: "quote_unavailable" }, { status: 422 });
    assert.equal((await request("/checkout", "POST", body)).status, 422);
    quote = Response.json({}, { status: 503 });
    assert.equal((await request("/checkout", "POST", body)).status, 503);
    assert.equal(records.size, 0);
});
