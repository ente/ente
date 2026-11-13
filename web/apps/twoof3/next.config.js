const path = require("path");
const baseConfig = require("ente-base/next.config.base.js");

module.exports = {
    ...baseConfig,
    webpack: (config, options) => {
        const nextConfig = baseConfig.webpack
            ? baseConfig.webpack(config, options)
            : config;

        nextConfig.module.rules.push({
            resourceQuery: /raw/,
            type: "asset/source",
        });
        nextConfig.resolve.alias = {
            ...(nextConfig.resolve.alias || {}),
            "qr-raw/decode.js": path.resolve(
                __dirname,
                "../../node_modules/qr/decode.js",
            ),
            "qr-raw/index.js": path.resolve(
                __dirname,
                "../../node_modules/qr/index.js",
            ),
        };

        return nextConfig;
    },
    ...(process.env.NODE_ENV === "development" && {
        output: undefined,
        async rewrites() {
            return {
                fallback: [
                    {
                        source: "/:path((?!_next|images|favicon.ico).*)",
                        destination: "/",
                    },
                ],
            };
        },
    }),
};
