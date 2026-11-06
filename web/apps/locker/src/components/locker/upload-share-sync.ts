import log from "ente-base/log";

export function retryUploadShareSync(refreshData: () => Promise<void>) {
    let cancelled = false;
    let timeout: ReturnType<typeof setTimeout>;
    const retry = async () => {
        try {
            await refreshData();
        } catch (error) {
            log.error("Failed to sync uploaded file for sharing", error);
        } finally {
            if (!cancelled) schedule();
        }
    };
    const schedule = () => {
        timeout = setTimeout(() => void retry(), 2000);
    };
    schedule();
    return () => {
        cancelled = true;
        clearTimeout(timeout);
    };
}
