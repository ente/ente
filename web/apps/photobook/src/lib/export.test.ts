import JSZip from "jszip";
import assert from "node:assert/strict";
import { afterAll, beforeAll, test, vi } from "vitest";
import { makeBlankPage } from "./bookPages";
import {
    exportPdfX4Pages,
    exportPngPagesZip,
    renderPageToCanvas,
} from "./export";
import { applyVariant } from "./layouts";
import * as pdfx from "./pdfx";
import {
    DEFAULT_PRINT_SELECTION,
    getBindingPrintSelection,
    PrintExportValidationError,
    type PrintSelection,
} from "./printProducts";

const sizeMm = 210;

interface TextDraw {
    text: string;
    x: number;
    y: number;
    fontSize: number;
    align: string;
}
interface CanvasRecord {
    width: number;
    height: number;
    marks: string[];
    textDraws: TextDraw[];
    imageDraws: { x: number; y: number; width: number; height: number }[];
}
const documentDescriptor = Object.getOwnPropertyDescriptor(
    globalThis,
    "document",
);
const imageDescriptor = Object.getOwnPropertyDescriptor(globalThis, "Image");
const fileReaderDescriptor = Object.getOwnPropertyDescriptor(
    globalThis,
    "FileReader",
);
let canvasCount = 0;

beforeAll(() => {
    // Exercise export sequencing without starting a browser or loading WASM.
    Object.defineProperty(globalThis, "document", {
        configurable: true,
        value: {
            fonts: { ready: Promise.resolve() },
            createElement(tag: string) {
                assert.equal(tag, "canvas");
                canvasCount++;
                const canvas: CanvasRecord = {
                    width: 0,
                    height: 0,
                    marks: [],
                    textDraws: [],
                    imageDraws: [],
                };
                return Object.assign(canvas, {
                    getContext: () => ({
                        font: "10px sans-serif",
                        textAlign: "left",
                        save: vi.fn(),
                        restore: vi.fn(),
                        beginPath: vi.fn(),
                        rect: vi.fn(),
                        clip: vi.fn(),
                        translate: vi.fn(),
                        rotate: vi.fn(),
                        fillRect: vi.fn(),
                        measureText(text: string) {
                            return {
                                width:
                                    text.length *
                                    Number(/([\d.]+)px/.exec(this.font)![1]!) *
                                    0.6,
                            };
                        },
                        fillText(text: string, x: number, y: number) {
                            canvas.marks.push(text);
                            canvas.textDraws.push({
                                text,
                                x,
                                y,
                                fontSize: Number(
                                    /([\d.]+)px/.exec(this.font)![1]!,
                                ),
                                align: this.textAlign,
                            });
                        },
                        drawImage(
                            _image: unknown,
                            x: number,
                            y: number,
                            width: number,
                            height: number,
                        ) {
                            canvas.marks.push("ente-logo");
                            canvas.imageDraws.push({ x, y, width, height });
                        },
                    }),
                    toBlob(callback: BlobCallback) {
                        callback(
                            new Blob([JSON.stringify(canvas)], {
                                type: "image/png",
                            }),
                        );
                    },
                });
            },
        },
    });
    Object.defineProperty(globalThis, "Image", {
        configurable: true,
        value: class {
            naturalWidth = 844;
            naturalHeight = 264;
            onload: (() => void) | null = null;
            set src(_value: string) {
                queueMicrotask(() => this.onload?.());
            }
        },
    });
    Object.defineProperty(globalThis, "FileReader", {
        configurable: true,
        value: class {
            onload:
                ((event: { target: { result: ArrayBuffer } }) => void) | null =
                null;
            onerror: ((event: { target: { error: unknown } }) => void) | null =
                null;
            readAsArrayBuffer(blob: Blob) {
                blob.arrayBuffer().then(
                    (result) => this.onload?.({ target: { result } }),
                    (error: unknown) => this.onerror?.({ target: { error } }),
                );
            }
        },
    });
    vi.spyOn(pdfx, "renderCanvasToFogra39Jpeg").mockImplementation(
        (canvas: HTMLCanvasElement) =>
            Promise.resolve(new TextEncoder().encode(JSON.stringify(canvas))),
    );
    vi.spyOn(pdfx, "createPdfX4").mockImplementation(
        (images: Uint8Array[], size: pdfx.PdfXPageSize) =>
            Promise.resolve(
                new TextEncoder().encode(
                    JSON.stringify({
                        pages: images.map(
                            (image) =>
                                JSON.parse(
                                    new TextDecoder().decode(image),
                                ) as CanvasRecord,
                        ),
                        size,
                    }),
                ),
            ),
    );
});

