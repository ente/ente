import { decryptBox, generateKey } from "ente-base/crypto";
import { CollectionSubType, type Collection } from "ente-media/collection";
import type { EnteFile } from "ente-media/file";
import { ItemVisibility } from "ente-media/file-metadata";
import {
    bindCollectionKeyOpener,
    hideFiles,
    movePendingRemovalActionsToUncategorized,
    unbindCollectionKeyOpener,
} from "ente-new/photos/services/collection";
import {
    savedCollectionFiles,
    savedCollections,
} from "ente-new/photos/services/photos-fdb";
import { afterEach, beforeEach, expect, test, vi } from "vitest";

vi.mock("ente-base/crypto", () => import("ente-base/crypto/libsodium"));
vi.mock("ente-accounts/services/user", () => ({
    ensureLocalUser: () => ({ id: 1 }),
}));
vi.mock("ente-new/photos/services/account-keys", () => ({
    ensureMasterKeyFromSession: () => Promise.resolve(masterKey),
}));
vi.mock("ente-new/photos/services/photos-fdb", () => ({
    savedCollections: vi.fn(),
    savedCollectionFiles: vi.fn(),
}));
vi.mock("ente-base/http", async (importOriginal) => ({
    ...(await importOriginal<typeof import("ente-base/http")>()),
    authenticatedRequestHeaders: () => Promise.resolve({}),
}));
vi.mock("ente-base/origins", () => ({
    apiURL: (path: string) => Promise.resolve(`https://example.invalid${path}`),
}));

const fetchMock = vi.fn();
let masterKey: string;
beforeEach(async () => {
    masterKey = await generateKey();
    bindCollectionKeyOpener(({ encryptedKey, keyDecryptionNonce }) =>
        decryptBox(
            { encryptedData: encryptedKey, nonce: keyDecryptionNonce! },
            masterKey,
        ),
    );
    vi.stubGlobal("window", {});
    vi.stubGlobal("fetch", fetchMock);
    fetchMock.mockImplementation((url: string, request: RequestInit) => {
        if (url.endsWith("/collection-actions/pending-remove")) {
            return Promise.resolve(
                Response.json({ actions: [{ collectionID: 10, fileID: 100 }] }),
            );
        }
        if (url.endsWith("/collections")) {
            return Promise.resolve(
                Response.json({
                    collection: {
                        ...(JSON.parse(request.body as string) as Record<
                            string,
                            unknown
                        >),
                        id: 40,
                        owner: { id: 1 },
                        updationTime: 1,
                    },
                }),
            );
        }
        return Promise.resolve(new Response(null, { status: 200 }));
    });
});
afterEach(() => {
    unbindCollectionKeyOpener();
    vi.unstubAllGlobals();
    vi.resetAllMocks();
});

const hiddenAlbum = async (
    id: number,
    ownerID: number,
): Promise<Collection> => ({
    id,
    owner: { id: ownerID },
    key: await generateKey(),
    name: ".hidden",
    type: "album",
    sharees: [],
    publicURLs: [],
    updationTime: 1,
    magicMetadata: {
        version: 1,
        count: 2,
        data: {
            subType: CollectionSubType.defaultHidden,
            visibility: ItemVisibility.hidden,
        },
    },
});

test.each([
    ["hide", true],
    ["hide", false],
    ["pending removal", true],
    ["pending removal", false],
] as const)(
    "%s selects only owned Hidden albums (owned exists: %s)",
    async (flow, hasOwned) => {
        const foreign = await hiddenAlbum(2, 2);
        const oldestOwned = await hiddenAlbum(20, 1);
        const newerOwned = await hiddenAlbum(30, 1);
        const source = await hiddenAlbum(10, 1);
        delete source.magicMetadata!.data.subType;
        const collections = [
            foreign,
            ...(hasOwned ? [newerOwned, oldestOwned] : []),
            source,
        ];
        const file = {
            id: 100,
            collectionID: source.id,
            key: await generateKey(),
        } as EnteFile;
        vi.mocked(savedCollections).mockResolvedValue(collections);
        vi.mocked(savedCollectionFiles).mockResolvedValue([file]);

        await (flow == "hide"
            ? hideFiles([file])
            : movePendingRemovalActionsToUncategorized(collections));

        expect(
            fetchMock.mock.calls.filter(([url]) =>
                (url as string).endsWith("/collections"),
            ),
        ).toHaveLength(hasOwned ? 0 : 1);
        const move = fetchMock.mock.calls.find(([url]) =>
            (url as string).endsWith("/collections/move-files"),
        )!;
        expect(
            JSON.parse((move[1] as RequestInit).body as string),
        ).toMatchObject({
            fromCollectionID: source.id,
            toCollectionID: hasOwned ? oldestOwned.id : 40,
            files: [{ id: file.id }],
        });
    },
);
