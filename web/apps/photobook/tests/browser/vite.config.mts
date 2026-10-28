import { fileURLToPath } from "node:url";
import { defineConfig } from "vite";

export default defineConfig({
    resolve: {
        alias: {
            "@": fileURLToPath(new URL("../../src", import.meta.url)),
            "@imagemagick/magick-wasm/magick.wasm":
                fileURLToPath(
                    import.meta.resolve("@imagemagick/magick-wasm/magick.wasm"),
                ) + "?url",
        },
    },
    server: { host: "127.0.0.1", port: 4318, strictPort: true },
});
