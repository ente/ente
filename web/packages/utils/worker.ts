export const workerReady = async <T>(
    worker: Worker,
    ready: Promise<T>,
): Promise<T> => {
    let onError!: (event: ErrorEvent) => void;
    const failed = new Promise<never>((_, reject) => {
        onError = (event) =>
            reject(new Error(event.message || "Worker failed to start"));
        worker.addEventListener("error", onError);
    });
    try {
        return await Promise.race([ready, failed]);
    } catch (error) {
        worker.terminate();
        throw error;
    } finally {
        worker.removeEventListener("error", onError);
    }
};
