import assert from "node:assert/strict";
import type { PageFlip } from "page-flip";
import { test, vi } from "vitest";
import { clipSoftcoverInsidePages } from "./softcoverPreview";

function fixture() {
    const state = { index: 1, direction: 1, folding: true };
    const pages = Array.from({ length: 8 }, () => {
        const style = {
            clipPath: "",
            webkitClipPath: "",
            setProperty(name: string, value: string) {
                if (name === "-webkit-clip-path") this.webkitClipPath = value;
            },
        };
        return {
            style,
            simpleDraw: vi.fn((orientation: number) => {
                assert.ok(orientation === 0 || orientation === 1);
                // The library replaces cssText, clearing the previous frame's mask.
                style.clipPath = "";
                style.webkitClipPath = "";
            }),
            getElement: () => ({ style }),
        };
    });
    const book = {
        getPageCount: () => pages.length,
        getPage: (index: number) => pages[index]!,
        getCurrentPageIndex: () => state.index,
        getRender: () => ({ getRect: () => ({ pageWidth: 300, height: 300 }) }),
        getFlipController: () => ({
            getCalculation: () =>
                state.folding
                    ? {
                          getDirection: () => state.direction,
                          getBottomClipArea: () => [
                              null,
                              { x: 200, y: 0 },
                              { x: 300, y: 0 },
                              { x: 300, y: 300 },
                              { x: 100, y: 300 },
                              { x: 200, y: 0 },
                          ],
                      }
                    : null,
        }),
    } as unknown as PageFlip;
    return { book, pages, state };
}

// Evaluate the generated even-odd polygon at a point, so regressions that
// expose the wrong side of a cover are caught without a browser screenshot.
function visibleAt(clip: string, x: number, y: number) {
    const points = [...clip.matchAll(/(-?[\d.]+)px (-?[\d.]+)px/g)].map(
        (match) => [Number(match[1]!), Number(match[2]!)] as const,
    );
    let inside = false;
    for (let i = 0, j = points.length - 1; i < points.length; j = i++) {
        const [xi, yi] = points[i]!;
        const [xj, yj] = points[j]!;
        if (yi > y !== yj > y && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi)
            inside = !inside;
    }
    return inside;
}

test("closing the front cover reveals the background behind the left fold", () => {
    const { book, pages } = fixture();
    clipSoftcoverInsidePages(book);
    pages[1]!.simpleDraw(0);
    const clip = pages[1]!.style.clipPath;
    assert.match(clip, /^polygon\(evenodd,/);
    assert.equal(
        visibleAt(clip, 10, 150),
        false,
        "the exposed outside edge has no stationary white sheet",
    );
    assert.equal(
        visibleAt(clip, 280, 150),
        true,
        "the unfolded inside face remains beside the spine",
    );
    assert.equal(pages[1]!.style.webkitClipPath, clip);
});

test("closing the back cover mirrors the cutout onto the right page", () => {
    const { book, pages, state } = fixture();
    state.index = 5;
    state.direction = 0;
    clipSoftcoverInsidePages(book);
    pages[6]!.simpleDraw(1);
    assert.equal(visibleAt(pages[6]!.style.clipPath, 290, 150), false);
    assert.equal(visibleAt(pages[6]!.style.clipPath, 20, 150), true);
});

test("opening covers and turning interior pages retain the normal page drawing", () => {
    const { book, pages, state } = fixture();
    const originals = pages.map((page) => page.simpleDraw);
    clipSoftcoverInsidePages(book);
    for (const index of [0, 2, 3, 4, 5, 7])
        assert.equal(pages[index]!.simpleDraw, originals[index]!);
    for (const [index, direction] of [
        [0, 0],
        [7, 1],
        [3, 0],
        [3, 1],
        [1, 0],
        [5, 1],
    ]) {
        Object.assign(state, { index, direction });
        pages[1]!.simpleDraw(0);
        pages[6]!.simpleDraw(1);
        assert.equal(pages[1]!.style.clipPath, "");
        assert.equal(pages[6]!.style.clipPath, "");
    }
});

test("cancelled and completed folds clear the cutout, and cleanup restores the library methods", () => {
    const { book, pages, state } = fixture();
    const originals = pages.map((page) => page.simpleDraw);
    const restore = clipSoftcoverInsidePages(book);
    pages[1]!.simpleDraw(0);
    assert.notEqual(pages[1]!.style.clipPath, "");
    state.folding = false;
    pages[1]!.simpleDraw(0);
    assert.equal(pages[1]!.style.clipPath, "");
    assert.equal(pages[1]!.style.webkitClipPath, "");
    restore();
    assert.deepEqual(
        pages.map((page) => page.simpleDraw),
        originals,
    );
});
