import { fileURLToPath } from "node:url";
import { defineConfig } from "vitest/config";

export default defineConfig({
    resolve: {
        alias: {
            "@": fileURLToPath(new URL("./src", import.meta.url)),
            "@imagemagick/magick-wasm/magick.wasm":
                fileURLToPath(
                    import.meta.resolve("@imagemagick/magick-wasm/magick.wasm"),
                ) + "?url",
        },
    },
    test: { include: ["src/**/*.test.ts"] },
});
