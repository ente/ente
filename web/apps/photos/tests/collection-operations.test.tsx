import type { Collection } from "ente-media/collection";
import type { EnteFile } from "ente-media/file";
import { renderToStaticMarkup } from "react-dom/server";
import { beforeEach, expect, test, vi } from "vitest";
import { useCollectionOperations } from "../src/components/gallery/media/use-collection-operations";
import { initialGalleryState } from "../src/components/gallery/reducer";

const services = vi.hoisted(() => ({
    createAlbum: vi.fn(),
    performCollectionOp: vi.fn(),
    onGenericError: vi.fn(),
}));

vi.mock("@/components/CollectionSelector", () => ({
    CollectionSelector: () => null,
}));
vi.mock("@/components/gallery/helpers", () => ({
    findCollectionCreatingIfNeeded: vi.fn(),
    performCollectionOp: services.performCollectionOp,
}));
vi.mock("@/components/utils/dialog-attributes", () => ({
    notifyOthersFilesDialogAttributes: vi.fn(),
}));
vi.mock("@/utils/file", () => import("../src/utils/file"));
vi.mock("@/services/save", () => ({ downloadAndSaveFiles: vi.fn() }));
vi.mock("ente-base/components/Notification", () => ({
    Notification: () => null,
}));
vi.mock("ente-base/components/SingleInputDialog", () => ({
    SingleInputDialog: () => null,
}));
vi.mock("ente-base/context", () => ({
    useBaseContext: () => ({
        showMiniDialog: vi.fn(),
        onGenericError: services.onGenericError,
    }),
}));
vi.mock("ente-new/photos/types/context", () => ({
    usePhotosAppContext: () => ({
        showLoadingBar: vi.fn(),
        hideLoadingBar: vi.fn(),
        showNotification: vi.fn(),
    }),
}));
vi.mock("ente-new/photos/services/collection", () => ({
    createAlbum: services.createAlbum,
    createHiddenAlbum: vi.fn(),
    canAddFilesToCollection: vi.fn(),
    removeFromCollection: vi.fn(),
}));

const album: Collection = {
    id: 20,
    name: "New album",
    type: "album",
    owner: { id: 1 },
    key: "album-key",
    sharees: [],
    publicURLs: [],
    updationTime: 1,
};
const files: EnteFile[] = [1, 2, 3].map((id) => ({
    id,
    collectionID: 10,
    ownerID: 1,
    key: "file-key",
    file: { decryptionHeader: "" },
    thumbnail: { decryptionHeader: "" },
    updationTime: id,
    metadata: {
        fileType: 0,
        title: `${id}.jpg`,
        creationTime: id,
        modificationTime: id,
    },
}));

beforeEach(() => {
    vi.clearAllMocks();
    services.createAlbum.mockReset().mockResolvedValue(album);
    services.performCollectionOp.mockResolvedValue(undefined);
});

const openAddDialog = () => {
    let operations: ReturnType<typeof useCollectionOperations>;
    let initialized = false;
    const Harness = () => {
        operations = useCollectionOperations({
            state: {
                ...initialGalleryState,
                user: {
                    id: 1,
                    email: "review@example.test",
                    token: "test-token",
                },
            },
            selected: {
                1: true,
                2: true,
                count: 2,
                ownCount: 2,
                collectionID: 10,
                context: undefined,
            },
            filteredFiles: files,
            barMode: "albums",
            clearSelection: vi.fn(),
            remotePull: vi.fn().mockResolvedValue(undefined),
        });
        if (!initialized) {
            initialized = true;
            operations.createOnCreateForCollectionOp("add")();
        }
        return null;
    };
    renderToStaticMarkup(<Harness />);
    const dialogProps = operations!.albumNameInputProps;
    return {
        operations: operations!,
        close: dialogProps.onClose,
        submit: () => dialogProps.onSubmit("New album", vi.fn()),
    };
};

test("closing a submitted dialog retains its selected photos", async () => {
    const creation = Promise.withResolvers<Collection>();
    services.createAlbum.mockReturnValueOnce(creation.promise);
    const dialog = openAddDialog();
    const submitted = dialog.submit();
    dialog.close();
    creation.resolve(album);
    await submitted;
    expect(services.performCollectionOp).toHaveBeenCalledExactlyOnceWith(
        "add",
        album,
        files.slice(0, 2),
        10,
    );
});

test("a newer operation cannot replace a pending album's operation", async () => {
    const creation = Promise.withResolvers<Collection>();
    services.createAlbum.mockReturnValueOnce(creation.promise);
    const dialog = openAddDialog();
    const submitted = dialog.submit();
    dialog.close();
    dialog.operations.createOnCreateForCollectionOp("move")();
    creation.resolve(album);
    await submitted;
    expect(services.performCollectionOp).toHaveBeenCalledExactlyOnceWith(
        "add",
        album,
        files.slice(0, 2),
        10,
    );
});

test("retrying a failed creation retains its selected photos", async () => {
    services.createAlbum.mockRejectedValueOnce(new Error("HTTP 500"));
    const dialog = openAddDialog();
    await expect(dialog.submit()).rejects.toThrow("HTTP 500");
    expect(services.performCollectionOp).not.toHaveBeenCalled();
    await dialog.submit();
    expect(services.performCollectionOp).toHaveBeenCalledExactlyOnceWith(
        "add",
        album,
        files.slice(0, 2),
        10,
    );
});
