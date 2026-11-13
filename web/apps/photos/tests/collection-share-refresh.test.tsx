import type { Collection } from "ente-media/collection";
import type { EffectCallback } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { beforeEach, expect, test, vi } from "vitest";

const effects = vi.hoisted(() => [] as EffectCallback[]);
const refresh = vi.hoisted(() => vi.fn());
vi.mock("@/components/Avatar", () => ({ default: () => null }));
vi.mock("@/components/share/PublicLinkField", () => ({
    PublicLinkField: () => null,
}));
vi.mock("@/components/sidebar/theme", () => ({
    sidebarStyles: {},
    sidebarTheme: {},
}));
vi.mock("@/components/utils/use-public-link-url", () => ({
    usePublicLinkURL: () => ({
        resolvedURL: undefined,
        isLoading: false,
        error: undefined,
    }),
}));
vi.mock("ente-new/photos/components/utils/use-snapshot", () => ({
    useSettingsSnapshot: () => ({}),
}));
vi.mock("ente-base/components/RowButton", () => ({
    RowButtonGroup: () => null,
    RowButton: () => null,
    RowButtonDivider: () => null,
    RowButtonEndActivityIndicator: () => null,
    RowButtonGroupHint: () => null,
    RowButtonGroupTitle: () => null,
    RowLabel: () => null,
    RowSwitch: () => null,
}));
vi.mock("@/services/avatar", () => ({ avatarTextColor: vi.fn() }));
vi.mock("react", async (original) => ({
    ...(await original<typeof import("react")>()),
    useEffect: (effect: EffectCallback) => effects.push(effect),
    useEffectEvent: (callback: (...args: never[]) => unknown) => callback,
}));
vi.mock("ente-base/components/mui/SidebarDrawer", () => ({
    SidebarDrawer: ({ children }: { children: React.ReactNode }) => children,
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
    getCollectionByID: () => Promise.resolve({ publicURLs: [] }),
}));

import { CollectionShare } from "../src/components/collections/CollectionShare";

beforeEach(() => {
    effects.length = 0;
    refresh.mockReset().mockResolvedValue(undefined);
});

const renderSharing = (
    userID: number,
    onRemotePull = () => Promise.resolve(),
) => {
    const collection = {
        id: 42,
        type: "album",
        owner: { id: 1 },
        sharees: [{ id: 2, role: "VIEWER" }],
        publicURLs: [],
        key: "key",
        name: "Album",
        updationTime: 1,
    } satisfies Collection;
    return renderToStaticMarkup(
        <CollectionShare
            open
            onClose={vi.fn()}
            user={{ id: userID } as never}
            collection={collection}
            collectionSummary={
                {
                    type: userID === 1 ? "owned" : "sharedIncoming",
                    attributes: new Set(),
                } as never
            }
            emailByUserID={new Map()}
            shareSuggestionEmails={[]}
            setBlockingLoad={vi.fn()}
            onRemotePull={onRemotePull}
        />,
    );
};

test.each([1, 2])(
    "fetches participant details when user %i opens sharing",
    async (userID) => {
        renderSharing(userID);
        for (const effect of effects) effect();
        await Promise.resolve();
        expect(refresh).toHaveBeenCalledWith(42);
    },
);

test("does not start a full sync after refreshing sharing", async () => {
    const onRemotePull = vi.fn(() => Promise.resolve());
    refresh.mockResolvedValue({ publicURLs: [] });
    renderSharing(1, onRemotePull);
    for (const effect of effects) effect();
    await Promise.resolve();
    expect(onRemotePull).not.toHaveBeenCalled();
});

test("syncs the gallery when a participant discovers a public link", async () => {
    const onRemotePull = vi.fn(() => Promise.resolve());
    refresh.mockResolvedValue({ publicURLs: [{}] });
    renderSharing(2, onRemotePull);
    for (const effect of effects) effect();
    await Promise.resolve();
    expect(onRemotePull).toHaveBeenCalledWith({ silent: true });
});
