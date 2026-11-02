import type { Collection } from "ente-media/collection";
import type { EnteFile } from "ente-media/file";
import { renderToStaticMarkup } from "react-dom/server";
import { beforeEach, expect, test, vi } from "vitest";
import { useCollectionDialogs } from "../src/components/gallery/media/use-collection-dialogs";
import { useCollectionOperations } from "../src/components/gallery/media/use-collection-operations";
import { initialGalleryState } from "../src/components/gallery/reducer";

const services = vi.hoisted(() => ({
    createAlbum: vi.fn(),
    renameCollection: vi.fn(),
    performCollectionOp: vi.fn(),
    onGenericError: vi.fn(),
    hideLoadingBar: vi.fn(),
    showNotification: vi.fn(),
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
        hideLoadingBar: services.hideLoadingBar,
        showNotification: services.showNotification,
    }),
}));
vi.mock("ente-new/photos/services/collection", () => ({
    createAlbum: services.createAlbum,
    renameCollection: services.renameCollection,
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
    services.renameCollection.mockReset().mockResolvedValue(undefined);
    services.performCollectionOp.mockReset().mockResolvedValue(undefined);
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

const openSingleFileAddDialog = () => {
    let dialogs: ReturnType<typeof useCollectionDialogs>;
    let step = 0;
    const remotePull = vi.fn().mockResolvedValue(undefined);
    const Harness = () => {
        dialogs = useCollectionDialogs({
            state: initialGalleryState,
            remotePull,
        });
        if (step === 0) {
            step++;
            dialogs.handleAddSingleFileToCollection(files[0]!, 10);
        } else if (step === 1) {
            step++;
            dialogs.collectionSelectorProps.attributes!.onCreateCollection();
        }
        return null;
    };
    renderToStaticMarkup(<Harness />);
    return {
        remotePull,
        submit: (name = "New album") =>
            dialogs!.albumNameInputProps.onSubmit(name, vi.fn()),
        select: () =>
            dialogs!.collectionSelectorProps.attributes!.onSelectCollection(
                album,
            ),
    };
};

test("creating an album from the viewer adds the file and refreshes the gallery", async () => {
    const dialog = openSingleFileAddDialog();
    await dialog.submit();
    expect(services.performCollectionOp).toHaveBeenCalledExactlyOnceWith(
        "add",
        album,
        [files[0]],
        10,
    );
    expect(dialog.remotePull).toHaveBeenCalledExactlyOnceWith({
        silent: true,
        source: "single-file-add-to-album",
    });
    expect(services.showNotification).toHaveBeenCalledOnce();
    expect(services.hideLoadingBar).toHaveBeenCalledOnce();
});

test("a single-file add failure reaches the album-name form", async () => {
    services.performCollectionOp.mockRejectedValueOnce(new Error("HTTP 500"));
    const dialog = openSingleFileAddDialog();
    await expect(dialog.submit()).rejects.toThrow("HTTP 500");
    expect(services.onGenericError).not.toHaveBeenCalled();
    expect(services.showNotification).not.toHaveBeenCalled();
    expect(dialog.remotePull).not.toHaveBeenCalled();
    expect(services.hideLoadingBar).toHaveBeenCalledOnce();
});

test("retrying a failed single-file add reuses the created album", async () => {
    services.performCollectionOp.mockRejectedValueOnce(new Error("HTTP 500"));
    const dialog = openSingleFileAddDialog();
    await expect(dialog.submit()).rejects.toThrow("HTTP 500");
    await dialog.submit();
    expect(services.createAlbum).toHaveBeenCalledExactlyOnceWith("New album");
    expect(services.performCollectionOp).toHaveBeenCalledTimes(2);
    expect(services.performCollectionOp).toHaveBeenLastCalledWith(
        "add",
        album,
        [files[0]],
        10,
    );
    expect(dialog.remotePull).toHaveBeenCalledOnce();
    expect(services.showNotification).toHaveBeenCalledOnce();
});

test("retrying a failed refresh does not recreate the album or add the file again", async () => {
    const dialog = openSingleFileAddDialog();
    dialog.remotePull.mockRejectedValueOnce(new Error("HTTP 500"));
    await expect(dialog.submit()).rejects.toThrow("HTTP 500");
    expect(services.showNotification).not.toHaveBeenCalled();
    await dialog.submit();
    expect(services.createAlbum).toHaveBeenCalledOnce();
    expect(services.performCollectionOp).toHaveBeenCalledOnce();
    expect(dialog.remotePull).toHaveBeenCalledTimes(2);
    expect(services.showNotification).toHaveBeenCalledOnce();
});

test("a failed single-file album creation can be retried", async () => {
    services.createAlbum.mockRejectedValueOnce(new Error("HTTP 500"));
    const dialog = openSingleFileAddDialog();
    await expect(dialog.submit()).rejects.toThrow("HTTP 500");
    expect(services.performCollectionOp).not.toHaveBeenCalled();
    await dialog.submit();
    expect(services.createAlbum).toHaveBeenCalledTimes(2);
    expect(services.performCollectionOp).toHaveBeenCalledOnce();
    expect(dialog.remotePull).toHaveBeenCalledOnce();
});

test("editing the name on retry renames the same album and retains it after a rename failure", async () => {
    services.performCollectionOp.mockRejectedValueOnce(new Error("Add failed"));
    services.renameCollection.mockRejectedValueOnce(new Error("Rename failed"));
    const dialog = openSingleFileAddDialog();
    await expect(dialog.submit()).rejects.toThrow("Add failed");
    await expect(dialog.submit("Renamed album")).rejects.toThrow(
        "Rename failed",
    );
    expect(services.performCollectionOp).toHaveBeenCalledOnce();
    await dialog.submit("Renamed album");
    expect(services.createAlbum).toHaveBeenCalledOnce();
    expect(services.renameCollection).toHaveBeenCalledTimes(2);
    expect(services.renameCollection).toHaveBeenLastCalledWith(
        album,
        "Renamed album",
    );
    expect(services.performCollectionOp).toHaveBeenLastCalledWith(
        "add",
        { ...album, name: "Renamed album" },
        [files[0]],
        10,
    );
});

test("an existing-album add failure still reports a generic error", async () => {
    const error = new Error("HTTP 500");
    services.performCollectionOp.mockRejectedValueOnce(error);
    const dialog = openSingleFileAddDialog();
    dialog.select();
    await vi.waitFor(() =>
        expect(services.onGenericError).toHaveBeenCalledExactlyOnceWith(error),
    );
    expect(services.showNotification).not.toHaveBeenCalled();
    expect(services.hideLoadingBar).toHaveBeenCalledOnce();
});
