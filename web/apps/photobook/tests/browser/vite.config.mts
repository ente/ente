import { fileURLToPath } from "node:url";
import { defineConfig, type PluginOption } from "vite";
import wasm from "vite-plugin-wasm";

export default defineConfig({
    define: {
        "process.env": JSON.stringify({
            NODE_ENV: "production",
            appName: "photobook",
            isDesktop: "",
        }),
    },
    resolve: {
        alias: { "@": fileURLToPath(new URL("../../src", import.meta.url)) },
    },
    plugins: [wasm() as PluginOption],
    worker: { plugins: () => [wasm() as PluginOption] },
    server: {
        host: "127.0.0.1",
        port: 4318,
        strictPort: true,
        fs: { allow: ["../.."] },
    },
});
