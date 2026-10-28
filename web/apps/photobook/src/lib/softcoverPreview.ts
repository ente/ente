import type { PageFlip } from "page-flip";

export function clipSoftcoverInsidePages(book: PageFlip): () => void {
    const count = book.getPageCount();
    if (count < 4) return () => undefined;

    const restore = [
        { index: 1, direction: 1, spreadStart: 1 },
        { index: count - 2, direction: 0, spreadStart: count - 3 },
    ].map(({ index, direction, spreadStart }) => {
        const page = book.getPage(index);
        const simpleDraw = page.simpleDraw;

        page.simpleDraw = function (orientation) {
            simpleDraw.call(this, orientation);
            const fold = book.getFlipController().getCalculation();
            if (
                fold?.getDirection() !== direction ||
                book.getCurrentPageIndex() !== spreadStart
            )
                return;

            const { pageWidth: width, height } = book.getRender().getRect();
            const exposed = fold
                .getBottomClipArea()
                .filter((point) => point !== null);
            if (exposed.length < 3) return;

            // The calculation measures x from the spine; a left page is mirrored.
            const hole = exposed.map(
                ({ x, y }) => `${direction === 1 ? width - x : x}px ${y}px`,
            );
            const clip = `polygon(evenodd, 0px 0px, ${width}px 0px, ${width}px ${height}px, 0px ${height}px, 0px 0px, ${hole.join(", ")}, ${hole[0]})`;
            const style = page.getElement().style;
            style.clipPath = clip;
            style.setProperty("-webkit-clip-path", clip);
        };

        return () => {
            page.simpleDraw = simpleDraw;
        };
    });

    return () => restore.forEach((reset) => reset());
}
