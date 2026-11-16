import { renderToStaticMarkup } from "react-dom/server";
import { beforeEach, expect, test, vi } from "vitest";
import {
    toggleUploadDestination,
    updateUploadDestinations,
    uploadDestinationsByItem,
    uploadQueueItemKey,
    type UploadDestination,
} from "../src/components/create-item/file-upload-helpers";
import { useUploadQueue } from "../src/components/create-item/use-upload-queue";
import type { LockerCollection } from "../src/types";

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
            eligibleCollections: [],
            selectedUploadItems: files(),
            uploadDestinations: {},
            setUploadDestinations: vi.fn(),
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

const collection = (id: number, name: string): LockerCollection => ({
    id,
    name,
    owner: { id: 1 },
    items: [],
    sharees: [],
    type: "folder",
    isShared: false,
});

const existing = (id: number): UploadDestination => ({ kind: "existing", id });

test.each([
    [
        "identical names",
        [collection(1, "Documents"), collection(2, "Documents")],
    ],
    [
        "normalized name matches",
        [collection(1, "Documents"), collection(2, " documents ")],
    ],
    [
        "reordered collections",
        [collection(2, "Documents"), collection(1, "Documents")],
    ],
    [
        "a renamed collection",
        [collection(1, "New name"), collection(2, "Documents")],
    ],
])(
    "the selected ID reaches the upload callback with %s",
    async (_case, eligibleCollections) => {
        const items = files().slice(0, 1);
        const selection = uploadDestinationsByItem(items, [], 1);
        const create = vi.fn();
        await queueFor({
            selectedUploadItems: items,
            eligibleCollections,
            uploadDestinations: selection,
            onCreateUploadCollection: create,
        }).upload(complete);
        expect(upload.mock.calls.map(([, ids]) => ids)).toEqual([[1]]);
        expect(create).not.toHaveBeenCalled();
    },
);

test("batch and per-file choices reach the upload callback by ID", async () => {
    const items = files();
    const collections = [collection(1, "First"), collection(2, "Second")];
    const all = updateUploadDestinations(
        {},
        undefined,
        items,
        new Set(),
        () => [existing(1)],
    );
    const uploadDestinations = updateUploadDestinations(
        all,
        uploadQueueItemKey(items[1]!),
        items,
        new Set(),
        (current) => toggleUploadDestination(current, existing(2), collections),
    );
    await queueFor({
        selectedUploadItems: items,
        eligibleCollections: collections,
        uploadDestinations,
    }).upload(complete);
    expect(upload.mock.calls.map(([file, ids]) => [file.name, ids])).toEqual([
        ["one.txt", [1]],
        ["two.txt", [1, 2]],
    ]);
});

test("folder suggestions select a unique ID or defer to a user choice", async () => {
    const [first, second] = files();
    const unique = { ...first!, suggestedCollectionNames: ["Tax"] };
    const ambiguous = { ...second!, suggestedCollectionNames: ["Documents"] };
    const items = [unique, ambiguous];
    const eligibleCollections = [
        collection(1, "Tax"),
        collection(2, "Documents"),
        collection(3, " documents "),
    ];
    const selections = uploadDestinationsByItem(items, eligibleCollections);
    const create = vi.fn();
    const props = {
        selectedUploadItems: items,
        eligibleCollections,
        onCreateUploadCollection: create,
    };

    await queueFor({ ...props, uploadDestinations: selections }).upload(
        complete,
    );
    expect(error).toHaveBeenCalledWith("uploadDestinationNeedsChoice");
    expect(upload).not.toHaveBeenCalled();
    expect(create).not.toHaveBeenCalled();

    const uploadDestinations = updateUploadDestinations(
        selections,
        uploadQueueItemKey(ambiguous),
        items,
        new Set(),
        (current) =>
            toggleUploadDestination(current, existing(3), eligibleCollections),
    );
    await queueFor({ ...props, uploadDestinations }).upload(complete);
    expect(upload.mock.calls.map(([, ids]) => ids)).toEqual([[1], [3]]);
});

