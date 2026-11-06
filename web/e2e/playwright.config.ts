import { defineConfig, devices } from "@playwright/test";
import { fileURLToPath } from "node:url";
import { apps } from "./apps.ts";

const selected = Object.entries(apps).filter(
    ([name]) =>
        !process.env.ENTE_E2E_PROJECT || name === process.env.ENTE_E2E_PROJECT,
);

export default defineConfig({
    outputDir: "./test-results",
    forbidOnly: !!process.env.CI,
    workers: 1,
    retries: 0,
    timeout: 120_000,
    expect: { timeout: 30_000 },
    reporter: [
        ["list"],
        ["html", { outputFolder: "playwright-report", open: "never" }],
    ],
    use: {
        ...devices["Desktop Chrome"],
        locale: "en-US",
        trace: "retain-on-failure",
        screenshot: "only-on-failure",
    },
    projects: selected.map(([name, { port }]) => ({
        name,
        testDir: `../apps/${name}/e2e`,
        use: { baseURL: `http://localhost:${port}` },
    })),
    webServer: selected.map(([name, { port }]) => ({
        command: `node e2e/serve.ts ${name}`,
        cwd: fileURLToPath(new URL("..", import.meta.url)),
        url: `http://localhost:${port}/signup`,
        reuseExistingServer: false,
        timeout: 180_000,
    })),
});
