import { CollectionSubType, type Collection } from "ente-media/collection";
import { renderToStaticMarkup } from "react-dom/server";
import { beforeEach, expect, test, vi } from "vitest";
import { useGalleryOperations } from "../src/components/gallery/hooks/use-gallery-operations";
import type { useGalleryUploads } from "../src/components/gallery/hooks/use-gallery-uploads";
import {
    initialNavigationState,
    type GalleryDestination,
} from "../src/components/gallery/navigation/navigation-state";
import { initialGalleryState } from "../src/components/gallery/reducer";

const uploads = vi.hoisted(() =>
    vi.fn<
        (input: Parameters<typeof useGalleryUploads>[0]) => {
            dropzoneProps: object;
        }
    >(() => ({ dropzoneProps: {} })),
);

vi.mock("@/components/QuickLinkCreatedNotification", () => ({
    QuickLinkCreatedNotification: () => null,
}));
vi.mock("@/components/gallery/media/GalleryDownloadNotifications", () => ({
    GalleryDownloadNotifications: () => null,
}));
vi.mock("@/components/gallery/media/use-file-mutations", () => ({
    useFileMutations: () => ({ publicLinkToast: { open: false } }),
}));
vi.mock("../src/components/gallery/media/use-collection-dialogs", () => ({
    useCollectionDialogs: () => ({ albumNameInputVisibilityProps: {} }),
}));
vi.mock("@/components/gallery/hooks/use-gallery-uploads", () => ({
    useGalleryUploads: uploads,
}));
vi.mock("ente-gallery/components/utils/save-groups", () => ({
    useSaveGroups: () => ({ saveGroups: [] }),
}));
vi.mock("ente-new/photos/types/context", () => ({
    usePhotosAppContext: () => ({}),
}));

const collection: Collection = {
    id: 10,
    name: "Public link",
    type: "album",
    owner: { id: 1 },
    key: "test-key",
    sharees: [],
    publicURLs: [],
    updationTime: 1,
    magicMetadata: {
        version: 1,
        count: 1,
        data: { subType: CollectionSubType.quicklink },
    },
};

beforeEach(() => vi.clearAllMocks());

const uploadTarget = (destination: GalleryDestination) => {
    const Harness = () => {
        useGalleryOperations(
            {
                state: { ...initialGalleryState, collections: [collection] },
                searchIndexRevision: 0,
                remotePullRevision: 0,
                isFirstLoad: false,
                dispatch: vi.fn(),
                peopleState: undefined,
                remotePull: vi.fn(),
                remoteFilesPull: vi.fn(),
                showSessionExpiredDialog: vi.fn(),
                joinedCollectionID: undefined,
            },
            { ...initialNavigationState, destination },
            false,
            vi.fn(),
        );
        return null;
    };
    renderToStaticMarkup(<Harness />);
    return uploads.mock.lastCall![0].activeCollection;
};

test("a selected public link does not become the drop upload target", () => {
    expect(
        uploadTarget({ section: "links", collectionID: 10 }),
    ).toBeUndefined();
});

test.each<GalleryDestination>([
    { section: "albums", albumMode: "albums", collectionID: 10 },
    { section: "albums", albumMode: "hidden-albums", collectionID: 10 },
    { section: "albums", albumMode: "archive-albums", collectionID: 10 },
    { section: "albums", collectionID: 10, collectionMap: true },
])("an album destination retains its upload target: %j", (destination) => {
    expect(uploadTarget(destination)).toBe(collection);
});

test.each<GalleryDestination>([
    { section: "albums", albumFilter: "ente" },
    { section: "people", personID: "person" },
    { section: "places", collectionID: -1 },
])(
    "a destination without an album requires album selection: %j",
    (destination) => {
        expect(uploadTarget(destination)).toBeUndefined();
    },
);
