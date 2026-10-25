import wasm from "vite-plugin-wasm";
import { defineConfig } from "wxt";

// Ente API origins. `api.ente.com` is the production default; self-hosted
// servers are granted at runtime via the optional host permission requested
// during login (see `utils/ente/origins.ts`).
const enteAPIOrigin = "https://api.ente.com/*";
// The Ente Auth web app, used for the "sign in via the browser" hand-off
// (passkey / email-MFA logins). Its storage holds the session we import.
const enteWebOrigin = "https://auth.ente.com/*";

export default defineConfig({
    modules: ["@wxt-dev/module-react"],

    manifest: {
        name: "Ente Auth Autofill",
        description:
            "Autofill and suggest TOTP codes directly from your Ente Auth account.",
        permissions: ["storage"],
        host_permissions: [enteAPIOrigin, enteWebOrigin],
        // Self-hosted Ente servers are requested on demand at login time.
        optional_host_permissions: ["*://*/*"],
        // The Ente crypto is WebAssembly, which MV3 blocks unless explicitly
        // allowed.
        content_security_policy: {
            extension_pages:
                "script-src 'self' 'wasm-unsafe-eval'; object-src 'self';",
        },
        action: { default_title: "Ente Auth" },
    },

    vite: () => ({
        // Pin a single tsconfig for the transformer. Without this, Vite/oxc
        // walks up from the imported WASM sources
        // (`../web/packages/wasm/*/pkg/*.js`) and finds that package's
        // `tsconfig.json`, which extends the monorepo-only
        // `ente-build-config/tsconfig-typecheck.json` (not installed here) and
        // fails transformation.
        tsconfig: "tsconfig.json",
        plugins: [wasm()],
        server: {
            fs: {
                // The WASM `pkg` output lives outside the extension root (in
                // the sibling `web/` workspace).
                allow: [".."],
            },
        },
    }),
});
