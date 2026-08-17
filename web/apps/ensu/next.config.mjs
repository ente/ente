import nextConfig from "ente-base/next.config.base.js";

/** @type {{ process?: { env?: Record<string, string | undefined> } }} */
const globalWithProcess = globalThis;
const env = globalWithProcess.process?.env;
const isTauriBuild = env?.ENTE_TAURI === "1";
const rawBasePath = env?.ENTE_BASE_PATH ?? "";
const normalizedBasePath = rawBasePath
    ? rawBasePath.startsWith("/")
        ? rawBasePath
        : `/${rawBasePath}`
    : undefined;

/** @satisfies {import("next").NextConfig} */
const config = {
    ...nextConfig,
    ...(isTauriBuild ? { output: "export" } : {}),
    ...(normalizedBasePath
        ? {
              basePath: normalizedBasePath,
              assetPrefix: normalizedBasePath,
              trailingSlash: true,
          }
        : {}),
};

export default config;
