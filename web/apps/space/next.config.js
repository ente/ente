const baseConfig = require("ente-base/next.config.base.js");

module.exports = {
    ...baseConfig,
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
