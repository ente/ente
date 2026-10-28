import assert from "node:assert/strict";
import { test } from "vitest";
import { makeBlankPage } from "./bookPages";
import { applyVariant, getMirrorVariant, getVariantsForCount } from "./layouts";
import {
    getBrandingLayout,
    getCaptionLayout,
    getCenterTextLayout,
    getTextBlockLayout,
    SAFE_AREA,
    TEXT_LINE_HEIGHT,
    type MeasureText,
} from "./printLayout";
import type { TextBlock } from "./types";

const sizeMm = 210;

const measure: MeasureText = (text, fontSize) => text.length * fontSize * 0.6;
const coverTitleFontSize = getCaptionLayout(
    { ...makeBlankPage(), slots: applyVariant("1-padded", ["photo"]) },
    "top",
    true,
    measure,
)!.fontSize;
const epsilon = 1e-9;
const baseBlock: TextBlock = {
    id: "text",
    text: "Holiday",
    x: 20,
    y: 30,
    width: 45,
    height: 15,
    fontSize: 2.5,
    rotation: 0,
    style: "body",
    alignment: "left",
    color: "#555555",
};

function assertSafeText(block: TextBlock) {
    const layout = getTextBlockLayout(block, measure);
    const angle = (layout.rotation * Math.PI) / 180;
    // Check every transformed corner, independently of the layout's bounds helper.
    for (const [x, y] of [
        [0, 0],
        [layout.width, 0],
        [0, layout.height],
        [layout.width, layout.height],
    ] as const) {
        const pageX =
            ((layout.x + x * Math.cos(angle) - y * Math.sin(angle)) / 100) *
            sizeMm;
        const pageY =
            ((layout.y + x * Math.sin(angle) + y * Math.cos(angle)) / 100) *
            sizeMm;
        assert.ok(
            pageX >= 10 - epsilon && pageX <= sizeMm - 10 + epsilon,
            `unsafe x: ${pageX}`,
        );
        assert.ok(
            pageY >= 10 - epsilon && pageY <= sizeMm - 10 + epsilon,
            `unsafe y: ${pageY}`,
        );
    }
    return layout;
}

test("ordinary captions fit wholly inside the 10 mm safe area on 210 mm pages", () => {
    const page = {
        ...makeBlankPage(),
        slots: applyVariant("1-moderate", ["photo"]),
        topCaption: "Summer",
        bottomCaption: "2026",
    };
    for (const position of ["top", "bottom"] as const) {
        const layout = getCaptionLayout(page, position, false, measure)!;
        const center = ((layout.y + layout.height / 2) / 100) * sizeMm;
        const halfLine = ((layout.fontSize * TEXT_LINE_HEIGHT) / 200) * sizeMm;
        assert.ok(center - halfLine >= 10);
        assert.ok(center + halfLine <= sizeMm - 10);
        assert.equal(
            layout.fontSize,
            1.6,
            "normal captions retain their font size",
        );
        assert.ok(Math.abs(Math.min(center, sizeMm - center) - 12.5) < epsilon);
    }
});

test("cover titles have equal space toward the photo and paper edge in both inset layouts", () => {
    for (const variant of ["1-moderate", "1-padded"]) {
        const page = {
            ...makeBlankPage(),
            slots: applyVariant(variant, ["photo"]),
            topCaption: "Our holiday",
            bottomCaption: "2026",
        };
        for (const position of ["top", "bottom"] as const) {
            const layout = getCaptionLayout(page, position, true, measure)!;
            const photo = page.slots[0]!;
            const gap =
                position === "top"
                    ? photo.y - layout.y - layout.height
                    : layout.y - photo.y - photo.height;
            const outerGap =
                position === "top" ? layout.y : 100 - layout.y - layout.height;
            assert.ok(
                Math.abs(gap - outerGap) < epsilon,
                `${variant} ${position}: the caption is centred in the white margin`,
            );
            assert.ok((gap / 100) * sizeMm >= 10 - epsilon);
            assert.ok((layout.y / 100) * sizeMm >= 10 - epsilon);
            assert.ok(
                ((layout.y + layout.height) / 100) * sizeMm <=
                    sizeMm - 10 + epsilon,
            );
            assert.ok(
                layout.fontSize * TEXT_LINE_HEIGHT <= layout.height + epsilon,
            );
        }
    }
});

