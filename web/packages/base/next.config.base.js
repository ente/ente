// @ts-check

const cp = require("child_process");
const os = require("os");
const path = require("path");
const fs = require("fs");

const gitSHA = (() => {
    const command =
        os.platform() == "win32"
            ? "git rev-parse --short HEAD 2> NUL || cd ."
            : "git rev-parse --short HEAD 2>/dev/null || true";
    const result = cp
        .execSync(command, { cwd: __dirname, encoding: "utf8" })
        .trimEnd();
    return result ? result : undefined;
})();

const appName = path.basename(process.cwd());

const isDesktop = process.env._ENTE_IS_DESKTOP ? "1" : "";

const desktopAppVersion = isDesktop
    ? JSON.parse(fs.readFileSync("../../../desktop/package.json", "utf-8"))
          .version
    : undefined;

if (process.env.NEXT_PUBLIC_ENTE_ACCOUNTS_URL) {
    console.log(
        "The NEXT_PUBLIC_ENTE_ACCOUNTS_URL environment variable is not supported.",
    );
    console.log("Use apps.accounts in the museum configuration instead.");
    process.exit(1);
}

if (process.env.NEXT_PUBLIC_ENTE_FAMILY_URL) {
    console.log(
        "The NEXT_PUBLIC_ENTE_FAMILY_URL environment variable is not supported.",
    );
    console.log("Use apps.family in the museum configuration instead.");
    process.exit(1);
}

if (process.env.NEXT_PUBLIC_ENTE_ALBUMS_ENDPOINT) {
    console.log(
        "The NEXT_PUBLIC_ENTE_ALBUMS_ENDPOINT environment variable is not used anymore and is ignored.",
    );
    console.log("Use apps.public-albums in the museum configuration instead.");
}

if (process.env.NEXT_PUBLIC_ENTE_PHOTOS_ENDPOINT) {
    console.log(
        "The NEXT_PUBLIC_ENTE_PHOTOS_ENDPOINT environment variable is not used anymore and is ignored.",
    );
    console.log(
        "It only affected client-side handoffs; public link behavior is configured through Museum.",
    );
}

if (process.env.NEXT_PUBLIC_ENTE_SHARE_ENDPOINT) {
    console.log(
        "The NEXT_PUBLIC_ENTE_SHARE_ENDPOINT environment variable is not used anymore and is ignored.",
    );
    console.log(
        "It only affected link preview metadata; public link behavior is configured through Museum.",
    );
}

/** @type {import("next").NextConfig} */
const nextConfig = {
    agentRules: false,
    output: "export",
    devIndicators: false,
    compiler: { emotion: true },
    transpilePackages: [
        "ente-base",
        "ente-utils",
        "ente-new",
        "ente-core-wasm",
        "ente-paste-wasm",
    ],

    env: { gitSHA, appName, isDesktop, desktopAppVersion },

    // Desktop development runs via ente://app, and uses a separate dist
    // directory so web and desktop dev servers can run simultaneously.
    ...(process.env.NODE_ENV != "production" &&
        isDesktop && { allowedDevOrigins: ["app"], distDir: ".next-desktop" }),

    webpack: (config, { isServer }) => {
        if (!isServer) {
            config.resolve.fallback.fs = false;
        }

        // libheif-js triggers an unavoidable dynamic-require warning.
        // https://github.com/catdad-experiments/libheif-js/issues/23
        config.ignoreWarnings = [{ module: /libheif-js/ }];

        config.experiments = { ...config.experiments, asyncWebAssembly: true };

        // Webpack otherwise warns that Wasm's async functions are unsupported.
        // Declare that capability without changing every Next.js browser target.
        config.output = config.output || {};
        config.output.environment = {
            ...(config.output.environment || {}),
            asyncFunction: true,
        };

        return config;
    },
};

module.exports = nextConfig;
