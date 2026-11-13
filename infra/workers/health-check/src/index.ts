export default {
    async scheduled(_, env: Env, ctx: ExecutionContext) {
        ctx.waitUntil(ping(env, ctx));
    },
} satisfies ExportedHandler<Env>;

interface Env {
    NOTIFY_URL: string;
    CHAT_ID: string;
}

const ping = async (env: Env, ctx: ExecutionContext) => {
    const notify = async (msg: string) =>
        sendMessage(`${msg} on ${Date()}`, env);

    try {
        let timeout = setTimeout(() => {
            ctx.waitUntil(notify("Ping timed out"));
        }, 5000);
        const res = await fetch("https://api.ente.com/ping", {
            headers: {
                "User-Agent": "health-check",
            },
        });
        clearTimeout(timeout);
        if (!res.ok) await notify(`Ping failed (HTTP ${res.status})`);
    } catch (e) {
        await notify(`Ping failed (${e instanceof Error ? e.message : e})`);
    }
};

const sendMessage = async (message: string, env: Env) => {
    console.log(message);
    const res = await fetch(env.NOTIFY_URL, {
        method: "POST",
        headers: {
            "Content-Type": "application/json",
        },
        body: JSON.stringify({
            chat_id: parseInt(env.CHAT_ID),
            parse_mode: "html",
            text: message,
        }),
    });
    if (!res.ok) throw new Error(`Failed to sendMessage (HTTP ${res.status})`);
};
