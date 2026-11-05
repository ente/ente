export default {
    async fetch(request: Request) {
        switch (request.method) {
            case "OPTIONS":
                return handleOPTIONS();
            case "POST":
                return handlePOSTOrPUT(request);
            case "PUT":
                return handlePOSTOrPUT(request);
            default:
                console.log(`Unsupported HTTP method ${request.method}`);
                return new Response(null, { status: 405 });
        }
    },
} satisfies ExportedHandler;

const ALLOWED_UPLOAD_HOSTS = new Set<string>([
    "ente-prod-eu.s3.eu-central-003.backblazeb2.com",
    "ente-prod-v3.s3.eu-central-2.wasabisys.com",
]);

const isAllowedUploadURL = (uploadURL: string) => {
    try {
        const url = new URL(uploadURL);
        if (url.protocol !== "https:") return false;
        if (url.username || url.password) return false;
        if (url.port && url.port !== "443") return false;
        if (!ALLOWED_UPLOAD_HOSTS.has(url.hostname)) return false;
        return true;
    } catch {
        return false;
    }
};

const handleOPTIONS = () =>
    new Response("", {
        headers: {
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "POST, PUT, OPTIONS",
            "Access-Control-Allow-Headers":
                "Content-Type, Content-MD5, UPLOAD-URL, X-Client-Package, X-Client-Version",
            "Access-Control-Expose-Headers": "X-Request-Id, CF-Ray",
            "Access-Control-Max-Age": "86400",
        },
    });

const handlePOSTOrPUT = async (request: Request) => {
    const url = new URL(request.url);

    const uploadURL = request.headers.get("UPLOAD-URL");
    if (!uploadURL) {
        console.error("No uploadURL provided");
        return new Response(null, { status: 400 });
    }
    if (!isAllowedUploadURL(uploadURL)) {
        console.warn("Blocked uploadURL due to allowlist");
        return new Response(JSON.stringify({ error: "host not whitelisted" }), {
            status: 400,
            headers: {
                "Content-Type": "application/json",
                "Access-Control-Allow-Origin": "*",
                "Access-Control-Expose-Headers": "X-Request-Id, CF-Ray",
            },
        });
    }

    const forwardHeaders = buildForwardHeaders(request);

    let response: Response;
    switch (url.pathname) {
        case "/file-upload":
            response = await fetch(uploadURL, {
                method: request.method,
                body: request.body,
                ...(forwardHeaders ? { headers: forwardHeaders } : {}),
            });
            break;
        case "/multipart-upload":
            response = await fetch(uploadURL, {
                method: request.method,
                body: request.body,
                ...(forwardHeaders ? { headers: forwardHeaders } : {}),
            });
            if (response.ok) {
                const etag = response.headers.get("etag");
                if (etag === null) {
                    console.log("No etag in response");
                    response = new Response(null, { status: 500 });
                } else {
                    response = new Response(JSON.stringify({ etag }), {
                        headers: {
                            "Content-Type": "application/json",
                        },
                    });
                }
            }
            break;
        case "/multipart-complete":
            response = await fetch(uploadURL, {
                method: request.method,
                body: request.body,
                headers: {
                    "Content-Type": "text/xml",
                },
            });
            break;
        default:
            return new Response(null, { status: 404 });
    }

    if (!response.ok) console.log("Upstream error", response.status);

    response = new Response(response.body, response);
    response.headers.set("Access-Control-Allow-Origin", "*");
    response.headers.set(
        "Access-Control-Expose-Headers",
        "X-Request-Id, CF-Ray",
    );
    return response;
};

const buildForwardHeaders = (
    request: Request,
): Record<string, string> | undefined => {
    const headers: Record<string, string> = {};
    const contentMd5 =
        request.headers.get("CONTENT-MD5") ??
        request.headers.get("Content-MD5");
    if (contentMd5) {
        headers["Content-MD5"] = contentMd5;
    }
    const contentLength = request.headers.get("Content-Length");
    if (contentLength) {
        headers["Content-Length"] = contentLength;
    }
    const contentType = request.headers.get("Content-Type");
    if (contentType) {
        headers["Content-Type"] = contentType;
    }
    return Object.keys(headers).length ? headers : undefined;
};
