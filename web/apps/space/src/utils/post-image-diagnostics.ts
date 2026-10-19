import { logToDisk } from "ente-base/log-web";

const checkedFiles = new WeakSet<File>();

export const logSpaceImageReadCheck = async (
    file: File,
    preparationError: unknown,
    context: { requestId?: string; attempt: number; item: number },
) => {
    if (
        !(preparationError instanceof Error) ||
        preparationError.message != "Could not decode image" ||
        checkedFiles.has(file)
    )
        return;
    checkedFiles.add(file);

    const { requestId, attempt, item } = context;
    const startedAt = performance.now();
    logToDisk(
        `[info] Space image prefix read check ${JSON.stringify({ requestId, attempt, item, outcome: "started" })}`,
    );
    let outcome = "prefix-readable";
    let error: string | undefined;
    try {
        await file.slice(0, 64 * 1024).arrayBuffer();
    } catch (cause) {
        outcome = "failed";
        const name = cause instanceof Error ? cause.name : "Unknown";
        error = [
            "NotReadableError",
            "NotFoundError",
            "SecurityError",
            "AbortError",
            "InvalidStateError",
            "TypeError",
            "RangeError",
        ].includes(name)
            ? name
            : "Unknown";
    }
    logToDisk(
        `[info] Space image prefix read check ${JSON.stringify({ requestId, attempt, item, outcome, error, elapsedMs: Math.round(performance.now() - startedAt) })}`,
    );
};
