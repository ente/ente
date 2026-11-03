import { fileURLToPath } from "node:url";
import { defineConfig } from "vitest/config";

export default defineConfig({
    resolve: {
        alias: { "@": fileURLToPath(new URL("./src", import.meta.url)) },
    },
    oxc: { jsx: { runtime: "automatic" } },
    test: {
        projects: [
            {
                extends: true,
                test: {
                    name: "unit",
                    environment: "node",
                    include: ["src/**/*.test.ts"],
                },
            },
            {
                extends: true,
                test: {
                    name: "dom",
                    environment: "happy-dom",
                    include: ["src/**/*.test.tsx"],
                },
            },
        ],
    },
});
