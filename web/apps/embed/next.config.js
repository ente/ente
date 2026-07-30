const baseConfig = require("ente-base/next.config.base.js");

module.exports = {
    ...baseConfig,
    // Keep static export in production; in development, serve path-token links
    // through the index page so local browser loads match Cloudflare fallback.
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
