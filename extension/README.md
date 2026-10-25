# Ente Auth Autofill (Chrome extension)

A Chrome (MV3) extension that signs in to your Ente server and autofills TOTP
codes from **Ente Auth** into OTP fields on web pages.

This lives alongside the Ente monorepo but is its own npm project. It reuses
Ente's audited Rust crypto by compiling the WASM bindings from `rust/` and
importing the generated `pkg` output directly (see
`utils/wasm/prelogin.ts` / `utils/wasm/auth.ts`). The thin TypeScript glue that
talks to the server is adapted from `web/packages/accounts` and
`web/apps/auth` — each vendored file carries a comment pointing at its origin.

## What works

- **Login** with email + password using Ente's SRP flow, plus TOTP two-factor.
- **Email-MFA accounts**: when the server reports email MFA, the extension sends
  a one-time code to the email and verifies it, then unlocks with the same
  password (mirrors the web app's `/users/verify-email` flow).
- **Browser sign-in hand-off**: for logins the extension cannot perform itself
  (e.g. a passkey second factor), "Sign in via the Ente web app" opens
  `auth.ente.com`, waits for you to finish there, then imports the resulting
  session (token, key attributes, and master key) so the vault unlocks in the
  extension.
- **Self-hosted servers**: set a custom API origin from the popup; the required
  host permission is requested on demand.
- **Unlock**: once signed in, the vault can be unlocked offline from the stored
  key attributes.
- **Code list** in the popup with live OTPs, countdown, and copy-to-clipboard.
- **Autofill**: a content script detects OTP inputs (including plain text
  fields and segmented one-digit-per-box inputs) and shows an inline "Ente"
  button that fills the matching code for the current site.

## Not yet supported

- Passkey second factor **inside the extension** — the popup rejects it with a
  clear message and points you at the browser sign-in hand-off instead.
- The browser sign-in hand-off only works with the hosted `auth.ente.com`; it
  does not cover self-hosted web apps.
- Email-MFA accounts that have **no password** (no key attributes) cannot be
  unlocked, since the master key needs the password-derived KEK.
- HOTP counter increments are not persisted back to the server (codes are
  generated, but the server-side counter is unchanged).
- Generating "interactive" key attributes, so the offline unlock pays the full
  Argon2 cost (slow for accounts with high memory limits).

## Prerequisites

The WASM bindings must be built once (they are not committed). From `web/`:

```sh
cd ../web
npm ci
npm run build:prelogin-wasm
npm run build:auth-wasm
```

This requires a Rust toolchain with the `wasm32-unknown-unknown` target and
[`wasm-pack`](https://rustwasm.github.io/wasm-pack/).

## Build

```sh
npm install
npm run build      # -> .output/chrome-mv3
```

Or `npm run dev` for watch mode with HMR.

## Load in Chrome

1. Open `chrome://extensions`.
2. Enable **Developer mode**.
3. **Load unpacked** → select `.output/chrome-mv3`.

## Architecture

```
entrypoints/
  background.ts        MV3 service worker: answers content-script requests
  ente-web.content.ts  Scrapes a logged-in auth.ente.com tab for the hand-off
  otp.content.ts       Detects OTP fields, shows the fill button
  popup/               React UI: login, unlock, code list
utils/
  vault.ts             Login / unlock / refresh state machine
  cached-codes.ts      WASM-free read of the decrypted vault (for background)
  matcher.ts           Issuer/host matching heuristics
  messaging.ts         Typed messages between content script and background
  ente/                Vendored Ente server glue (SRP, keys, codes, ...)
  wasm/                Wrappers over the generated WASM packages
```

### Browser sign-in hand-off

The WASM crypto stack uses dynamic `import()`, which is disallowed in a service
worker, so the background never loads it. Instead:

1. The popup asks the background to start the hand-off, which opens
   `auth.ente.com`.
2. `ente-web.content.ts` polls that tab; once the web app has a session it reads
   `localStorage.user`, `localStorage.keyAttributes`, and the boxed master key in
   `sessionStorage.encryptionKey`, and sends them to the background.
3. The background stashes them in `browser.storage.session` (only while a
   hand-off is pending).
4. The popup — which already loads the WASM stack — unboxes the master key and
   finishes the login.

### Security model

- The master key and the decrypted authenticator items live only in
  `browser.storage.session`, which is cleared when the browser closes and is
  restricted to trusted extension contexts (`storage.session.setAccessLevel`).
- Content scripts never see secrets: they receive only a short-lived OTP for
  the current site, and only when the site matches an item's issuer.
- The auth token (persistent, revocable) lives in `browser.storage.local`.

## Icons

Add PNG icons under `public/icon/{16,32,48,128}.png` to give the extension a
toolbar icon; WXT picks them up automatically.
