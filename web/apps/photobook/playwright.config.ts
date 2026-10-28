import { defineConfig } from "@playwright/test";

export default defineConfig({
    testDir: "tests/browser",
    testMatch: "**/*.spec.ts",
    fullyParallel: false,
    workers: 1,
    timeout: 120_000,
    expect: { timeout: 10_000 },
    forbidOnly: !!process.env.CI,
    reporter: "list",
    use: {
        baseURL: "http://127.0.0.1:4317",
        browserName: "chromium",
        viewport: { width: 1440, height: 1000 },
        trace: "retain-on-failure",
        screenshot: "only-on-failure",
    },
    webServer: [
        { command: "node scripts/serve.mts", url: "http://127.0.0.1:4317" },
        {
            command: "vite --config tests/browser/vite.config.mts",
            url: "http://127.0.0.1:4318/tests/browser/export.html",
        },
    ],
});