afterAll(() => {
    vi.restoreAllMocks();
    for (const [key, descriptor] of [
        ["document", documentDescriptor],
        ["Image", imageDescriptor],
        ["FileReader", fileReaderDescriptor],
    ] as const) {
        if (descriptor) Object.defineProperty(globalThis, key, descriptor);
        else Reflect.deleteProperty(globalThis, key);
    }
});

function bookWithBlankPage(count: number) {
    const pages = Array.from({ length: count }, (_, i) => ({
        ...makeBlankPage(),
        centerText: i === 10 || i === count - 1 ? "" : `Page ${i + 1}`,
    }));
    return pages;
}

test("hardcover and softcover export the same content without printer-added blanks", async () => {
    const pages = bookWithBlankPage(24);
    const original = structuredClone(pages);
    const hardcover = await exportPdfX4Pages(
        pages,
        getBindingPrintSelection("Hardcover"),
    );
    const softcover = await exportPdfX4Pages(
        pages,
        getBindingPrintSelection("Softcover"),
    );
    assert.deepEqual(
        JSON.parse(await hardcover.text()),
        JSON.parse(await softcover.text()),
    );
    assert.equal(
        (JSON.parse(await hardcover.text()) as { pages: CanvasRecord[] }).pages
            .length,
        24,
    );
    assert.deepEqual(pages, original);
});

test("a missing photo cannot silently produce an incomplete print page", async () => {
    const page = {
        ...makeBlankPage(),
        slots: applyVariant("1-full", ["missing-photo"]),
    };
    await assert.rejects(
        renderPageToCanvas(page, () => Promise.resolve(null), 2480, 2480),
        /photo is missing/,
    );
});

test(`${sizeMm} mm PDF export preserves all 24 pages including a blank interior page`, async () => {
    const pages = bookWithBlankPage(24);
    const original = structuredClone(pages);
    const blob = await exportPdfX4Pages(pages, DEFAULT_PRINT_SELECTION);
    const result = JSON.parse(await blob.text()) as {
        pages: CanvasRecord[];
        size: pdfx.PdfXPageSize;
    };

    assert.equal(result.pages.length, 24);
    assert.deepEqual(
        result.pages.map((page) => page.marks),
        pages.map((page, i) =>
            i === 23 ? ["ente-logo"] : page.centerText ? [page.centerText] : [],
        ),
    );
    assert.deepEqual(result.size, {
        widthMm: 210,
        heightMm: 210,
        widthPx: 2480,
        heightPx: 2480,
    });
    assert.deepEqual(pages, original);
});

test("PDF export adds an even-count blank immediately before the back cover", async () => {
    const pages = bookWithBlankPage(23);
    const blob = await exportPdfX4Pages(pages, DEFAULT_PRINT_SELECTION);
    const result = JSON.parse(await blob.text()) as { pages: CanvasRecord[] };

    assert.equal(result.pages.length, 24);
    assert.deepEqual(result.pages[10]!.marks, [], "retains the existing blank");
    assert.deepEqual(result.pages[21]!.marks, ["Page 22"]);
    assert.deepEqual(
        result.pages[22]!.marks,
        [],
        "adds the extra blank before the back cover",
    );
    assert.deepEqual(result.pages[23]!.marks, ["ente-logo"]);
    assert.equal(pages.length, 23, "does not mutate the input book");
});

