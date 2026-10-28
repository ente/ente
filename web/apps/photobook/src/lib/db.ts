import localforage from "localforage";
import { defaultVariantKeyForCount, getVariantPreview } from "./layouts";
import { isPrintSelection } from "./printProducts";
import type { BookPage, BookState, Photo } from "./types";

const photoBlobStore = localforage.createInstance({
    name: "ente-photobook",
    storeName: "photo_blobs",
});

const thumbnailStore = localforage.createInstance({
    name: "ente-photobook",
    storeName: "thumbnails",
});

const previewStore = localforage.createInstance({
    name: "ente-photobook",
    storeName: "previews",
});

const metaStore = localforage.createInstance({
    name: "ente-photobook",
    storeName: "metadata",
});

export async function savePhotoBlob(id: string, blob: Blob): Promise<void> {
    await photoBlobStore.setItem(id, blob);
}

export async function getPhotoBlob(id: string): Promise<Blob | null> {
    return photoBlobStore.getItem<Blob>(id);
}

export async function saveThumbnail(id: string, blob: Blob): Promise<void> {
    await thumbnailStore.setItem(id, blob);
}

export async function getThumbnail(id: string): Promise<Blob | null> {
    return thumbnailStore.getItem<Blob>(id);
}

export async function savePreview(id: string, blob: Blob): Promise<void> {
    await previewStore.setItem(id, blob);
}

export async function getPreview(id: string): Promise<Blob | null> {
    return previewStore.getItem<Blob>(id);
}

export async function saveBookState(state: BookState): Promise<void> {
    await metaStore.setItem("bookState", state);
}

function normalizeStoredPage(
    storedPage: BookPage,
    pageIndex: number,
): BookPage {
    const {
        paddingH: _paddingH,
        paddingV: _paddingV,
        ...page
    } = storedPage as BookPage & { paddingH?: number; paddingV?: number };
    const hasOldSingleInset =
        page.layoutVariant === "1-padded" && pageIndex > 0;
    const needsSingleLayout = !page.layoutVariant && page.slots.length === 1;
    const hasSavedPadding =
        "paddingH" in storedPage || "paddingV" in storedPage;
    const hasShortColumns =
        page.layoutVariant === "4-equal-cols" &&
        page.slots.length === 4 &&
        page.slots.every((slot) => slot.y === 20 && slot.height === 60);
    const hasOldCaptionMargins =
        page.slots.length > 0 &&
        [8, (20 / 210) * 100].some(
            (margin) =>
                Math.abs(
                    Math.min(...page.slots.map((slot) => slot.y)) - margin,
                ) < 1e-9 &&
                Math.abs(
                    Math.max(
                        ...page.slots.map((slot) => slot.y + slot.height),
                    ) -
                        (100 - margin),
                ) < 1e-9,
        );
    const hasOldHorizontalMargins =
        page.slots.length > 0 &&
        [14.8, 20.72].some((marginMm) => {
            const margin = (marginMm / 210) * 100;
            return (
                Math.abs(
                    Math.min(...page.slots.map((slot) => slot.x)) - margin,
                ) < 1e-9 &&
                Math.abs(
                    Math.max(...page.slots.map((slot) => slot.x + slot.width)) -
                        (100 - margin),
                ) < 1e-9
            );
        });
    if (
        !hasOldSingleInset &&
        !needsSingleLayout &&
        !hasSavedPadding &&
        !hasShortColumns &&
        !hasOldCaptionMargins &&
        !hasOldHorizontalMargins
    )
        return page;

    const layoutVariant = hasOldSingleInset
        ? "1-moderate"
        : needsSingleLayout && pageIndex === 0
          ? "1-full"
          : (page.layoutVariant ??
            defaultVariantKeyForCount(page.slots.length));
    const positions = getVariantPreview(layoutVariant);
    if (positions.length !== page.slots.length) return page;

    // Replace only the frame geometry; retain photo order, slot IDs, crops, and text.
    return {
        ...page,
        layoutVariant,
        slots: page.slots.map((slot, index) => ({
            ...slot,
            ...positions[index],
        })),
    };
}

export async function getBookState(): Promise<BookState | null> {
    const state = await metaStore.getItem<BookState>("bookState");
    if (!state) return null;

    // Older books may contain a formatId. All books now use square pages;
    // retain their content and position without restoring the obsolete format.
    return {
        pages: state.pages.map(normalizeStoredPage),
        currentSpreadIndex: state.currentSpreadIndex,
        ...(typeof state.title === "string" ? { title: state.title } : {}),
        ...(isPrintSelection(state.printSelection)
            ? { printSelection: state.printSelection }
            : {}),
    };
}

export async function savePhotos(photos: Photo[]): Promise<void> {
    await metaStore.setItem("photos", photos);
}

export async function getPhotos(): Promise<Photo[] | null> {
    return metaStore.getItem<Photo[]>("photos");
}

export async function saveAppView(view: string): Promise<void> {
    await metaStore.setItem("appView", view);
}

export async function getAppView(): Promise<string | null> {
    return metaStore.getItem<string>("appView");
}

export async function clearAll(): Promise<void> {
    await Promise.all([
        photoBlobStore.clear(),
        thumbnailStore.clear(),
        previewStore.clear(),
        metaStore.clear(),
    ]);
}