test.each([
    [
        { kind: "existing", id: 999 } satisfies UploadDestination,
        "uploadDestinationUnavailable",
    ],
    [
        { kind: "new", name: " existing " } satisfies UploadDestination,
        "uploadDestinationNeedsChoice",
    ],
])(
    "an invalid destination stops the batch before creation or upload",
    async (destination, message) => {
        const [first, second] = files();
        const create = vi.fn();
        await queueFor({
            selectedUploadItems: [first!, second!],
            eligibleCollections: [collection(1, "Existing")],
            uploadDestinations: {
                [uploadQueueItemKey(first!)]: [{ kind: "new", name: "New" }],
                [uploadQueueItemKey(second!)]: [destination],
            },
            onCreateUploadCollection: create,
        }).upload(complete);
        expect(error).toHaveBeenCalledWith(message);
        expect(upload).not.toHaveBeenCalled();
        expect(create).not.toHaveBeenCalled();
    },
);

test("a retry reuses a successfully created collection after partial failure", async () => {
    const [first, second] = files();
    const items = [
        { ...first!, suggestedCollectionNames: ["New"] },
        { ...second!, suggestedCollectionNames: [" new ", "Another"] },
    ];
    let selections = uploadDestinationsByItem(items, []);
    const create = vi
        .fn<NonNullable<Props["onCreateUploadCollection"]>>()
        .mockResolvedValueOnce(8)
        .mockRejectedValueOnce(new Error("network"))
        .mockResolvedValueOnce(9);
    const refresh = vi
        .fn<NonNullable<Props["onRefreshUploadCollections"]>>()
        .mockResolvedValueOnce([collection(8, "New")])
        .mockResolvedValueOnce([
            collection(8, "New"),
            collection(9, "Another"),
        ]);
    const setUploadDestinations: Props["setUploadDestinations"] = (update) => {
        selections = typeof update === "function" ? update(selections) : update;
    };
    const props = {
        selectedUploadItems: items,
        onCreateUploadCollection: create,
        onRefreshUploadCollections: refresh,
        setUploadDestinations,
    };

    await queueFor({ ...props, uploadDestinations: selections }).upload(
        complete,
    );
    expect(upload).not.toHaveBeenCalled();
    expect(refresh).toHaveBeenCalledOnce();

    await queueFor({
        ...props,
        eligibleCollections: [collection(8, "New")],
        uploadDestinations: selections,
    }).upload(complete);
    expect(create.mock.calls).toEqual([["New"], ["Another"], ["Another"]]);
    expect(upload.mock.calls.map(([, ids]) => ids)).toEqual([[8], [8, 9]]);
});

test("a retry syncs a created collection before uploading to its saved ID", async () => {
    const items = files()
        .slice(0, 1)
        .map((item) => ({ ...item, suggestedCollectionNames: ["New"] }));
    let selections = uploadDestinationsByItem(items, []);
    const create = vi
        .fn<NonNullable<Props["onCreateUploadCollection"]>>()
        .mockResolvedValue(8);
    const refresh = vi
        .fn<NonNullable<Props["onRefreshUploadCollections"]>>()
        .mockResolvedValueOnce(undefined)
        .mockResolvedValueOnce([collection(8, "New")]);
    const setUploadDestinations: Props["setUploadDestinations"] = (update) => {
        selections = typeof update === "function" ? update(selections) : update;
    };
    const props = {
        selectedUploadItems: items,
        onCreateUploadCollection: create,
        onRefreshUploadCollections: refresh,
        setUploadDestinations,
    };

    await queueFor({ ...props, uploadDestinations: selections }).upload(
        complete,
    );
    expect(error).toHaveBeenCalledWith("generic_error_retry");
    expect(upload).not.toHaveBeenCalled();

    await queueFor({ ...props, uploadDestinations: selections }).upload(
        complete,
    );
    expect(create).toHaveBeenCalledExactlyOnceWith("New");
    expect(refresh).toHaveBeenCalledTimes(2);
    expect(upload.mock.calls.map(([, ids]) => ids)).toEqual([[8]]);
});

test("a file without a destination uses the upload service's Uncategorized fallback", async () => {
    await queueFor({ selectedUploadItems: files().slice(0, 1) }).upload(
        complete,
    );
    expect(upload.mock.calls.map(([, ids]) => ids)).toEqual([[]]);
});
