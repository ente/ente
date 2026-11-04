interface Env {
    GITHUB_REPOSITORY: string;
    GITHUB_TOKEN: string;
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
        const context = [
            `CLI version: ${value.version}`,
            `OS: ${value.os}`,
            `Receipt: ${id}`,
        ].join("\n");
        try {
            const response = await fetch(
                `https://api.github.com/repos/${env.GITHUB_REPOSITORY}/issues`,
                {
                    method: "POST",
                    headers: {
                        Authorization: `Bearer ${env.GITHUB_TOKEN}`,
                        Accept: "application/vnd.github+json",
                        "Content-Type": "application/json",
                        "User-Agent": "ente-feedback",
                        "X-GitHub-Api-Version": "2026-03-10",
                    },
                    body: JSON.stringify({
                        title: Array.from(
                            value.message.trim().replace(/\s+/gu, " "),
                        )
                            .slice(0, 100)
                            .join(""),
                        body: `${codeBlock(context)}\n\n${codeBlock(value.message)}`,
                    }),
                    redirect: "manual",
                    signal: AbortSignal.timeout(15_000),
                },
            );
            await response.body?.cancel();
            if (response.status === 201)
                return Response.json({ id }, { status: 201 });
            console.error(
                `GitHub feedback submission returned ${response.status}`,
            );
        } catch {
            console.error("Could not confirm GitHub feedback submission");
        }
        return error("Could not confirm feedback submission", 502);
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

const codeBlock = (text: string) =>
    text
        .replace(/\r\n?/g, "\n")
        .split("\n")
        .map((line) => `    ${line}`)
        .join("\n");
