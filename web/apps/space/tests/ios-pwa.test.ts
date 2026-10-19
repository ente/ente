import { readFileSync } from "node:fs";
import { runInNewContext } from "node:vm";
import { expect, test } from "vitest";

const bootstrap = readFileSync(
    new URL("../public/ios-pwa.js", import.meta.url),
    "utf8",
);

test.each([
    { name: "iOS Home Screen", navigator: { standalone: true }, enabled: true },
    {
        name: "iOS browser tab",
        navigator: { standalone: false },
        enabled: false,
    },
    { name: "Android PWA", navigator: {}, enabled: false },
    { name: "desktop PWA", navigator: {}, enabled: false },
])(
    "only opts in $name when using the iOS standalone API",
    ({ navigator, enabled }) => {
        const dataset: Record<string, string> = {};
        runInNewContext(bootstrap, {
            navigator,
            document: { documentElement: { dataset } },
            matchMedia: () => ({ matches: true }),
        });
        expect(dataset.spaceIosPwa == "true").toBe(enabled);
    },
);
