# Development

## Editor setup

We recommend VS Code, with the following extensions:

- Prettier - reformats your code automatically (enable format on save),
- ESLint - warns you about issues

Optionally, if you're going to make many changes to the CSS in JS, you might also find it useful to install the _vscode-styled-components_ extension.

## npm commands

Use the npm version from `package.json`.

### npm ci, npm install

Use `npm ci` to install dependencies using the committed lockfile. You need this for initial setup, and whenever `package-lock.json` changes (e.g. after pulling the latest upstream).

`npm ci` is the safe default. However, it deletes and recreates `node_modules` each time. For a faster incremental install, you can use `npm install` if you have already run `npm ci` and `package-lock.json` has not changed since then.

> We pin exact versions in `package.json` and commit the lockfile so both `npm install` and `npm ci` should give the same outcome; however, this is not guaranteed, so if `npm install` changes `package-lock.json`, review the diff instead of treating it as incidental churn.

Use `npm install <package> --workspace <workspace>` only when intentionally adding or updating dependencies, and review the resulting `package.json` and `package-lock.json` changes.

Installs skip dependency lifecycle scripts (`ignore-scripts` in `.npmrc`) so that installing cannot run arbitrary code from packages. The packages we use work fine without their lifecycle scripts: they either ship prebuilt binaries (e.g. `esbuild`, `sharp`) or fetch them on first use (`wasm-pack`). `save-exact` in `.npmrc` keeps newly added dependencies pinned to exact versions.

### npm run dev:\*

Launch the app in development mode. There is one `npm run dev:foo` for each app, e.g. `npm run dev:auth`. `npm run dev` is a shortcut for `npm run dev:photos`.

Common ports are `3000` for photos, `3002` for albums, `3003` for auth, `3005` for share, and `3006` for embed. See `package.json` for the full list.

### npm run build:\*

Build a production export for the app. This is a bunch of static HTML/JS/CSS that can be then deployed to any web server.

There is one `npm run build:foo` for each app, e.g. `npm run build:auth`. The output will be placed in `apps/<foo>/out`, e.g. `apps/auth/out`.

### lint, lint:fix

Use `npm run lint` to check that your code formatting is as expected, and that there are no linter errors. Use `npm run lint:fix` to try and automatically fix the issues.

## Monorepo

The monorepo uses npm workspaces.

To run a command for a workspace `<ws>`, invoke `npm exec --workspace <ws> -- <cmd>` from the root folder. For example, to start a development server for the `photos` app, we can do

```sh
npm exec --workspace photos -- next dev --webpack
```

There is also a convenience alias, `npm run dev:photos`. See `package.json` for the full list of such aliases. The two common patterns are `dev:<app-name>` for running a local development server, and `build:<app-name>` for creating a production build.

> Tip: `npm run dev` is a shortcut for `npm run dev:photos`

Note that npm does not automatically update `node_modules` if you switch to a branch that has added or modified dependencies. So if you encounter unexpected errors on switching branches, make sure that your `node_modules` is up to date first: use `npm install` if `package-lock.json` has not changed since your last `npm ci`, otherwise use `npm ci`.

To add a local package as a dependency, use `<package-name>@*`. The "\*" here denotes any version.

```sh
npm install 'ente-utils@*' --workspace photos
```

To see the workspace package metadata, use

```sh
npm query .workspace
```
