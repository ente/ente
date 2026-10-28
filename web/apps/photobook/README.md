# Photobook

A browser photobook editor built as an Ente web workspace. It uses Pages Router and the shared `ente-base` and `ente-build-config` configuration.

Run commands from `web/`:

```sh
npm ci
npm run dev:photobook
npm run build:photobook
npm run lint
npm test --workspace photobook
```

Development runs on port 3014. The production build writes `apps/photobook/out/`.

PDF export renders each page to sRGB canvas pixels and sends them to `ente-photobook-wasm` in a worker. The package builds the existing `rust/bindings/wasm/photobook` binding with wasm-pack. Generated `pkg/` files stay ignored. Rust converts to the bundled FOGRA39 CMYK profile and streams PDF/X-4 page chunks back to the browser. PNG ZIP export uses the existing canvas renderer and JSZip.

HEIC conversion, EXIF dates, encrypted file handling, and public album requests use shared Ente packages. Album API requests follow Ente's configured API origin. A self-hosted album requires the corresponding Ente API configuration; the app does not discover servers by trying multiple hosts with an access token.

Book state and image blobs use a typed IndexedDB database through Ente’s existing `idb` dependency. The app starts with a new `photobook` database; it does not import the standalone app’s saved books. Pending album downloads resume after reload and discard per-photo download credentials when complete. Reset clears the book and image stores in one transaction.

The UI remains English-only. Translation work is deferred.

The web CI runs the app's unit tests through the shared `npm test` command.

The existing Deploy (Web) workflow builds this workspace and publishes its output through `deploy-web-app` to Cloudflare Pages project `ente`, branch `deploy/photobook`. Configure the existing hostname to use that deployment before retiring the standalone GitHub Pages deployment. Do not copy the old repository's GitHub Pages workflow or CNAME file.
