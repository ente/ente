## Staff dashboard

Web app for staff members to help with support and other administration.

### Development

Install dependencies:

```sh
npm ci
```

Run the dev server:

```sh
npm run dev
```

By default, the app talks to `https://api.ente.com`. To point it at a local API:

```sh
VITE_ENTE_API_ORIGIN=http://localhost:8080 npm run dev
```

### Checks

```sh
npm run lint # or lint:fix
npm run build
```

> [!NOTE]
>
> If `package-lock.json` has not changed since your last `npm ci`, you can use `npm install` as a faster incremental alternative.

### Deployment

The app gets redeployed whenever a PR that touches `infra/staff/**` is merged into main. See [web/docs/deploy.md](../../web/docs/deploy.md) for details.
