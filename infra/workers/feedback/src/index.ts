interface Env {
    DB: D1Database;
    SUBMISSIONS: RateLimit;
}

interface Feedback {
    message: string;
    version: string;
    os: string;
}

export default {
    async fetch(request: Request, env: Env) {
        if (request.method !== "POST")
            return new Response(null, {
                status: 405,
                headers: { Allow: "POST" },
            });
        const contentType = request.headers.get("Content-Type") ?? "";
        if (!/^application\/json(?:\s*;|$)/i.test(contentType))
            return error("Expected application/json", 415);
        const { success } = await env.SUBMISSIONS.limit({
            key: request.headers.get("CF-Connecting-IP") ?? "local",
        });
        if (!success)
            return Response.json(
                { error: "Too many submissions" },
                { status: 429, headers: { "Retry-After": "60" } },
            );
        if (!request.body) return error("Missing feedback", 400);
        let value: unknown;
        try {
            const bytes = new Uint8Array(16 * 1024);
            let length = 0;
            for await (const chunk of request.body) {
                if (length + chunk.length > bytes.length)
                    return error("Request is too large", 413);
                bytes.set(chunk, length);
                length += chunk.length;
            }
            value = JSON.parse(
                new TextDecoder("utf-8", {
                    fatal: true,
                    ignoreBOM: false,
                }).decode(bytes.subarray(0, length)),
            );
        } catch {
            return error("Invalid JSON", 400);
        }
        if (!isFeedback(value)) return error("Invalid feedback", 400);

        const id = crypto.randomUUID();
        try {
            await env.DB.prepare(
                "INSERT INTO feedback (id, message, version, os) VALUES (?, ?, ?, ?)",
            )
                .bind(id, value.message, value.version, value.os)
                .run();
            return Response.json({ id }, { status: 201 });
        } catch {
            console.error("Could not confirm feedback submission");
            return error("Could not confirm feedback submission", 500);
        }
    },
} satisfies ExportedHandler<Env>;

const error = (message: string, status: number) =>
    Response.json({ error: message }, { status });

const isText = (value: unknown, max: number): value is string =>
    typeof value === "string" &&
    value.trim().length > 0 &&
    Array.from(value).length <= max;

const isLine = (value: unknown, max: number): value is string =>
    isText(value, max) && !/\p{Cc}/u.test(value);

const isFeedback = (value: unknown): value is Feedback =>
    typeof value === "object" &&
    value !== null &&
    "message" in value &&
    isText(value.message, 2_000) &&
    !/\p{Cc}/u.test(value.message.replace(/[\r\n\t]/g, "")) &&
    "version" in value &&
    isLine(value.version, 64) &&
    "os" in value &&
    isLine(value.os, 32);
