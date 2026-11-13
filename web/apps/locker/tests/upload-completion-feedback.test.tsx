import { renderToStaticMarkup } from "react-dom/server";
import { afterEach, beforeEach, expect, test, vi } from "vitest";
import { useLockerUploads } from "../src/components/locker/use-locker-uploads";

vi.mock("../src/services/uploads", () => ({ uploadLockerFile: vi.fn() }));
vi.mock("ente-base/log", () => ({ default: { error: vi.fn() } }));
vi.mock("i18next", () => ({ t: (key: string) => key }));

beforeEach(() => {
    vi.useFakeTimers();
    vi.stubGlobal("window", globalThis);
});
afterEach(() => {
    vi.clearAllTimers();
    vi.useRealTimers();
    vi.unstubAllGlobals();
});

const completion = () => {
    const setToast = vi.fn();
    const refreshData = vi.fn(() => Promise.resolve());
    let uploads: ReturnType<typeof useLockerUploads>;
    function Harness() {
        uploads = useLockerUploads({
            refreshData,
            setToast,
            ensureUploadLimitState: () => Promise.resolve(undefined),
        });
        return null;
    }
    renderToStaticMarkup(<Harness />);
    return { finished: uploads!.handleUploadsFinished, setToast, refreshData };
};

test("single-file completion clears the toast instead of covering the share sheet", async () => {
    const { finished, setToast, refreshData } = completion();
    await finished(1, 1);
    expect(setToast).toHaveBeenCalledExactlyOnceWith(null);
    expect(refreshData).toHaveBeenCalledOnce();
});

test("batch completion keeps its completion toast", async () => {
    const { finished, setToast } = completion();
    await finished(2, 2);
    expect(setToast).toHaveBeenCalledExactlyOnceWith("uploadMultipleComplete");
});

test("a partially successful batch keeps completion feedback", async () => {
    const { finished, setToast } = completion();
    await finished(1, 2);
    expect(setToast).toHaveBeenCalledExactlyOnceWith("uploadComplete");
});
