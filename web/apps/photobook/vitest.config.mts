import { fileURLToPath } from "node:url";
import { defineConfig } from "vitest/config";

export default defineConfig({
    resolve: {
        alias: { "@": fileURLToPath(new URL("./src", import.meta.url)) },
    },
    test: {
        projects: [
            { test: { name: "node", include: ["src/**/*.test.ts"] } },
            {
                oxc: { jsx: { runtime: "automatic" } },
                test: {
                    name: "dom",
                    include: ["src/**/*.test.tsx"],
                    environment: "happy-dom",
                },
            },
        ],
    },
});
