# Development

## npm commands

### npm ci, npm install

Use `npm ci` to install dependencies using the committed lockfile. You need this for initial setup, and whenever `package-lock.json` changes (e.g. after pulling the latest upstream).

`npm ci` is the safe default. However, it deletes and recreates `node_modules` each time. For a faster incremental install, you can use `npm install` if you have already run `npm ci` and `package-lock.json` has not changed since then.

> We pin exact versions in `package.json` and commit the lockfile so both `npm install` and `npm ci` should give the same outcome; however, this is not guaranteed, so if `npm install` changes `package-lock.json`, review the diff instead of treating it as incidental churn.

Use `npm install <package>` only when intentionally adding or updating dependencies, and review the resulting `package.json` and `package-lock.json` changes.

The desktop app embeds the Photos web app, so local development also requires installing dependencies in `../web`:

```sh
cd ../web
npm ci
cd ../desktop
npm ci
npm run postinstall
```

### npm run dev

Launch the app in development mode:

- Runs the postinstall script if needed.
- Transpiles the files in `src/` and starts the main process.

- Runs a development server for the renderer, with hot module reload.

The renderer scripts check that `../web` dependencies have been installed. If they are missing or stale, update them before debugging renderer errors: use `npm install` in `../web` if its `package-lock.json` has not changed since your last `npm ci`, otherwise use `npm ci`.

### npm run build

Build a binary for your current platform.

Note that our actual releases use a [GitHub workflow](../../.github/workflows/photos-desktop-build.yml) that is similar to this, except it builds binaries for all the supported OSes and uses production signing credentials.

During development, you might find `npm run build:quick` helpful. It is a variant of `npm run build` that omits some steps to build a binary quicker, something that can be useful during development.

### npm run postinstall

Installs skip dependency lifecycle scripts (`ignore-scripts` in `.npmrc`) so that installing cannot run arbitrary code from packages. The flip side is that our own postinstall does not run automatically either, so it must be invoked explicitly. `npm run dev` runs it automatically if it hasn't run for the currently installed dependencies; for other flows (e.g. `npm run build`) run it yourself after `npm ci`. It:

- Runs the install scripts of the dependencies that fetch prebuilt binaries (`ffmpeg-static`, `onnxruntime-node`, `electron-winstaller`).

- Runs [electron-builder](https://www.electron.build/cli)'s `install-app-deps` command to rebuild native node modules (those written in C/C++) against `electron`'s packaged `node` version.

- Downloads the `vips` binary used during development (see `scripts/vips.js`).

### lint, lint:fix

Use `npm run lint` to check that your code formatting is as expected, and that there are no linter errors. Use `npm run lint:fix` to try and automatically fix the issues.
