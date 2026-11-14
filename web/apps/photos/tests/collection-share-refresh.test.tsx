// @vitest-environment happy-dom
import type { Collection } from "ente-media/collection";
import React, { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, test, vi } from "vitest";

const refresh = vi.hoisted(() => vi.fn());
const link = vi.hoisted(() => vi.fn());
const saved = vi.hoisted(() => vi.fn());
vi.mock("@/components/Avatar", () => ({ default: () => null }));
vi.mock("@/components/share/PublicLinkField", () => ({
    PublicLinkField: () => null,
}));
vi.mock("@/components/sidebar/theme", () => ({
    sidebarStyles: {},
    sidebarTheme: {},
}));
vi.mock("@/components/utils/use-public-link-url", () => ({
    usePublicLinkURL: link,
}));
vi.mock("ente-new/photos/components/utils/use-snapshot", () => ({
    useSettingsSnapshot: () => ({}),
}));
vi.mock("ente-contacts", async (original) => ({
    ...(await original<typeof import("ente-contacts")>()),
    useResolvedContactDisplay: ({ email }: { email: string }) => ({
        primaryLabel: email,
    }),
}));
vi.mock("i18next", async (original) => ({
    ...(await original<typeof import("i18next")>()),
    t: (key: string) => key,
}));
vi.mock("ente-base/components/RowButton", () => ({
    RowButtonGroup: ({ children }: React.PropsWithChildren) => (
        <div>{children}</div>
    ),
    RowButton: ({ label }: { label: string }) => <div>{label}</div>,
    RowButtonDivider: () => null,
    RowButtonEndActivityIndicator: () => null,
    RowButtonGroupHint: () => null,
    RowButtonGroupTitle: ({ children }: React.PropsWithChildren) => (
        <div>{children}</div>
    ),
    RowLabel: ({ label }: { label: string }) => <div>{label}</div>,
    RowSwitch: () => null,
}));
vi.mock("@/services/avatar", () => ({ avatarTextColor: vi.fn() }));
vi.mock("ente-base/components/mui/SidebarDrawer", () => ({
    SidebarDrawer: ({ children }: React.PropsWithChildren) => children,
    NestedSidebarDrawer: () => null,
    TitledNestedSidebarDrawer: () => null,
    SidebarDrawerTitlebar: () => null,
}));
vi.mock("ente-base/context", () => ({
    useBaseContext: () => ({ onGenericError: vi.fn() }),
}));
vi.mock("ente-new/photos/types/context", () => ({
    usePhotosAppContext: () => ({
        showLoadingBar: vi.fn(),
        hideLoadingBar: vi.fn(),
    }),
}));
vi.mock("ente-new/photos/services/collection", () => ({
    refreshCollection: refresh,
    savedAllCollections: saved,
}));

import { CollectionShare } from "../src/components/collections/CollectionShare";

const publicURL = { url: "https://example.test/shared" } as never;
const album = (
    urls: boolean,
    role: "VIEWER" | "COLLABORATOR" = "VIEWER",
    email = "old@example.com",
): Collection => ({
    id: 42,
    name: "Album",
    type: "album",
    owner: { id: 1 },
    key: "key",
    sharees: [{ id: 2, role, email }],
    publicURLs: urls ? [publicURL] : [],
    updationTime: 1,
});
const render = (
    collection: Collection,
    userID: number,
    collaborator: boolean,
    onRemotePull = vi.fn().mockResolvedValue(undefined),
) => (
    <CollectionShare
        open
        onClose={vi.fn()}
        user={{ id: userID } as never}
        collection={collection}
        collectionSummary={
            {
                type: userID == 1 ? "album" : "sharedIncoming",
                attributes: new Set(
                    collaborator ? ["sharedIncomingCollaborator"] : [],
                ),
            } as never
        }
        emailByUserID={new Map()}
        shareSuggestionEmails={[]}
        setBlockingLoad={vi.fn()}
        onRemotePull={onRemotePull}
    />
);
beforeEach(() => {
    Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });
    refresh.mockReset();
    saved.mockReset().mockResolvedValue([]);
    link.mockReset().mockReturnValue({
        resolvedURL: undefined,
        isLoading: true,
        error: undefined,
    });
});

