declare module "page-flip" {
    interface PageFlipOptions {
        width: number;
        height: number;
        size?: "fixed" | "stretch";
        minWidth?: number;
        maxWidth?: number;
        minHeight?: number;
        maxHeight?: number;
        showCover?: boolean;
        maxShadowOpacity?: number;
        mobileScrollSupport?: boolean;
        flippingTime?: number;
        useMouseEvents?: boolean;
        swipeDistance?: number;
        startPage?: number;
        drawShadow?: boolean;
        autoSize?: boolean;
        startZIndex?: number;
        showPageCorners?: boolean;
        usePortrait?: boolean;
        clickEventForward?: boolean;
    }

    class PageFlip {
        constructor(element: HTMLElement, options: PageFlipOptions);
        loadFromHTML(elements: HTMLElement[]): void;
        loadFromImages(images: string[]): void;
        turnToPage(pageNum: number): void;
        turnToNextPage(): void;
        turnToPrevPage(): void;
        getCurrentPageIndex(): number;
        getState(): "read" | "fold_corner" | "user_fold" | "flipping";
        getPageCount(): number;
        getPage(pageIndex: number): {
            setDensity(density: "hard" | "soft"): void;
            getDensity(): "hard" | "soft";
            simpleDraw: (orientation: number) => void;
            getElement(): HTMLElement;
        };
        getRender(): { getRect(): { pageWidth: number; height: number } };
        getFlipController(): {
            getCalculation(): {
                getDirection(): number;
                getBottomClipArea(): ({ x: number; y: number } | null)[];
            } | null;
        };
        on(event: "flip", callback: (e: { data: number }) => void): PageFlip;
        on(
            event: "changeState",
            callback: (e: { data: string }) => void,
        ): PageFlip;
        destroy(): void;
        flip(page: number, corner?: "top" | "bottom"): void;
        flipNext(corner: "top" | "bottom"): void;
        flipPrev(corner: "top" | "bottom"): void;
        update(): void;
    }

    export { PageFlip };
    export type { PageFlipOptions };
}