for (const count of [23, 24]) {
    test(`PNG export preserves blanks and cover order for a ${count}-page input`, async () => {
        const blob = await exportPngPagesZip(
            bookWithBlankPage(count),
            DEFAULT_PRINT_SELECTION,
        );
        const zip = await JSZip.loadAsync(await blob.arrayBuffer());
        const names = Object.keys(zip.files);

        assert.equal(names.length, 24);
        assert.deepEqual(
            names,
            Array.from(
                { length: 24 },
                (_, i) => `page_${String(i + 1).padStart(3, "0")}.png`,
            ),
        );
        const blank = JSON.parse(
            await zip.file("page_011.png")!.async("string"),
        ) as CanvasRecord;
        const back = JSON.parse(
            await zip.file("page_024.png")!.async("string"),
        ) as CanvasRecord;
        assert.deepEqual(blank.marks, []);
        assert.deepEqual(back.marks, ["ente-logo"]);
        assert.equal(back.width, 2480);
        assert.equal(back.height, 2480);
    });
}

for (const [format, runExport] of [
    ["PDF", exportPdfX4Pages],
    ["PNG", exportPngPagesZip],
] as const) {
    test(`${format} rejects invalid product counts before rendering or reporting progress`, async () => {
        for (const count of [0, 2, 20, 301]) {
            const before = canvasCount;
            let progressCalls = 0;
            await assert.rejects(
                runExport(
                    bookWithBlankPage(count),
                    DEFAULT_PRINT_SELECTION,
                    () => {
                        progressCalls++;
                    },
                ),
                PrintExportValidationError,
            );
            assert.equal(canvasCount, before);
            assert.equal(progressCalls, 0);
        }
    });

    test(`${format} cannot bypass validation with an unknown product or unsupported size`, async () => {
        for (const selection of [
            { productId: "unknown", sizeMm: 210 },
            { productId: "hardcover-gloss-200", sizeMm: 211 },
            { productId: "softcover-gloss-150", sizeMm: 211 },
        ] as PrintSelection[]) {
            const before = canvasCount;
            await assert.rejects(
                runExport(bookWithBlankPage(24), selection),
                PrintExportValidationError,
            );
            assert.equal(canvasCount, before);
        }
    });
}

test("softcover requires 24 pages and rejects the former 20-page minimum", async () => {
    const selection: PrintSelection = {
        productId: "softcover-gloss-150",
        sizeMm: 210,
    };
    for (const runExport of [exportPdfX4Pages, exportPngPagesZip]) {
        await assert.rejects(
            runExport(bookWithBlankPage(20), selection),
            PrintExportValidationError,
        );
    }
    const pages = bookWithBlankPage(24);
    const pdf = JSON.parse(
        await (await exportPdfX4Pages(pages, selection)).text(),
    ) as { pages: CanvasRecord[] };
    const png = await exportPngPagesZip(pages, selection);
    const zip = await JSZip.loadAsync(await png.arrayBuffer());
    assert.equal(pdf.pages.length, 24);
    assert.equal(Object.keys(zip.files).length, 24);
});

test("150 gsm hardcover accepts a 500-page PDF while other hardcover paper rejects it", async () => {
    const pages = bookWithBlankPage(500);
    const selection: PrintSelection = {
        productId: "hardcover-gloss-150",
        sizeMm: 210,
    };
    const result = JSON.parse(
        await (await exportPdfX4Pages(pages, selection)).text(),
    ) as { pages: CanvasRecord[] };
    assert.equal(result.pages.length, 500);
    await assert.rejects(
        exportPdfX4Pages(pages, DEFAULT_PRINT_SELECTION),
        PrintExportValidationError,
    );
});

test("PNG dimensions match 210 mm pages at 300 DPI", async () => {
    const blob = await exportPngPagesZip(
        bookWithBlankPage(24),
        DEFAULT_PRINT_SELECTION,
    );
    const zip = await JSZip.loadAsync(await blob.arrayBuffer());
    const page = JSON.parse(
        await zip.file("page_001.png")!.async("string"),
    ) as CanvasRecord;
    assert.equal(page.width, 2480);
    assert.equal(page.height, page.width);
});

