import { afterEach, expect, test, vi } from "vitest";
import { pasteClient } from "../src/paste";

vi.mock("ente-base/origins", () => ({
    apiOrigin: () => Promise.resolve("http://localhost"),
}));

afterEach(() => vi.unstubAllGlobals());

test("failed worker startup rejects, terminates, and allows another attempt", async () => {
    class FailedWorker extends EventTarget {
        postMessage = vi.fn();
        terminate = vi.fn();
    }
    const workers: FailedWorker[] = [];
    vi.stubGlobal(
        "Worker",
        class extends FailedWorker {
            constructor() {
                super();
                workers.push(this);
            }
        },
    );

    for (let attempt = 1; attempt <= 2; attempt++) {
        const ready = pasteClient();
        await vi.waitFor(() => expect(workers).toHaveLength(attempt));
        const worker = workers[attempt - 1]!;
        worker.dispatchEvent(new Event("error"));
        await expect(ready).rejects.toThrow("Worker failed to start");
        expect(worker.terminate).toHaveBeenCalledOnce();
    }
});
