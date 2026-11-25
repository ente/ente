import { ThemeProvider } from "@mui/material";
import { photosTheme } from "ente-base/components/utils/theme";
import type { CollectionSummary } from "ente-new/photos/services/collection-summary";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, test, vi } from "vitest";
import {
    PhotosNavigationContext,
    type PhotosNavigationActions,
} from "../src/components/gallery/navigation/PhotosNavigationContext";
import { AlbumsHeader } from "../src/components/gallery/sections/albums/AlbumsHeader";

vi.mock("@/components/gallery/SectionBackButton", () => ({
    SectionBackButton: () => null,
}));
vi.mock(
    "@/components/gallery/header-styles",
    () => import("../src/components/gallery/header-styles"),
);
vi.mock("i18next", () => ({ t: (key: string) => key }));
vi.mock("../src/components/gallery/sections/albums/AlbumTile", () => ({
    AlbumTile: () => null,
}));
vi.mock("react-virtualized-auto-sizer", () => ({
    default: ({
        children,
    }: {
        children: (size: { width: number; height: number }) => React.ReactNode;
    }) => children({ width: 400, height: 200 }),
}));

const album = (id: number): CollectionSummary => ({
    id,
    name: `Album ${id}`,
    type: "album",
    attributes: new Set(),
    fileCount: 1,
    latestFile: undefined,
    coverFile: undefined,
    updationTime: undefined,
    sortPriority: 0,
});

const render = (count: number) =>
    renderToStaticMarkup(
        <ThemeProvider theme={photosTheme}>
            <PhotosNavigationContext.Provider
                value={
                    {
                        backToAlbums: vi.fn(),
                        selectCollection: vi.fn(),
                    } as unknown as PhotosNavigationActions
                }
            >
                <AlbumsHeader
                    title="Archive"
                    albums={Array.from({ length: count }, (_, i) =>
                        album(i + 1),
                    )}
                    height={311}
                />
            </PhotosNavigationContext.Provider>
        </ThemeProvider>,
    );

describe("Hidden and Archive album strip", () => {
    test("shows a right chevron when more albums are off screen", () => {
        const html = render(10);
        expect(html).toContain('aria-label="next"');
        expect(html).not.toContain('aria-label="previous"');
    });

    test("hides the chevrons when every album fits", () => {
        const html = render(2);
        expect(html).not.toContain('aria-label="next"');
        expect(html).not.toContain('aria-label="previous"');
    });
});
