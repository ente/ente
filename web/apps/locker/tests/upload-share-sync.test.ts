import { afterEach, beforeEach, expect, test, vi } from "vitest";
import { retryUploadShareSync } from "../src/components/locker/upload-share-sync";

vi.mock("ente-base/log", () => ({ default: { error: vi.fn() } }));
beforeEach(() => vi.useFakeTimers());
afterEach(() => vi.useRealTimers());

test("sync retries continue beyond the initial six-second follow-ups", async () => {
    const refresh = vi.fn(() => Promise.resolve());
    const stop = retryUploadShareSync(refresh);
    await vi.advanceTimersByTimeAsync(12000);
    expect(refresh).toHaveBeenCalledTimes(6);
    stop();
    await vi.advanceTimersByTimeAsync(10000);
    expect(refresh).toHaveBeenCalledTimes(6);
});

test("a transient failure does not stop future attempts", async () => {
    const refresh = vi
        .fn()
        .mockRejectedValueOnce(new Error("offline"))
        .mockResolvedValue(undefined);
    const stop = retryUploadShareSync(refresh);
    await vi.advanceTimersByTimeAsync(4000);
    expect(refresh).toHaveBeenCalledTimes(2);
    stop();
});

test("slow sync requests never overlap and cleanup prevents rescheduling", async () => {
    let finish!: () => void;
    const refresh = vi.fn(
        () =>
            new Promise<void>((resolve) => {
                finish = resolve;
            }),
    );
    const stop = retryUploadShareSync(refresh);
    await vi.advanceTimersByTimeAsync(20000);
    expect(refresh).toHaveBeenCalledOnce();
    stop();
    finish();
    await vi.advanceTimersByTimeAsync(10000);
    expect(refresh).toHaveBeenCalledOnce();
});

test("closing the prompt before a retry cancels the pending timer", async () => {
    const refresh = vi.fn(() => Promise.resolve());
    const stop = retryUploadShareSync(refresh);
    stop();
    await vi.advanceTimersByTimeAsync(10000);
    expect(refresh).not.toHaveBeenCalled();
});
