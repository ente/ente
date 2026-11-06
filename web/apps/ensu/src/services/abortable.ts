export const abortable = async <T>(
    operation: Promise<T>,
    signal: AbortSignal,
): Promise<T> => {
    let abort: () => void = () => undefined;
    try {
        return await Promise.race([
            new Promise<never>((_, reject) => {
                abort = () => {
                    const reason: unknown = signal.reason;
                    reject(
                        reason instanceof Error
                            ? reason
                            : new DOMException(
                                  "Operation cancelled",
                                  "AbortError",
                              ),
                    );
                };
                if (signal.aborted) abort();
                else signal.addEventListener("abort", abort, { once: true });
            }),
            operation,
        ]);
    } finally {
        signal.removeEventListener("abort", abort);
    }
};