test(`${sizeMm} mm rendering centres captions between the photo and paper edge`, async () => {
    for (const variant of ["2-side", "1-moderate", "1-padded"]) {
        const isFrontCover = variant.startsWith("1-");
        const page = {
            ...makeBlankPage(),
            slots: applyVariant(
                variant,
                isFrontCover ? ["photo"] : ["photo-1", "photo-2"],
            ),
            topCaption: "Summer",
            bottomCaption: "2026",
        };
        const sizePx = Math.round((sizeMm / 25.4) * 300);
        const result = (await renderPageToCanvas(
            page,
            (id) => Promise.resolve(`test:${id}`),
            sizePx,
            sizePx,
            false,
            isFrontCover,
        )) as unknown as CanvasRecord;
        assert.equal(result.imageDraws.length, page.slots.length);
        assert.equal(result.textDraws.length, 2);
        const photoTop = Math.min(...result.imageDraws.map((draw) => draw.y));
        const photoBottom = Math.max(
            ...result.imageDraws.map((draw) => draw.y + draw.height),
        );
        const [topCaption, bottomCaption] = result.textDraws;
        assert.ok(topCaption && bottomCaption);
        const topPhotoGap = photoTop - topCaption.y - topCaption.fontSize * 0.7;
        const topEdgeGap = topCaption.y - topCaption.fontSize * 0.7;
        const bottomPhotoGap =
            bottomCaption.y - bottomCaption.fontSize * 0.7 - photoBottom;
        const bottomEdgeGap =
            sizePx - bottomCaption.y - bottomCaption.fontSize * 0.7;
        assert.ok(
            Math.abs(topPhotoGap - topEdgeGap) < 1e-6,
            "top caption has equal whitespace above and below",
        );
        assert.ok(
            Math.abs(bottomPhotoGap - bottomEdgeGap) < 1e-6,
            "bottom caption has equal whitespace above and below",
        );
        assert.ok(
            ((topCaption.y - topCaption.fontSize * 0.7) / sizePx) * sizeMm >=
                10 - 1e-6,
        );
        assert.ok(
            ((sizePx - bottomCaption.y - bottomCaption.fontSize * 0.7) /
                sizePx) *
                sizeMm >=
                10 - 1e-6,
        );
        const empty = (await renderPageToCanvas(
            { ...page, topCaption: "", bottomCaption: "" },
            (id) => Promise.resolve(`test:${id}`),
            sizePx,
            sizePx,
            false,
            isFrontCover,
        )) as unknown as CanvasRecord;
        assert.deepEqual(
            empty.textDraws,
            [],
            "editor placeholders are never exported",
        );
        assert.deepEqual(
            empty.imageDraws,
            result.imageDraws,
            "adding a caption does not shift the photos",
        );
    }
});

test(`${sizeMm} mm rendering keeps caption and custom-text bounds at least 10 mm from the trim`, async () => {
    const text = "A long caption. ".repeat(30);
    const page = {
        ...makeBlankPage(),
        slots: applyVariant("1-moderate", ["photo"]),
        topCaption: "Ordinary caption",
        bottomCaption: text,
        textBlocks: [
            {
                id: "text",
                text: "Saved text outside the page",
                x: 110,
                y: 110,
                width: 45,
                height: 15,
                fontSize: 6,
                rotation: 0,
                color: "#555555",
                style: "body" as const,
                alignment: "left" as const,
            },
        ],
    };
    const original = structuredClone(page);
    const sizePx = Math.round((sizeMm / 25.4) * 300);
    const result = (await renderPageToCanvas(
        page,
        (id) => Promise.resolve(`test:${id}`),
        sizePx,
        sizePx,
    )) as unknown as CanvasRecord;
    const safe = (10 / sizeMm) * sizePx;
    assert.equal(result.textDraws.length, 3);
    for (const draw of result.textDraws) {
        const width = draw.text.length * draw.fontSize * 0.6;
        const left = draw.align === "center" ? draw.x - width / 2 : draw.x;
        assert.ok(left >= safe - 1e-6);
        assert.ok(left + width <= sizePx - safe + 1e-6);
        assert.ok(draw.y - draw.fontSize * 0.7 >= safe - 1e-6);
        assert.ok(draw.y + draw.fontSize * 0.7 <= sizePx - safe + 1e-6);
    }
    assert.deepEqual(
        page,
        original,
        "export corrects legacy positions without mutating the book",
    );
});

