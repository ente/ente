import { makeBlankPage, normalizeBookPages } from "./bookPages";
import {
    applyVariant,
    chooseBestVariantKey,
    generateAutoLayout,
    getVariantsForCount,
} from "./layouts";
import type { BookPage, Photo } from "./types";

export const MAX_PAGE_PHOTOS = 4;
export type PhotoDestination =
    { kind: "page"; pageId: string } | { kind: "end" };
export interface AddPhotosOptions {
    replace?: boolean;
    destination?: PhotoDestination;
}

export function normalizeFrontCover(pages: BookPage[]): BookPage[] {
    const cover = pages.at(0);
    const filled = cover?.slots.filter((slot) => slot.photoId) ?? [];
    if (!cover || filled.length <= 1) return pages;
    const first = filled[0]!;
    const remaining = filled.slice(1);
    const coverSlot = applyVariant("1-full", [first.photoId!])[0]!;
    const layoutVariant = getVariantsForCount(remaining.length)[0]!.key;
    const slots = applyVariant(
        layoutVariant,
        remaining.map((slot) => slot.photoId!),
    ).map((slot, index) => ({
        ...slot,
        id: remaining[index]!.id,
        cropX: remaining[index]!.cropX,
        cropY: remaining[index]!.cropY,
        cropZoom: remaining[index]!.cropZoom,
    }));
    return normalizeBookPages([
        {
            ...cover,
            layoutVariant: "1-full",
            slots: [
                {
                    ...first,
                    x: coverSlot.x,
                    y: coverSlot.y,
                    width: coverSlot.width,
                    height: coverSlot.height,
                },
            ],
        },
        { ...makeBlankPage(), layoutVariant, slots },
        ...pages.slice(1),
    ]);
}

export function availablePhotoSpaces(
    page: BookPage,
    isFrontCover = false,
): number {
    const capacity = isFrontCover ? 1 : MAX_PAGE_PHOTOS;
    return Math.max(
        0,
        capacity - page.slots.filter((slot) => slot.photoId).length,
    );
}

export function photoDestinationError(
    pages: BookPage[],
    destination: PhotoDestination,
    count: number,
): string | null {
    if (destination.kind === "end") return null;
    const index = pages.findIndex((page) => page.id === destination.pageId);
    if (index < 0)
        return "That page is no longer available. Choose another page.";
    if (index === pages.length - 1)
        return "Choose an inside page or the front cover.";
    if (index === 0)
        return count === 1 ? null : "Choose one photo for the front cover.";
    const spaces = availablePhotoSpaces(pages[index]!);
    if (count > spaces)
        return `This page has room for ${spaces} more photo${spaces === 1 ? "" : "s"}. Choose another page or create new pages at the end.`;
    return null;
}

export function placeImportedPhotos(
    pages: BookPage[],
    allPhotos: Photo[],
    newPhotos: Photo[],
    destination: PhotoDestination,
): BookPage[] {
    if (newPhotos.length === 0) return pages;
    const error = photoDestinationError(pages, destination, newPhotos.length);
    if (error) throw new Error(error);
    if (pages.length === 0) return generateAutoLayout(newPhotos);

    if (destination.kind === "page") {
        const photoMap = new Map(allPhotos.map((photo) => [photo.id, photo]));
        return pages.map((page, index) => {
            if (page.id !== destination.pageId) return page;
            if (index === 0) {
                // A cover import replaces its image, retaining the title and chosen layout.
                const layoutVariant = getVariantsForCount(1, true).some(
                    (variant) => variant.key === page.layoutVariant,
                )
                    ? page.layoutVariant!
                    : "1-full";
                return {
                    ...page,
                    layoutVariant,
                    slots: applyVariant(layoutVariant, [newPhotos[0]!.id]),
                };
            }
            const existingSlots = page.slots.filter((slot) => slot.photoId);
            const ids = [
                ...existingSlots.map((slot) => slot.photoId!),
                ...newPhotos.map((photo) => photo.id),
            ];
            const photos = ids.map(
                (id) =>
                    photoMap.get(id) ?? {
                        id,
                        fileName: "",
                        width: 1,
                        height: 1,
                        dateTaken: 0,
                    },
            );
            const layoutVariant = chooseBestVariantKey(photos);
            const slots = applyVariant(layoutVariant, ids).map((slot) => {
                const existing = existingSlots.find(
                    (candidate) => candidate.photoId === slot.photoId,
                );
                return existing
                    ? {
                          ...slot,
                          id: existing.id,
                          cropX: existing.cropX,
                          cropY: existing.cropY,
                          cropZoom: existing.cropZoom,
                      }
                    : slot;
            });
            return { ...page, slots, layoutVariant };
        });
    }

    const appended: BookPage[] = [];
    for (let i = 0; i < newPhotos.length; i += MAX_PAGE_PHOTOS) {
        const photos = newPhotos.slice(i, i + MAX_PAGE_PHOTOS);
        const layoutVariant = chooseBestVariantKey(photos);
        appended.push({
            ...makeBlankPage(),
            layoutVariant,
            slots: applyVariant(
                layoutVariant,
                photos.map((photo) => photo.id),
            ),
        });
    }
    return normalizeBookPages([
        ...pages.slice(0, -1),
        ...appended,
        pages[pages.length - 1]!,
    ]);
}
