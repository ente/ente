# Cloudflare Workers

Source code for our [Cloudflare Workers](https://developers.cloudflare.com/workers/).

Workers are npm workspaces that share a root `package.json` and base `tsconfig`, but are deployed individually.

## Deploying

Install dependencies:

```sh
npm ci
```

Log in if needed, then deploy the worker:

```sh
npm exec --workspace health-check -- wrangler login
npm exec --workspace health-check -- wrangler deploy
```

Replace `health-check` with the worker to deploy. Wrangler credentials are shared across the workspaces.

Stream logs from a deployed worker:

```sh
npm exec --workspace health-check -- wrangler tail
```

Log out when finished:

```sh
npm exec --workspace health-check -- wrangler logout
```

## Creating a new worker

Copy an existing workspace. This avoids the unnecessary boilerplate in Cloudflare's template. To create one from scratch, use `npm create cloudflare@latest`.

To import an existing worker from the Cloudflare dashboard, use

```sh
npm create cloudflare@2 existing-worker-name -- --type pre-existing --existing-script existing-worker-name
```

## Logging

Attach the tail worker by adding this to `wrangler.toml`:

```toml
tail_consumers = [{ service = "tail" }]
```

The tail worker sends console output and uncaught exceptions to Grafana.
