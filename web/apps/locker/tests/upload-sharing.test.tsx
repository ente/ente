import { renderToStaticMarkup } from "react-dom/server";
import { beforeEach, expect, test, vi } from "vitest";
import { UploadShareDialog } from "../src/components/locker/UploadShareDialog";
import type { LockerCollection, LockerItem } from "../src/types";

const { confirm, openLink, close } = vi.hoisted(() => ({
    confirm: vi.fn(),
    openLink: vi.fn(),
    close: vi.fn(),
}));
vi.mock("../src/components/ui/LockerConfirmDialog", () => ({
    LockerConfirmDialog: (props: unknown) => {
        confirm(props);
        return null;
    },
}));
vi.mock("../src/components/items/LockerFileLinkDialog", () => ({
    LockerFileLinkDialog: () => null,
}));
vi.mock("../src/components/items/use-file-link", () => ({
    useFileLink: () => ({
        activeFileLinkItem: null,
        openFileLinkDialog: openLink,
    }),
}));
vi.mock("ente-accounts/services/accounts-db", () => ({
    savedLocalUser: () => ({ id: 1 }),
}));
vi.mock("i18next", () => ({ t: (key: string) => key }));

const item: LockerItem = {
    id: 42,
    ownerID: 1,
    type: "file",
    data: { name: "Renamed document.pdf" },
    collectionID: 7,
    collectionIDs: [7],
};
const collection: LockerCollection = {
    id: 7,
    name: "Documents",
    owner: { id: 1 },
    sharees: [],
    items: [item],
    type: "folder",
    isShared: false,
};
const render = (fileIDs = [42], collections = [collection]) =>
    renderToStaticMarkup(
        <UploadShareDialog
            open
            fileIDs={fileIDs}
            collections={collections}
            onClose={close}
            refreshData={() => Promise.resolve()}
            setFeedbackMessage={() => undefined}
        />,
    );
const prompt = () =>
    confirm.mock.calls[0]![0] as {
        open: boolean;
        confirmDisabled: boolean;
        onConfirm: () => void;
        onClose: () => void;
        body: React.ReactNode;
    };
beforeEach(() => vi.clearAllMocks());

test("sharing uses the exact uploaded file only after an explicit action", () => {
    render();
    expect(openLink).not.toHaveBeenCalled();
    expect(prompt().confirmDisabled).toBe(false);
    prompt().onConfirm();
    expect(close).toHaveBeenCalledOnce();
    expect(openLink).toHaveBeenCalledExactlyOnceWith(item);
});

test("sharing waits for the uploaded file to appear in synced collections", () => {
    render([99]);
    expect(prompt().confirmDisabled).toBe(true);
    expect(prompt().body).toBeNull();
    prompt().onConfirm();
    expect(openLink).not.toHaveBeenCalled();
    confirm.mockClear();
    const syncedItem = { ...item, id: 99 };
    render([99], [{ ...collection, items: [syncedItem] }]);
    expect(prompt().confirmDisabled).toBe(false);
    expect(openLink).not.toHaveBeenCalled();
    prompt().onConfirm();
    expect(openLink).toHaveBeenCalledExactlyOnceWith(syncedItem);
    expect(close).toHaveBeenCalledOnce();
});

test("dismissal does not create a link", () => {
    render();
    prompt().onClose();
    expect(openLink).not.toHaveBeenCalled();
});

test("batch uploads never show the post-upload share prompt", () => {
    render([42, 99], [{ ...collection, items: [item, { ...item, id: 99 }] }]);
    expect(prompt().open).toBe(false);
    expect(openLink).not.toHaveBeenCalled();
});

test("files owned by another user cannot be shared", () => {
    render([42], [{ ...collection, items: [{ ...item, ownerID: 2 }] }]);
    expect(prompt().confirmDisabled).toBe(true);
    prompt().onConfirm();
    expect(openLink).not.toHaveBeenCalled();
});