test("all padded layouts centre captions and placeholders in the full white margin", () => {
    const keys = new Set(
        [1, 2, 3, 4].flatMap((count) =>
            getVariantsForCount(count)
                .flatMap((variant) => [
                    variant.key,
                    getMirrorVariant(variant.key),
                ])
                .filter((key): key is string => !!key && key !== "1-full"),
        ),
    );
    for (const key of keys) {
        const count = Number(key[0]!);
        const slots = applyVariant(
            key,
            Array.from({ length: count }, (_, i) => `photo-${i}`),
        );
        const page = { ...makeBlankPage(), slots };
        const top = Math.min(...slots.map((slot) => slot.y));
        const bottom = Math.max(...slots.map((slot) => slot.y + slot.height));
        for (const position of ["top", "bottom"] as const) {
            const placeholder = getCaptionLayout(
                page,
                position,
                false,
                measure,
            )!;
            const caption = getCaptionLayout(
                { ...page, topCaption: "Summer", bottomCaption: "2026" },
                position,
                false,
                measure,
            )!;
            assert.deepEqual(
                placeholder,
                caption,
                "adding a caption does not shift its position or shrink its font",
            );
            assert.equal(caption.fontSize, 1.6);
            const gap =
                position === "top"
                    ? top - caption.y - caption.height
                    : caption.y - bottom;
            const outerGap =
                position === "top"
                    ? caption.y
                    : 100 - caption.y - caption.height;
            assert.ok(
                Math.abs(gap - outerGap) < epsilon,
                `${key} ${position}: equal space on both sides of the caption`,
            );
            assert.ok((gap / 100) * sizeMm >= 10 - epsilon);
            assert.ok((caption.y / 100) * sizeMm >= 10 - epsilon);
            assert.ok(
                ((caption.y + caption.height) / 100) * sizeMm <=
                    sizeMm - 10 + epsilon,
            );
        }
    }
});

test("captions are hidden when the photo leaves no safe caption band", () => {
    const page = {
        ...makeBlankPage(),
        slots: applyVariant("1-full", ["photo"]),
        topCaption: "Old caption",
    };
    assert.equal(getCaptionLayout(page, "top", true, measure), null);
    assert.equal(getCaptionLayout(page, "bottom", true, measure), null);
});

test("long captions shrink to fit the safe width without changing their content", () => {
    const text = "A long caption with all the names and places. ".repeat(10);
    const page = {
        ...makeBlankPage(),
        slots: applyVariant("1-moderate", ["photo"]),
        topCaption: text,
        bottomCaption: text,
    };
    for (const position of ["top", "bottom"] as const) {
        const layout = getCaptionLayout(page, position, false, measure)!;
        assert.ok(layout.fontSize < 1.6);
        assert.ok(measure(text, layout.fontSize, false) <= layout.width);
        assert.ok(layout.x * 2.1 >= 10 - epsilon);
        assert.ok((layout.x + layout.width) * 2.1 <= 200 + epsilon);
    }
    assert.equal(page.topCaption, text);
    assert.equal(page.bottomCaption, text);
});

test("back-cover logo ends 10 mm above the page edge", () => {
    const layout = getBrandingLayout();
    const bottomGap = 100 - layout.y - layout.height;
    assert.ok(Math.abs((bottomGap / 100) * 210 - 10) < epsilon);
    assert.ok(Math.abs(layout.x + layout.width / 2 - 50) < epsilon);
});

test("adding and removing photos switches between centered text and captions", () => {
    const page = {
        ...makeBlankPage(),
        centerText: "Summer in the city",
        topCaption: "Summer",
        bottomCaption: "2026",
    };
    const centered = getCenterTextLayout(page, measure)!;
    assert.equal(centered.fontSize, coverTitleFontSize);
    assert.equal(centered.x + centered.width / 2, 50);
    assert.equal(centered.y + centered.height / 2, 50);
    assert.equal(getCaptionLayout(page, "top", false, measure), null);
    assert.equal(getCaptionLayout(page, "bottom", false, measure), null);

    const withPhoto = { ...page, slots: applyVariant("1-moderate", ["photo"]) };
    assert.equal(getCenterTextLayout(withPhoto, measure), null);
    assert.ok(getCaptionLayout(withPhoto, "top", false, measure));
    assert.ok(getCaptionLayout(withPhoto, "bottom", false, measure));
    const emptied = {
        ...withPhoto,
        slots: withPhoto.slots.map((slot) => ({ ...slot, photoId: null })),
    };
    assert.deepEqual(getCenterTextLayout(emptied, measure), centered);
    assert.equal(getCaptionLayout(emptied, "top", false, measure), null);
    assert.equal(emptied.centerText, page.centerText);
});