test(`${sizeMm} mm rendering switches centered page text to photo captions`, async () => {
    const page = {
        ...makeBlankPage(),
        centerText: "Summer\n2026",
        topCaption: "Top",
        bottomCaption: "Bottom",
    };
    const original = structuredClone(page);
    const sizePx = Math.round((sizeMm / 25.4) * 300);
    const empty = (await renderPageToCanvas(
        makeBlankPage(),
        () => Promise.resolve(null),
        sizePx,
        sizePx,
    )) as unknown as CanvasRecord;
    assert.deepEqual(
        empty.textDraws,
        [],
        "never exports Add text... on an empty page",
    );
    const result = (await renderPageToCanvas(
        page,
        () => Promise.resolve(null),
        sizePx,
        sizePx,
    )) as unknown as CanvasRecord;
    assert.deepEqual(
        result.textDraws.map((draw) => draw.text),
        ["Summer", "2026"],
    );
    assert.ok(
        result.textDraws.every(
            (draw) => draw.align === "center" && draw.x === sizePx / 2,
        ),
    );
    assert.ok(
        Math.abs(
            (result.textDraws[0]!.y + result.textDraws[1]!.y) / 2 - sizePx / 2,
        ) < 1e-6,
    );
    const withPhoto = (await renderPageToCanvas(
        { ...page, slots: applyVariant("1-moderate", ["photo"]) },
        (id) => Promise.resolve(`test:${id}`),
        sizePx,
        sizePx,
    )) as unknown as CanvasRecord;
    assert.deepEqual(
        withPhoto.textDraws.map((draw) => draw.text),
        ["Top", "Bottom"],
    );
    assert.deepEqual(page, original, "hiding text retains the saved value");
});

test(`${sizeMm} mm rendering places the entire back logo inside the safe area`, async () => {
    const sizePx = Math.round((sizeMm / 25.4) * 300);
    const result = (await renderPageToCanvas(
        makeBlankPage(),
        () => Promise.resolve(null),
        sizePx,
        sizePx,
        true,
    )) as unknown as CanvasRecord;
    assert.equal(result.imageDraws.length, 1);
    const logo = result.imageDraws[0]!;
    const bottomGapMm = ((sizePx - logo.y - logo.height) / sizePx) * sizeMm;
    assert.ok(bottomGapMm >= 10 - 1e-6);
    assert.ok(Math.abs(bottomGapMm - 10) < 1e-6);
});

test(`${sizeMm} mm exports wrap page text at the same size as the cover title`, async () => {
    const centerText =
        "John didn't practise or sit around in his room thinking about drumming, he just did it and was magnificent.";
    const page = { ...makeBlankPage(), centerText };
    const sizePx = Math.round((sizeMm / 25.4) * 300);
    const result = (await renderPageToCanvas(
        page,
        () => Promise.resolve(null),
        sizePx,
        sizePx,
    )) as unknown as CanvasRecord;
    const cover = (await renderPageToCanvas(
        {
            ...makeBlankPage(),
            slots: applyVariant("1-padded", ["photo"]),
            topCaption: "Summer",
        },
        (id) => Promise.resolve(`test:${id}`),
        sizePx,
        sizePx,
        false,
        true,
    )) as unknown as CanvasRecord;
    assert.ok(
        result.textDraws.length > 1,
        "a paragraph wraps without manual line breaks",
    );
    assert.equal(
        result.textDraws.map((draw) => draw.text).join(" "),
        centerText,
    );
    for (const draw of result.textDraws) {
        assert.equal(draw.align, "center");
        assert.equal(draw.x, sizePx / 2);
        assert.equal(
            draw.fontSize,
            cover.textDraws[0]!.fontSize,
            "page text matches the rendered cover title size",
        );
        assert.ok(draw.text.length * draw.fontSize * 0.6 <= sizePx * 0.64);
    }
    const first = result.textDraws[0]!;
    const last = result.textDraws.at(-1)!;
    assert.ok(Math.abs((first.y + last.y) / 2 - sizePx / 2) < 1e-6);
    assert.equal(page.centerText, centerText);
});
