import type { BookPage } from "./types";

export const makeBlankPage = (): BookPage => ({
    id: crypto.randomUUID(),
    slots: [],
    textBlocks: [],
    topCaption: "",
    bottomCaption: "",
});

export function isBlankPage(page: BookPage): boolean {
    return (
        page.slots.length === 0 &&
        page.textBlocks.length === 0 &&
        !page.topCaption &&
        !page.bottomCaption &&
        !page.centerText
    );
}

export function isRequiredBlankPage(
    pages: BookPage[],
    pageId: string,
): boolean {
    if (pages.length % 2 !== 0) return false;
    const blankPages = pages.slice(1, -1).filter(isBlankPage);
    return blankPages.length === 1 && blankPages[0]!.id === pageId;
}

export function normalizeBookPages(pages: BookPage[]): BookPage[] {
    if (pages.length === 0) return pages;
    let result = pages;
    const back = pages[pages.length - 1]!;

    if (pages.length === 1 || back.slots.some((slot) => slot.photoId)) {
        // A former back-cover photo becomes an interior page, retaining its crop,
        // captions and layout. Append a new back cover instead of deleting content.
        result = [...pages, makeBlankPage()];
    } else if (back.slots.length > 0 || back.layoutVariant) {
        result = [
            ...pages.slice(0, -1),
            { ...back, slots: [], layoutVariant: undefined },
        ];
    }

    if (result.length % 2 !== 0) {
        result = [
            ...result.slice(0, -1),
            makeBlankPage(),
            result[result.length - 1]!,
        ];
    }
    return result;
}
