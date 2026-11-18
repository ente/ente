import { makeBlankPage, normalizeBookPages } from "./bookPages";
import {
    applyVariant,
    chooseBestVariantKey,
    generateAutoLayout,
    getMaxAutoLayoutPhotos,
    getVariantsForCount,
} from "./layouts";
import { MAX_PRINT_PAGES, MIN_PRINT_PAGES } from "./printProducts";
import type { BookPage, Photo } from "./types";

const MAX_PAGE_PHOTOS = 4;
const MAX_AUTO_LAYOUT_PHOTOS = getMaxAutoLayoutPhotos(MAX_PRINT_PAGES);

export function createImportedBookPages(photos: Photo[]) {
    let layoutPhotos = photos;
    if (photos.length > MAX_AUTO_LAYOUT_PHOTOS) {
        const sorted = [...photos].sort((a, b) => a.dateTaken - b.dateTaken);
        const interval = (sorted.length - 1) / (MAX_AUTO_LAYOUT_PHOTOS - 1);
        layoutPhotos = Array.from(
            { length: MAX_AUTO_LAYOUT_PHOTOS },
            (_, index) => sorted[Math.round(index * interval)]!,
        );
    }
    const pages = generateAutoLayout(layoutPhotos);
    if (pages.length > 0 && pages.length < MIN_PRINT_PAGES) {
        pages.splice(
            pages.length - 1,
            0,
            ...Array.from(
                { length: MIN_PRINT_PAGES - pages.length },
                makeBlankPage,
            ),
        );
    }
    return pages;
}

export type PhotoDestination =
    { kind: "page"; pageId: string } | { kind: "end" } | { kind: "gallery" };
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
        rotation: remaining[index]!.rotation,
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
    if (destination.kind === "gallery") return null;
    let capacity =
        Math.max(0, MAX_PRINT_PAGES - pages.length) * MAX_PAGE_PHOTOS;
    if (destination.kind === "page") {
        const index = pages.findIndex((page) => page.id === destination.pageId);
        if (index < 0)
            return "That page is no longer available. Choose another page.";
        if (index === pages.length - 1)
            return "Choose an inside page or the front cover.";
        if (index === 0)
            return count === 1 ? null : "Choose one photo for the front cover.";
        capacity += availablePhotoSpaces(pages[index]!);
    } else if (pages.length === 0) {
        capacity = MAX_AUTO_LAYOUT_PHOTOS;
    }
    if (count <= capacity) return null;
    if (capacity === 0)
        return `Your book has reached the ${MAX_PRINT_PAGES}-page limit. Choose a page with room for more photos.`;
    return `There’s room for ${capacity} more ${capacity === 1 ? "photo" : "photos"} here within the ${MAX_PRINT_PAGES}-page limit.`;
}

function addPhotosToPage(page: BookPage, allPhotos: Photo[], added: Photo[]) {
    const existingSlots = page.slots.filter((slot) => slot.photoId);
    const existingPhotos = existingSlots.map(
        (slot) =>
            allPhotos.find((photo) => photo.id === slot.photoId) ?? {
                id: slot.photoId!,
                fileName: "",
                width: 1,
                height: 1,
                dateTaken: 0,
            },
    );
    const photos = [...existingPhotos, ...added];
    const layoutVariant = chooseBestVariantKey(photos);
    const slots = applyVariant(
        layoutVariant,
        photos.map((photo) => photo.id),
    );
    for (const [
        index,
        { id, cropX, cropY, cropZoom, rotation },
    ] of existingSlots.entries()) {
        Object.assign(slots[index]!, { id, cropX, cropY, cropZoom, rotation });
    }
    return { ...page, slots, layoutVariant };
}

export function placeImportedPhotos(
    pages: BookPage[],
    allPhotos: Photo[],
    newPhotos: Photo[],
    destination: PhotoDestination,
): BookPage[] {
    if (newPhotos.length === 0 || destination.kind === "gallery") return pages;
    const error = photoDestinationError(pages, destination, newPhotos.length);
    if (error) throw new Error(error);
    if (pages.length === 0) return createImportedBookPages(newPhotos);

    const updated = [...pages];
    let insertAt = pages.length - 1;
    let remaining = newPhotos;
    if (destination.kind === "page") {
        const index = pages.findIndex((page) => page.id === destination.pageId);
        const page = pages[index]!;
        if (index === 0) {
            const layoutVariant = getVariantsForCount(1, true).some(
                (variant) => variant.key === page.layoutVariant,
            )
                ? page.layoutVariant!
                : "1-full";
            updated[0] = {
                ...page,
                layoutVariant,
                slots: applyVariant(layoutVariant, [newPhotos[0]!.id]),
            };
            return updated;
        }
        const spaces = availablePhotoSpaces(page);
        if (spaces > 0)
            updated[index] = addPhotosToPage(
                page,
                allPhotos,
                newPhotos.slice(0, spaces),
            );
        remaining = newPhotos.slice(spaces);
        insertAt = index + 1;
    }
    if (remaining.length === 0) return updated;

    const inserted: BookPage[] = [];
    for (let i = 0; i < remaining.length; i += MAX_PAGE_PHOTOS) {
        const photos = remaining.slice(i, i + MAX_PAGE_PHOTOS);
        inserted.push(addPhotosToPage(makeBlankPage(), allPhotos, photos));
    }
    return normalizeBookPages([
        ...updated.slice(0, insertAt),
        ...inserted,
        ...updated.slice(insertAt),
    ]);
}

export function placeGalleryPhoto(
    pages: BookPage[],
    photos: Photo[],
    photoId: string,
    pageId: string,
    slotId?: string,
): BookPage[] {
    const photo = photos.find((photo) => photo.id === photoId);
    const page = pages.find((page) => page.id === pageId);
    if (!photo || !page || page === pages.at(-1)) return pages;
    if (slotId) {
        if (!page.slots.some((slot) => slot.id === slotId)) return pages;
        return pages.map((current) =>
            current.id === pageId
                ? {
                      ...current,
                      slots: current.slots.map((slot) =>
                          slot.id === slotId
                              ? {
                                    ...slot,
                                    photoId,
                                    cropX: 0.5,
                                    cropY: 0.5,
                                    cropZoom: 1,
                                    rotation: 0,
                                }
                              : slot,
                      ),
                  }
                : current,
        );
    }
    if (availablePhotoSpaces(page, page === pages[0]) === 0) return pages;
    return placeImportedPhotos(pages, photos, [photo], {
        kind: "page",
        pageId,
    });
}