let root: Root;
let container: HTMLDivElement;
const update = async (element: React.ReactNode) => {
    await act(async () => {
        root.render(element);
        await Promise.resolve();
    });
};
beforeEach(() => {
    container = document.createElement("div");
    document.body.appendChild(container);
    root = createRoot(container);
});
afterEach(async () => {
    await act(async () => {
        root.unmount();
        await Promise.resolve();
    });
    container.remove();
});

test("accepts link removal after opening with an existing link", async () => {
    const original = album(true);
    refresh.mockResolvedValue(original);
    await update(render(original, 1, false));
    await update(render(album(false), 1, false));
    expect(link.mock.lastCall?.[1]).toBeUndefined();
});

test("preserves a discovered link until the gallery confirms it, then accepts removal", async () => {
    const original = album(false);
    const latest = album(true);
    const onRemotePull = vi.fn().mockResolvedValue(undefined);
    refresh.mockResolvedValue(latest);
    saved.mockResolvedValue([latest]);
    await update(render(original, 1, false, onRemotePull));
    await update(render(album(false), 1, false, onRemotePull));
    expect(link.mock.lastCall?.[1]).toEqual(publicURL);
    await update(render(latest, 1, false, onRemotePull));
    await update(render(album(false), 1, false, onRemotePull));
    expect(link.mock.lastCall?.[1]).toBeUndefined();
    expect(onRemotePull).not.toHaveBeenCalled();
});

test("accepts a cached removal before the discovered link reaches the gallery", async () => {
    const original = album(false);
    const latest = album(true);
    refresh.mockResolvedValue(latest);
    saved.mockResolvedValue([latest]);
    await update(render(original, 1, false));
    await update(render(album(false), 1, false));
    expect(link.mock.lastCall?.[1]).toEqual(publicURL);
    saved.mockResolvedValue([album(false)]);
    await update(render(album(false), 1, false));
    expect(link.mock.lastCall?.[1]).toBeUndefined();
});

test("ignores an older cache read after a newer gallery update", async () => {
    const original = album(false);
    const latest = album(true);
    const pending = Promise.withResolvers<Collection[]>();
    refresh.mockResolvedValue(latest);
    saved.mockReturnValue(pending.promise);
    await update(render(original, 1, false));
    await update(render(album(false), 1, false));
    await update(render(latest, 1, false));
    await act(async () => {
        pending.resolve([album(false)]);
        await pending.promise;
    });
    expect(link.mock.lastCall?.[1]).toEqual(publicURL);
});

test.each([
    ["COLLABORATOR", false, true],
    ["VIEWER", true, false],
] as const)(
    "uses refreshed role %s with stale summary",
    async (role, summaryCollaborator, visible) => {
        const latest = album(false, role);
        latest.sharees.push({
            id: 3,
            role: "COLLABORATOR",
            email: "other@example.com",
        });
        refresh.mockResolvedValue(latest);
        await update(render(album(false), 2, summaryCollaborator));
        expect(container.textContent.includes("collaborators")).toBe(visible);
    },
);

test("renders the refreshed participant email without a full sync", async () => {
    const pending = Promise.withResolvers<Collection>();
    const onRemotePull = vi.fn().mockResolvedValue(undefined);
    refresh.mockReturnValue(pending.promise);
    await update(render(album(false), 1, false, onRemotePull));
    expect(container.textContent).toContain("loading");
    expect(container.textContent).not.toContain("old@example.com");
    await act(async () => {
        pending.resolve(album(false, "VIEWER", "new@example.com"));
        await pending.promise;
    });
    expect(container.textContent).toContain("new@example.com");
    expect(onRemotePull).not.toHaveBeenCalled();
});

test("retries a failed refresh and displays the participant", async () => {
    refresh.mockRejectedValueOnce(new Error("network error"));
    refresh.mockResolvedValueOnce(album(false, "VIEWER", "new@example.com"));
    await update(render(album(false), 1, false));
    const retry = Array.from(container.querySelectorAll("button")).find(
        (button) => button.textContent == "retry",
    );
    expect(retry).toBeDefined();
    await act(async () => {
        retry!.click();
        await Promise.resolve();
    });
    expect(container.textContent).toContain("new@example.com");
});

test("syncs the gallery when a participant discovers a public link", async () => {
    const onRemotePull = vi.fn().mockResolvedValue(undefined);
    refresh.mockResolvedValue(album(true));
    await update(render(album(false), 2, false, onRemotePull));
    expect(onRemotePull).toHaveBeenCalledExactlyOnceWith({ silent: true });
});
