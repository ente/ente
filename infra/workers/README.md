# Cloudflare Workers

Source code for our [Cloudflare Workers](https://developers.cloudflare.com/workers/).

Workers are organized as npm workspaces sharing a common `package.json` and base `tsconfig`. They can however be deployed individually.

## Deploying

Install dependencies with `npm ci`.

> [!NOTE]
>
> If `package-lock.json` has not changed since your last `npm ci`, you can use `npm install` as a faster incremental alternative.

Then, to deploy an individual worker

- Login into wrangler (if needed) using `npm exec --workspace health-check -- wrangler login`

- Deploy! `npm exec --workspace health-check -- wrangler deploy`

Wrangler is the CLI provided by Cloudflare to manage workers. Apart from deploying, it also allows us to stream logs from running workers by using `npm exec --workspace <worker-name> -- wrangler tail`.

> [!NOTE]
>
> When you're done, remember to logout!
>
> ```sh
> npm exec --workspace health-check -- wrangler logout
> ```

> [!TIP]
>
> `wrangler login` and `wrangler logout` can be run from any of the worker workspaces, wrangler stores the credentials in some OS dependent shared location.

## Creating a new worker

Copy paste an existing one. Unironically this is a good option because Cloudflare's template has a lot of unnecessary noise, but if really do want to create one from scratch, use `npm create cloudflare@latest`.

To import an existing worker from the Cloudflare dashboard, use

```sh
npm create cloudflare@2 existing-worker-name -- --type pre-existing --existing-script existing-worker-name
```

## Logging

Attach the tail worker to your worker by adding

    tail_consumers = [{ service = "tail" }]

in its `wrangler.toml`. Then any `console.(log|warn|error)` statements and uncaught exceptions in your worker will be logged to Grafana.
