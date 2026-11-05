import { fileURLToPath } from "node:url";
import { preview } from "vite";
import { apps } from "./apps.ts";

const name = process.argv[2];
if (!name || !Object.hasOwn(apps, name))
    throw new Error("Expected an app name: photos or locker");
const app = apps[name as keyof typeof apps];

const server = await preview({
    configFile: false,
    envDir: false,
    root: fileURLToPath(new URL(`../apps/${name}/`, import.meta.url)),
    appType: "mpa",
    build: { outDir: "out" },
    preview: { host: "localhost", port: app.port, strictPort: true },
});
server.printUrls();
