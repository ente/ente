const baseConfig = require("ente-base/next.config.base.js");

module.exports = {
    ...baseConfig,
    webpack: (config, options) => {
        config = baseConfig.webpack(config, options);
        config.module.rules.push({
            test: /(?:like\.riv|@rive-app[\\/]canvas-lite[\\/]rive\.wasm)$/,
            type: "asset/resource",
            generator: { filename: "static/media/[name].[contenthash][ext]" },
        });
        return config;
    },
    transpilePackages: Array.from(
        new Set([
            ...(baseConfig.transpilePackages || []),
            "ente-media",
            "ente-space-wasm",
        ]),
    ),
    // Static deployments serve arbitrary profile links through profile-link.html.
    // In development, mirror that behavior with fallback rewrites.
    ...(process.env.NODE_ENV === "development" && {
        allowedDevOrigins: [
            ...(baseConfig.allowedDevOrigins ?? []),
            ...(process.env.ENTE_SPACE_ALLOWED_DEV_ORIGINS?.split(",") ?? []),
        ],
        output: undefined,
        async rewrites() {
            return {
                fallback: [
                    { source: "/:spaceUsername", destination: "/profile-link" },
                    {
                        source: "/:path((?!_next|images|favicon.ico).*)",
                        destination: "/",
                    },
                ],
            };
        },
    }),
};
