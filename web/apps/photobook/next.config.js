const { PHASE_DEVELOPMENT_SERVER } = require("next/constants");

/** @type {import('next').NextConfig} */
const nextConfig = {
    output: "export",
    trailingSlash: true,
    images: { unoptimized: true },
    webpack: (config, { isServer }) => {
        config.module.rules.push({
            test: /magick\.wasm$/,
            type: "asset/resource",
        });
        config.externals = [...(config.externals || []), { canvas: "canvas" }];

        // ente-wasm uses `import * as wasm from "./ente_wasm_bg.wasm"`, which
        // requires webpack's async WebAssembly experiment.
        config.experiments = {
            ...(config.experiments || {}),
            asyncWebAssembly: true,
            topLevelAwait: true,
        };

        config.output = {
            ...config.output,
            environment: { ...config.output?.environment, asyncFunction: true },
        };

        // The vendored ente-wasm is browser-only; never bundle it into the
        // server build (we use `output: "export"`, but Next still does an RSC
        // pass during build).
        if (isServer) {
            config.externals.push(({ request }, callback) => {
                if (request && request.includes("vendor/ente-wasm")) {
                    return callback(null, "commonjs " + request);
                }
                callback();
            });
        }

        return config;
    },
};

module.exports = (phase) => ({
    ...nextConfig,
    // Production builds clean .next; keep the running dev server's chunks separate.
    distDir: phase === PHASE_DEVELOPMENT_SERVER ? ".next-dev" : ".next",
});
