import { afterEach, beforeEach, expect, test, vi } from "vitest";
import {
    clearSpaceMediaLoadCooldown,
    loadSpaceMedia,
    SpaceMediaRateLimitError,
} from "../src/services/media-load";

beforeEach(() => {
    vi.useFakeTimers();
    clearSpaceMediaLoadCooldown();
});

afterEach(() => {
    clearSpaceMediaLoadCooldown();
    vi.useRealTimers();
});

test("a rate limit pauses other media requests without extending the cooldown on retry", async () => {
    const cause = Object.assign(new Error("Rate limit breached"), {
        status: 429,
    });
    const first = vi.fn().mockRejectedValue(cause);
    const second = vi.fn().mockResolvedValue("photo");
    const error = await loadSpaceMedia(first).catch((error: unknown) => error);
    expect(error).toBeInstanceOf(SpaceMediaRateLimitError);
    expect((error as SpaceMediaRateLimitError).cause).toBe(cause);
    await vi.advanceTimersByTimeAsync(59_999);
    await expect(loadSpaceMedia(second)).rejects.toBe(error);
    expect(second).not.toHaveBeenCalled();
    await vi.advanceTimersByTimeAsync(1);
    await expect(loadSpaceMedia(second)).resolves.toBe("photo");
    expect(second).toHaveBeenCalledOnce();
});

test("network errors do not impose a rate-limit cooldown", async () => {
    const error = new Error("Offline");
    await expect(loadSpaceMedia(() => Promise.reject(error))).rejects.toBe(
        error,
    );
    await expect(loadSpaceMedia(() => Promise.resolve("video"))).resolves.toBe(
        "video",
    );
});

test("clearing the session clears the media cooldown", async () => {
    await expect(
        loadSpaceMedia(() =>
            Promise.reject(
                Object.assign(new Error("Rate limit"), { status: 429 }),
            ),
        ),
    ).rejects.toBeInstanceOf(SpaceMediaRateLimitError);
    clearSpaceMediaLoadCooldown();
    await expect(
        loadSpaceMedia(() => Promise.resolve("new session")),
    ).resolves.toBe("new session");
});
