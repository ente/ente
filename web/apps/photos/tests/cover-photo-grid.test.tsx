import { ThemeProvider } from "@mui/material";
import { photosTheme } from "ente-base/components/utils/theme";
import type { EnteFile } from "ente-media/file";
import { FileType } from "ente-media/file-type";
import type { ComponentProps } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, test, vi } from "vitest";
import { CoverPhotoGrid } from "../src/components/collections/CoverPhotoGrid";

vi.mock("ente-gallery/services/download", () => ({ downloadManager: {} }));
vi.mock("ente-new/photos/services/ml", () => ({ faceCrop: vi.fn() }));
vi.mock("i18next", () => ({ t: () => "Current" }));

const photo = (id: number) =>
    ({
        id,
        metadata: {
            title: `Photo ${id}`,
            fileType: FileType.image,
            hasStaticThumbnail: true,
        },
    }) as EnteFile;

const renderGrid = (
    overrides: Partial<ComponentProps<typeof CoverPhotoGrid>> = {},
) =>
    renderToStaticMarkup(
        <ThemeProvider theme={photosTheme}>
            <CoverPhotoGrid
                width={720}
                height={366}
                photos={Array.from({ length: 10000 }, (_, i) => photo(i))}
                currentCoverID={0}
                selectedFileID={1}
                disabled={false}
                onSelect={vi.fn()}
                {...overrides}
            />
        </ThemeProvider>,
    );

describe("cover photo grid", () => {
    test("mounts a bounded window of a large album", () => {
        const markup = renderGrid();
        const cards = markup.match(/<button\b[^>]*aria-pressed=/g) ?? [];
        expect(cards.length).toBeGreaterThan(0);
        expect(cards.length).toBeLessThan(32);
        expect(markup).toContain('aria-label="Photo 0"');
        expect(markup).not.toContain('aria-label="Photo 9999"');
    });

    test("marks the selection separately from the current cover", () => {
        const markup = renderGrid({ photos: [photo(0), photo(1)] });
        expect(markup).toMatch(
            /aria-label="Photo 0" aria-pressed="false" aria-describedby=/,
        );
        expect(markup).toMatch(/aria-label="Photo 1" aria-pressed="true"/);
        expect(markup.match(/>Current</g)).toHaveLength(1);
        expect(
            markup.match(/<svg\b[^>]*width="13"[^>]*height="13"[^>]*>/g),
        ).toHaveLength(1);
    });

    test("disables every visible card during submission", () => {
        const markup = renderGrid({
            photos: [photo(0), photo(1)],
            disabled: true,
        });
        const cards = markup.match(/<button\b[^>]*>/g) ?? [];
        expect(cards).toHaveLength(2);
        for (const card of cards) expect(card).toContain('disabled=""');
    });

    test("supports a narrow viewport and an empty album", () => {
        const markup = renderGrid({ width: 220, photos: [photo(0), photo(1)] });
        expect(markup).toContain('aria-label="Photo 1"');
        expect(renderGrid({ photos: [] })).not.toContain("aria-pressed=");
    });
});
