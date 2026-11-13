/// <reference types="vite/client" />

interface ImportMetaEnv {
    readonly VITE_ENTE_API_ORIGIN: string | undefined;
}

interface ImportMeta {
    env: ImportMetaEnv;
}