test("page text wraps at a fixed column width without shrinking ordinary paragraphs", () => {
    const centerText =
        "John didn't practise or sit around in his room thinking about drumming, he just did it and was magnificent.";
    const page = { ...makeBlankPage(), centerText };
    const layout = getCenterTextLayout(page, measure)!;
    const short = getCenterTextLayout(
        { ...page, centerText: "Summer" },
        measure,
    )!;
    assert.equal(layout.width, 64);
    assert.equal(layout.width, short.width);
    assert.equal(layout.fontSize, short.fontSize);
    assert.equal(layout.fontSize, coverTitleFontSize);
    assert.ok(layout.lines.length > 1);
    assert.equal(layout.lines.join(" "), centerText);
    assert.equal(layout.x + layout.width / 2, 50);
    assert.equal(layout.y + layout.height / 2, 50);
    for (const line of layout.lines)
        assert.ok(
            measure(line, layout.fontSize, false) <=
                layout.width - layout.padding * 2,
        );
    assert.equal(
        page.centerText,
        centerText,
        "automatic wrapping does not insert saved line breaks",
    );
});

test("page text retains explicit blank lines and wraps unbroken words", () => {
    const page = makeBlankPage();
    assert.deepEqual(
        getCenterTextLayout({ ...page, centerText: "Summer\n\n2026" }, measure)!
            .lines,
        ["Summer", "", "2026"],
    );
    const word = "supercalifragilisticexpialidocious";
    const layout = getCenterTextLayout({ ...page, centerText: word }, measure)!;
    assert.ok(layout.lines.length > 1);
    assert.equal(layout.lines.join(""), word);
    assert.equal(layout.fontSize, coverTitleFontSize);
    for (const line of layout.lines)
        assert.ok(
            measure(line, layout.fontSize, false) <=
                layout.width - layout.padding * 2,
        );
});

test("page-length text fits inside the print safe area without changing the column width", () => {
    for (const centerText of [
        "A long line of text. ".repeat(60),
        "A line\n".repeat(30),
    ]) {
        const layout = getCenterTextLayout(
            { ...makeBlankPage(), centerText },
            measure,
        )!;
        assert.ok(layout.fontSize < coverTitleFontSize);
        assert.equal(layout.width, 64);
        assert.equal(layout.x + layout.width / 2, 50);
        assert.equal(layout.y + layout.height / 2, 50);
        assert.ok(layout.y >= SAFE_AREA.y - epsilon);
        assert.ok(layout.y + layout.height <= 100 - SAFE_AREA.y + epsilon);
        for (const line of layout.lines) {
            assert.ok(
                measure(line, layout.fontSize, false) <=
                    layout.width - layout.padding * 2,
            );
        }
    }
});

test("dragging custom text past any edge clamps every rotated corner", () => {
    for (const rotation of [0, 30, 90, 135, 180, 270, -45]) {
        for (const x of [-100, 50, 200]) {
            for (const y of [-100, 50, 200]) {
                const layout = assertSafeText({ ...baseBlock, x, y, rotation });
                assert.equal(
                    layout.fontSize,
                    baseBlock.fontSize,
                    "dragging ordinary text does not shrink it",
                );
            }
        }
    }
});

test("resizing or extending custom text keeps every line inside the safe area", () => {
    for (const rotation of [0, 45, -90]) {
        for (const text of [
            "A very long single line. ".repeat(25),
            "Several lines\n".repeat(30),
        ]) {
            const original = {
                ...baseBlock,
                text,
                fontSize: 6,
                x: 95,
                y: 98,
                rotation,
            };
            const before = structuredClone(original);
            const layout = assertSafeText(original);
            assert.ok(layout.fontSize < original.fontSize);
            assert.equal(
                layout.lines.join("\n"),
                text,
                "retains all content and explicit line breaks",
            );
            assert.deepEqual(
                original,
                before,
                "rendering does not mutate saved text",
            );
        }
    }
});

test("safe text retains its position, rotation and font size", () => {
    const layout = assertSafeText(baseBlock);
    assert.equal(layout.x, baseBlock.x);
    assert.equal(layout.y, baseBlock.y);
    assert.equal(layout.fontSize, baseBlock.fontSize);
    assert.equal(layout.rotation, baseBlock.rotation);
});
