import { renderToStaticMarkup } from "react-dom/server";
import { beforeEach, expect, test, vi } from "vitest";
import { useUploadQueue } from "../src/components/create-item/use-upload-queue";

vi.mock("../src/services/locker-errors", () => ({
    formatLockerMutationError: () => Promise.resolve("Upload failed"),
    lockerUpgradeCTAType: () => Promise.resolve(null),
}));
vi.mock("ente-base/log", () => ({ default: { error: vi.fn() } }));
vi.mock("i18next", () => ({ t: (key: string) => key }));

type Props = Parameters<typeof useUploadQueue>[0];
const allowance = {
    usage: 0,
    storageLimit: 1024,
    fileCount: 0,
    lockerFileLimit: 100,
    isPartOfFamily: false,
};
const files = () =>
    ["one.txt", "two.txt"].map((name) => ({
        file: new File(["test"], name),
        suggestedCollectionNames: [],
    }));
const upload = vi.fn<NonNullable<Props["onUploadProgress"]>>();
const finished = vi.fn<NonNullable<Props["onUploadsFinished"]>>();
const complete = vi.fn();
const error = vi.fn();
function queueFor(overrides: Partial<Props> = {}) {
    let queue: ReturnType<typeof useUploadQueue>;
    function Harness() {
        queue = useUploadQueue({
            displayCollections: [],
            selectedUploadItems: files(),
            selectedCollectionNamesByFileKey: {},
            userDetails: allowance,
            setError: error,
            setUpgradeCTAType: vi.fn(),
            onUploadProgress: upload,
            onUploadsFinished: finished,
            ...overrides,
        });
        return null;
    }
    renderToStaticMarkup(<Harness />);
    return queue!;
}
beforeEach(() => {
    vi.clearAllMocks();
    upload.mockResolvedValue(undefined);
});

test("single-file completion reports one selected file", async () => {
    await queueFor({ selectedUploadItems: files().slice(0, 1) }).upload(
        complete,
    );
    expect(finished).toHaveBeenCalledExactlyOnceWith(1, 1);
    expect(complete).toHaveBeenCalledOnce();
});

test("a partial batch reports its original selection size", async () => {
    upload.mockImplementation((file) =>
        file.name === "two.txt"
            ? Promise.reject(new Error("network"))
            : Promise.resolve(),
    );
    await queueFor().upload(complete);
    expect(finished).toHaveBeenCalledExactlyOnceWith(1, 2);
    expect(complete).not.toHaveBeenCalled();
});

test("all failed uploads do not invoke completion or sharing", async () => {
    upload.mockRejectedValue(new Error("network"));
    await queueFor().upload(complete);
    expect(finished).not.toHaveBeenCalled();
    expect(complete).not.toHaveBeenCalled();
});

test("a successful batch reports both files and closes the upload dialog", async () => {
    await queueFor().upload(complete);
    expect(finished).toHaveBeenCalledExactlyOnceWith(2, 2);
    expect(complete).toHaveBeenCalledOnce();
});

test.each([
    ["file count", { ...allowance, fileCount: 100 }],
    ["storage", { ...allowance, storageLimit: 0 }],
])("%s preflight failure never starts uploads", async (_name, userDetails) => {
    await queueFor({ userDetails }).upload(complete);
    expect(upload).not.toHaveBeenCalled();
    expect(finished).not.toHaveBeenCalled();
    expect(complete).not.toHaveBeenCalled();
    expect(error).toHaveBeenCalled();
});

test("missing allowance data never starts an upload", async () => {
    await queueFor({ userDetails: undefined }).upload(complete);
    expect(upload).not.toHaveBeenCalled();
    expect(finished).not.toHaveBeenCalled();
});

test("an oversized file is rejected before it is read or uploaded", async () => {
    const items = files().slice(0, 1);
    Object.defineProperty(items[0]!.file, "size", {
        value: 10 * 1024 ** 3 + 1,
    });
    await queueFor({ selectedUploadItems: items }).upload(complete);
    expect(upload).not.toHaveBeenCalled();
    expect(finished).not.toHaveBeenCalled();
});
