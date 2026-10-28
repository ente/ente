import { readFile, stat } from "node:fs/promises";
import { createServer } from "node:http";
import { extname, resolve, sep } from "node:path";

const root = resolve("out");
const contentTypes: Record<string, string> = {
    ".html": "text/html",
    ".js": "text/javascript",
    ".css": "text/css",
    ".wasm": "application/wasm",
    ".woff2": "font/woff2",
    ".svg": "image/svg+xml",
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".txt": "text/plain",
};

createServer(async (request, response) => {
    try {
        const pathname = new URL(request.url!, "http://127.0.0.1").pathname;
        let file = resolve(root, `.${decodeURIComponent(pathname)}`);
        if (file !== root && !file.startsWith(root + sep)) {
            response.writeHead(403).end();
            return;
        }
        if ((await stat(file)).isDirectory())
            file = resolve(file, "index.html");
        const bytes = await readFile(file);
        response.setHeader(
            "Content-Type",
            contentTypes[extname(file)] ?? "application/octet-stream",
        );
        response.end(bytes);
    } catch {
        response.writeHead(404).end();
    }
}).listen(4317, "127.0.0.1");
