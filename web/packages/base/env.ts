// The build replaces these process.env reads in browser bundles.
declare const process: {
    readonly env: {
        readonly NODE_ENV: "development" | "production" | "test";
        readonly NEXT_PUBLIC_ENSU_DESKTOP_VERSION?: string;
        readonly NEXT_PUBLIC_ENTE_ENDPOINT?: string;
        readonly appName: string;
        readonly desktopAppVersion?: string;
        readonly gitSHA?: string;
        readonly isDesktop: "" | "1";
    };
};

export const isDevBuild = process.env.NODE_ENV == "development";
export const buildEnvIsProductionBuild = process.env.NODE_ENV == "production";

export const buildEnvCustomAPIEndpoint = process.env.NEXT_PUBLIC_ENTE_ENDPOINT;
export const buildEnvEnsuDesktopVersion =
    process.env.NEXT_PUBLIC_ENSU_DESKTOP_VERSION;
export const buildEnvAppName = process.env.appName;
export const buildEnvIsDesktop = process.env.isDesktop == "1";
export const buildEnvDesktopAppVersion = process.env.desktopAppVersion;
export const buildEnvGitSHA = process.env.gitSHA;

// Keep these as functions; SSR would inline constants with the server value.
export const haveWindow = () => typeof window != "undefined";

export const inWorker = () => typeof importScripts == "function";
