import { app, net, protocol } from "electron/main";
import { stat } from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { wait } from "./utils/common";
import { isDev } from "./utils/electron";

export const rendererURL = "ente://app";
const devServerURL = "http://localhost:3008";

export const registerRendererProtocol = () => {
    const exportDirectory = path.join(app.getAppPath(), "out");
    protocol.handle("ente", async (request) => {
        const url = new URL(request.url);
        if (url.host != "app") return new Response(null, { status: 404 });
        if (request.method != "GET" && request.method != "HEAD") {
            return new Response(null, {
                status: 405,
                headers: { Allow: "GET, HEAD" },
            });
        }

        if (isDev) return proxyToNextDevServer(request, url);
        return serveExport(request, url, exportDirectory);
    });
};

const proxyToNextDevServer = async (request: Request, url: URL) => {
    const target = new URL(devServerURL);
    target.pathname = url.pathname;
    target.search = url.search;

    const deadline = Date.now() + 60_000;
    let response: Response;
    for (;;) {
        request.signal.throwIfAborted();
        try {
            response = await net.fetch(target.href, {
                method: request.method,
                headers: request.headers,
                signal: request.signal,
            });
            break;
        } catch (error) {
            if (
                Date.now() >= deadline ||
                !String(error).includes("net::ERR_CONNECTION_REFUSED")
            ) {
                throw error;
            }
            await wait(500);
        }
    }

    if (
        request.method != "GET" ||
        target.pathname != "/_next/static/chunks/webpack.js" ||
        !response.ok
    ) {
        return response;
    }

    const hmrOrigin = devServerURL.replace("http:", "ws:");
    const script = `(${rewriteHMRSocket.toString()})(${JSON.stringify(hmrOrigin)});\n`;
    return new Response(script + (await response.text()), {
        headers: {
            "Content-Type": "text/javascript; charset=utf-8",
            "Cache-Control": "no-store",
        },
    });
};

const rewriteHMRSocket = (devOrigin: string) => {
    globalThis.WebSocket = new Proxy(globalThis.WebSocket, {
        construct(target, args: unknown[], newTarget) {
            const [url] = args;
            if (
                typeof url == "string" &&
                url.split("?")[0] == "wss://app/_next/hmr"
            ) {
                args[0] = url.replace("wss://app", devOrigin);
            }
            return Reflect.construct(target, args, newTarget) as WebSocket;
        },
    });
};

const serveExport = async (request: Request, url: URL, directory: string) => {
    let pathname: string;
    try {
        pathname = decodeURIComponent(url.pathname);
    } catch {
        return new Response(null, { status: 400 });
    }
    if (
        /[\\\0]/.test(pathname) ||
        (process.platform == "win32" && pathname.includes(":"))
    ) {
        return new Response(null, { status: 400 });
    }

    const file = path.resolve(directory, "." + pathname);
    const relative = path.relative(directory, file);
    if (
        relative == ".." ||
        relative.startsWith(".." + path.sep) ||
        path.isAbsolute(relative)
    ) {
        return new Response(null, { status: 404 });
    }

    const asset = relative ? file : path.join(directory, "index.html");
    let resolvedFile = (await statIfPresent(asset))?.isFile()
        ? asset
        : undefined;
    if (!resolvedFile && !path.extname(asset)) {
        const html = asset + ".html";
        if ((await statIfPresent(html))?.isFile()) resolvedFile = html;
    }

    const headers = new Headers();
    const range = request.headers.get("Range");
    if (resolvedFile && range) headers.set("Range", range);
    const response = await net.fetch(
        pathToFileURL(resolvedFile ?? path.join(directory, "404.html")).href,
        { headers },
    );
    if (resolvedFile && request.method == "GET") return response;
    if (request.method == "HEAD") await response.body?.cancel();
    return new Response(request.method == "HEAD" ? null : response.body, {
        status: resolvedFile ? response.status : 404,
        headers: response.headers,
    });
};

const statIfPresent = async (file: string) => {
    try {
        return await stat(file);
    } catch (error) {
        const { code } = error as NodeJS.ErrnoException;
        if (code != "ENOENT" && code != "ENOTDIR") throw error;
        return undefined;
    }
};
