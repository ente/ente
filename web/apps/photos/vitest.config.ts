import type { PluginOption } from "vite";
import wasm from "vite-plugin-wasm";
import { defineConfig } from "vitest/config";

export default defineConfig({
    plugins: [wasm() as PluginOption],
    test: { include: ["tests/**/*.test.{ts,tsx}"] },
    // Next preserves JSX for its own compiler; component tests need it compiled.
    oxc: { jsx: { runtime: "automatic" } },
});
