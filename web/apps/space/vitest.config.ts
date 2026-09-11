import { fileURLToPath } from "node:url";
import type { PluginOption } from "vite";
import wasm from "vite-plugin-wasm";
import { defineConfig } from "vitest/config";

export default defineConfig({
    plugins: [wasm() as PluginOption],
    resolve: {
        alias: {
            services: fileURLToPath(new URL("./src/services", import.meta.url)),
        },
    },
});
