# Live photobook checkout

The photobook editor checks standard delivery for the selected book using the country and postal code. When Prodigi offers delivery, the editor uploads the private PDF and opens Shopify checkout. The Worker charges USD 49 for a 210 mm Softcover or USD 99 for a 210 mm Layflat through the draft invoice. Both include standard shipping. Shopify handles the address, tax and payment. The paid webhook queues the book for production. Prodigi’s dispatch callback updates the Shopify fulfillment and requests a shipping email, with tracking when supplied. Closing the editor after checkout opens has no effect on fulfillment.

## 1. Set up the two variants in Ente Merch

In Shopify admin, open **Products → Ente Photobook**. Configure Softcover at USD 49 and Layflat at USD 99. Use a physical product at a merchant-managed location, with inventory tracking off for print on demand. Keep the product off public sales channels during private testing. Customers who have a draft invoice use its checkout link. An unlisted storefront product is still accessible by direct link.

Both Shopify variant IDs are configured in [wrangler.jsonc](./wrangler.jsonc). If you replace a variant in Shopify, update its ID there before deploying.

Under **Settings → Shipping and delivery**, give the photobook variants a shipping profile with a single free standard rate in the markets you intend to serve. Include destinations supported by the corresponding Prodigi SKU. Use separate profiles if the products have different coverage. The Worker leaves shipping selection to Shopify so changing the destination at checkout uses that profile. Check your intended shipping address before paying. [Shopify shipping profiles](https://help.shopify.com/en/manual/fulfillment/setup/shipping-profiles)

## 2. Create the production Shopify app

1. In Ente’s **Shopify Dev Dashboard → Apps → Create app → Start from Dev Dashboard**, name the app **Ente Photobook Orders**. Use the organization that owns Ente Merch.
2. Create a version. Turn off **Embed app in Shopify admin**, use `https://shopify.dev/apps/default-app-home` for the app URL, and select webhook API version **2026-10**. Enter these scopes and release the version.

```text
write_draft_orders,read_orders,read_products,write_merchant_managed_fulfillment_orders
```

3. Select **Install app**, choose the existing **Ente Merch** store (`ente-swag.myshopify.com`), and approve the permissions. Copy this app’s client ID and client secret for the Worker. The Worker serves as the app backend and exchanges these credentials for Admin API access. [Shopify app setup](https://shopify.dev/docs/apps/build/dev-dashboard/create-apps-using-dev-dashboard) · [Shopify client credentials](https://shopify.dev/docs/apps/build/authentication-authorization/access-tokens/client-credentials-grant)

## 3. Deploy the backend

### Configure the upload rule in Cloudflare

In the `ente.com` zone, open **Security → Security rules → Create rule → Rate limiting rules**. Name it **Photobook upload starts**. On Pro or higher, use this expression. On Business or Enterprise you can also add `and http.request.method eq "POST"` to count delivery checks and upload starts and exclude browser preflight requests.

```text
http.host eq "photobook-orders.ente.com" and http.request.uri.path in {"/checkout" "/uploads"}
```

Select **IP**, **10 requests** per **1 minute**, **Block** for **1 minute**, then **Deploy**. Exact path matching keeps multipart uploads, Shopify webhooks and Prodigi callbacks outside the rule. The Free plan supports only a 10-second window and cannot scope a rate limiting rule to this hostname. A path-only rule would apply across the zone. [Cloudflare dashboard instructions](https://developers.cloudflare.com/waf/rate-limiting-rules/create-zone-dashboard/) · [Plan limits](https://developers.cloudflare.com/waf/rate-limiting-rules/#availability)

For a private pilot on any plan, use **Create rule → Custom rules** with the **Block** action and the expression below. Replace the example IP with your public IP before deploying. This restricts uploads to the tester and can be used on Free for local testing. [Cloudflare IP allowlist example](https://developers.cloudflare.com/waf/custom-rules/use-cases/allow-traffic-from-ips-in-allowlist/)

```text
http.host eq "photobook-orders.ente.com" and (http.request.uri.path in {"/checkout" "/uploads"} or starts_with(http.request.uri.path, "/uploads/")) and not ip.src in {192.0.2.1}
```

### Deploy from the dashboard

In **Workers & Pages → photobook-orders → Edit code**, paste the entire [worker.js](./worker.js). Configure the private EU R2 bucket as `BOOKS`, add the `photobook-orders` queue as producer binding `EVENTS`, and attach this Worker as its consumer with batch size 1, 24 retries, and dead-letter queue `photobook-orders-failed`. Copy the four text variables from [wrangler.jsonc](./wrangler.jsonc) and add the five secrets listed below. Use the custom domain `photobook-orders.ente.com` and disable the `workers.dev` route and preview URLs so upload requests use the hostname covered by the zone rules. Deploy and configure the Shopify payment webhook below.

### Deploy from your terminal

Use your existing Wrangler login for Ente’s account. Verify that `photobook-orders.ente.com` is available in the `ente.com` zone. The Worker deployment configures the hostname, DNS, and TLS. Run these commands from the repository root. [Cloudflare Worker custom domains](https://developers.cloudflare.com/workers/configuration/routing/custom-domains/)

```sh
cd infra/workers
npm ci
cd photobook-orders
npm exec -- wrangler whoami
```

Confirm that the account shown is Ente’s production account. Create the resources once, then deploy the Worker from this directory. Future Worker releases need only the deploy command.

```sh
npm exec -- wrangler r2 bucket create photobook-orders --jurisdiction eu
npm exec -- wrangler queues create photobook-orders
npm exec -- wrangler queues create photobook-orders-failed
npm exec -- wrangler deploy
```

Keep public access disabled on the R2 bucket. The Worker reads it using the `BOOKS` EU binding. `photobook-orders-failed` holds events that exhaust their retries.

In **Shopify admin → Settings → Notifications → Webhooks**, create a JSON webhook for **Order payment** (`orders/paid`), API version **2026-10**, at `https://photobook-orders.ente.com/shopify/orders-paid`. Copy the webhook signing secret shown in the notifications settings. The Worker verifies this signature and only processes paid, live orders from its own photobook drafts. If the store still has a payment webhook pointing at the photobook staging Worker, remove that staging subscription once its tests are finished. [Shopify webhook settings](https://help.shopify.com/en/manual/fulfillment/setup/notifications/webhooks)

From the same terminal run the following commands. Each prompts for one value.

```sh
npm exec -- wrangler secret put SHOPIFY_CLIENT_ID
npm exec -- wrangler secret put SHOPIFY_CLIENT_SECRET
npm exec -- wrangler secret put SHOPIFY_WEBHOOK_SECRET
npm exec -- wrangler secret put PRODIGI_LIVE_KEY
npm exec -- wrangler secret put BOOK_SECRET
```

- Enter the installed Shopify app's credentials for the first two and the **Notifications webhook signing secret** for the third.
- Enter the Prodigi v5 production credential with exactly one `live_` prefix. Set up your live Prodigi billing method before paying for the first book. Each order gets its own callback URL automatically. [Prodigi authentication and orders](https://www.prodigi.com/print-api/docs/)
- Generate a new random secret for `BOOK_SECRET`, for example with `openssl rand -hex 32`. Keep this stable while outstanding orders have signed PDF or callback links.
- If your Worker hostname differs, update `PUBLIC_ORIGIN` in `wrangler.jsonc`, the Shopify webhook URL, and the editor's `NEXT_PUBLIC_PHOTOBOOK_UPLOAD_ORIGIN`. This public variable contains only the Worker origin. Integration credentials belong in Worker secrets.

## 4. Place the first order from your local editor

Check the deployed endpoint from your terminal. Expect JSON with softcover and layflat prices of 49 and 99 USD. Opening a draft checkout in the next step also tests the upload and Shopify credentials.

```sh
curl -fsS -H 'Origin: http://localhost:3014' https://photobook-orders.ente.com/checkout
```

Start the development editor from the repository root in another terminal. It uses the production Worker by default.

```sh
cd web
npm run dev:photobook
```

1. Open [the local photobook app](http://localhost:3014), create a book, set the spine title, and choose a cover. Both bindings accept 24–100 pages including both covers, in even counts.
2. Click **Checkout** in the preview and enter the delivery country and postal code (where used). The editor checks the selected cover and page count with Prodigi before preparing the PDF. Try another destination if standard delivery is unavailable. When delivery is available, click **Proceed to checkout** to upload the PDF and open Shopify. Enter the remaining address and check the price, shipping, and tax there. Shopify applies its own shipping profiles if the address changes.
3. Pay only when you want a real print. Shopify sends the buyer's order confirmation. Check the paid order in Shopify and look for `ente-shopify-<numeric Shopify order ID>` in the **live** Prodigi dashboard.
4. After dispatch, open the Shopify order timeline and the buyer's shipping email. Retry delivery of the same event reuses the existing print order or Shopify fulfillment.

## Operations

The invoice contains a book ID and page count. The private PDF stays in R2 until a dispatched fulfillment is recorded. Prodigi gets a signed download URL valid for at most seven days, issued after payment. For an abandoned invoice, delete the open draft in Shopify before removing its PDF from R2. Completed uploads that never reached checkout and abandoned drafts currently need manual cleanup. R2 aborts incomplete multipart uploads using its bucket lifecycle rules. [R2 object lifecycles](https://developers.cloudflare.com/r2/buckets/object-lifecycles/)

The Worker queues payment and shipment events before acknowledging their delivery. The queue temporarily holds the delivery address for a paid book. A callback can arrive before tracking becomes visible. Failed work is retried with backoff. Investigate entries in `photobook-orders-failed` if a paid order or shipping notification is missing. Resolve the cause, then resend the message to `photobook-orders` with the original IDs so the print order's idempotency key stays the same. Manage reversals or print problems using the Shopify order and its Prodigi merchant reference.

Production editor builds offer a local PDF download. When you choose to open ordering publicly, enable the checkout button in those builds and remove the pilot IP restriction.
