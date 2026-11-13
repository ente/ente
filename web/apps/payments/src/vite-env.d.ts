/// <reference types="vite/client" />

interface ImportMetaEnv {
    readonly VITE_ENTE_ENDPOINT: string | undefined;
    readonly VITE_STRIPE_US_PUBLISHABLE_KEY: string | undefined;
    readonly VITE_STRIPE_IN_PUBLISHABLE_KEY: string | undefined;
}

interface ImportMeta {
    env: ImportMetaEnv;
}
