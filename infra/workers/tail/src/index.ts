export default {
    async tail(events: TraceItem[], env: Env) {
        // If the tail worker itself throws an exception (it shouldn't, unless
        // Loki is down), we don't catch it so that it counts as an "error" in
        // the worker stats.
        await handleTail(events, env);
    },
} satisfies ExportedHandler<Env>;

interface Env {
    LOKI_PUSH_URL: string;
    // Worker fetch does not accept credentials in the Loki URL.
    // This secret is base64-encoded `user:pass` for the Basic header.
    LOKI_AUTH: string;
}

const handleTail = async (events: TraceItem[], env: Env) => {
    for (const event of events.filter(hasLogOrException))
        await pushLogLine(Date.now(), JSON.stringify(event), env);
};

const hasLogOrException = (event: TraceItem) =>
    event.logs.length || event.exceptions.length;

const pushLogLine = async (timestampMs: number, logLine: string, env: Env) =>
    await fetch(env.LOKI_PUSH_URL, {
        method: "POST",
        headers: {
            "Content-Type": "application/json",
            Authorization: `Basic ${env.LOKI_AUTH}`,
        },
        body: JSON.stringify({
            streams: [
                {
                    stream: { job: "worker" },
                    values: [[`${timestampMs * 1e6}`, logLine]],
                },
            ],
        }),
    });
