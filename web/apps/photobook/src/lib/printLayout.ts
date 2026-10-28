import {
    BOOK_LAYOUT,
    BOOK_SIZE_MM,
    PRINT_SAFE_MARGIN_PCT,
} from "./bookFormats";
import { getCaptionZones } from "./layouts";
import type { BookPage, TextBlock } from "./types";

export const TEXT_LINE_HEIGHT = 1.4;
export const CENTER_TEXT_FONT_WEIGHT = 600;
export const CAPTION_FONT_WEIGHT = 300;
// Match the title size that fits in the inset cover's caption band.
const TITLE_FONT_SIZE = Math.min(
    5,
    ((BOOK_LAYOUT.coverInsetMarginMm.v / BOOK_SIZE_MM) * 100 -
        2 * PRINT_SAFE_MARGIN_PCT) /
        TEXT_LINE_HEIGHT,
);
export const SAFE_AREA = {
    x: PRINT_SAFE_MARGIN_PCT,
    y: PRINT_SAFE_MARGIN_PCT,
    width: 100 - 2 * PRINT_SAFE_MARGIN_PCT,
    height: 100 - 2 * PRINT_SAFE_MARGIN_PCT,
};

export function getInterFont(): string {
    if (typeof window === "undefined") return "sans-serif";
    return (
        getComputedStyle(document.body)
            .getPropertyValue("--font-inter")
            .trim() || "sans-serif"
    );
}

export function getOutfitFont(): string {
    if (typeof window === "undefined") return "sans-serif";
    return (
        getComputedStyle(document.body)
            .getPropertyValue("--font-outfit")
            .trim() || "sans-serif"
    );
}

export type MeasureText = (
    text: string,
    fontSize: number,
    bold: boolean,
) => number;
let measureContext: CanvasRenderingContext2D | null = null;
function measureTextWithFont(
    text: string,
    fontSize: number,
    fontFamily: string,
    fontWeight: number,
): number {
    // Measure at a fixed reference scale so editor zoom and export resolution
    // cannot change line fitting or the saved position.
    measureContext ??= document.createElement("canvas").getContext("2d");
    if (!measureContext) throw new Error("Unable to measure text.");
    measureContext.font = `${fontWeight} ${fontSize * 10}px ${fontFamily}, sans-serif`;
    const metrics = measureContext.measureText(text);
    return Math.max(metrics.width, metrics.actualBoundingBoxRight || 0) / 10;
}

const measureBookText: MeasureText = (text, fontSize, bold) =>
    measureTextWithFont(text, fontSize, getInterFont(), bold ? 700 : 400);
const measureCaptionText: MeasureText = (text, fontSize) =>
    measureTextWithFont(text, fontSize, getInterFont(), CAPTION_FONT_WEIGHT);
const measureCenterText: MeasureText = (text, fontSize) =>
    measureTextWithFont(
        text,
        fontSize,
        getOutfitFont(),
        CENTER_TEXT_FONT_WEIGHT,
    );

export interface CaptionLayout {
    x: number;
    y: number;
    width: number;
    height: number;
    fontSize: number;
}

export function getCaptionLayout(
    page: BookPage,
    position: "top" | "bottom",
    isFrontCover = false,
    measure: MeasureText = isFrontCover
        ? measureCenterText
        : measureCaptionText,
): CaptionLayout | null {
    if (!page.slots.some((slot) => slot.photoId)) return null;
    const zones = getCaptionZones(page);
    const zone = position === "top" ? zones.topPct : zones.bottomPct;
    // Equal insets from the paper edge and the photo centre the caption in
    // the entire white margin while keeping its text inside the safe area.
    const height = zone - 2 * PRINT_SAFE_MARGIN_PCT;
    if (height <= 0) return null;
    const text = position === "top" ? page.topCaption : page.bottomCaption;
    let fontSize = Math.min(
        isFrontCover ? TITLE_FONT_SIZE : 1.6,
        height / TEXT_LINE_HEIGHT,
    );
    if (text) {
        const textWidth = measure(text, fontSize, false) + fontSize * 0.2;
        fontSize *= Math.min(1, SAFE_AREA.width / textWidth);
    }
    return {
        x: SAFE_AREA.x,
        y:
            position === "top"
                ? SAFE_AREA.y
                : 100 - zone + PRINT_SAFE_MARGIN_PCT,
        width: SAFE_AREA.width,
        height,
        fontSize,
    };
}

export interface CenterTextLayout extends CaptionLayout {
    lines: string[];
    lineHeight: number;
    padding: number;
}

const CENTER_TEXT_WIDTH = 64;
const CENTER_TEXT_LINE_HEIGHT = 1.2;

function wrapCenterText(
    text: string,
    fontSize: number,
    width: number,
    measure: MeasureText,
): string[] {
    return text.split(/\r?\n/).flatMap((paragraph) => {
        const lines: string[] = [];
        let line = "";
        let space = "";
        for (const token of paragraph.match(/\s+|\S+/g) ?? []) {
            if (/^\s+$/.test(token)) {
                space += token;
                continue;
            }
            const candidate = line + space + token;
            if (measure(candidate, fontSize, false) <= width) {
                line = candidate;
                space = "";
                continue;
            }
            if (line) lines.push(line);
            line = "";
            space = "";
            if (measure(token, fontSize, false) <= width) {
                line = token;
                continue;
            }
            // Long words and scripts without spaces still wrap within the column.
            const graphemes = new Intl.Segmenter(undefined, {
                granularity: "grapheme",
            }).segment(token);
            for (const { segment } of graphemes) {
                if (line && measure(line + segment, fontSize, false) > width) {
                    lines.push(line);
                    line = "";
                }
                line += segment;
            }
        }
        lines.push(line);
        return lines;
    });
}

export function getCenterTextLayout(
    page: BookPage,
    measure: MeasureText = measureCenterText,
): CenterTextLayout | null {
    if (page.slots.some((slot) => slot.photoId)) return null;
    const text = page.centerText || "Add text...";
    const wrap = (size: number) =>
        wrapCenterText(text, size, CENTER_TEXT_WIDTH - size * 0.2, measure);
    let fontSize = TITLE_FONT_SIZE;
    let lines = wrap(fontSize);
    // Keep the large type size as lines are added. Only fit smaller if the
    // entire paragraph would otherwise overflow the page's print safe area.
    if (lines.length * fontSize * CENTER_TEXT_LINE_HEIGHT > SAFE_AREA.height) {
        let low = 0;
        let high = fontSize;
        for (let i = 0; i < 20; i++) {
            const candidate = (low + high) / 2;
            if (
                wrap(candidate).length * candidate * CENTER_TEXT_LINE_HEIGHT <=
                SAFE_AREA.height
            )
                low = candidate;
            else high = candidate;
        }
        fontSize = low;
        lines = wrap(fontSize);
    }
    const height = lines.length * fontSize * CENTER_TEXT_LINE_HEIGHT;
    return {
        x: (100 - CENTER_TEXT_WIDTH) / 2,
        y: (100 - height) / 2,
        width: CENTER_TEXT_WIDTH,
        height,
        fontSize,
        lines,
        lineHeight: CENTER_TEXT_LINE_HEIGHT,
        padding: fontSize * 0.1,
    };
}

export function getBrandingLayout(aspectRatio = 844 / 264) {
    const height = 3.1;
    const width = height * aspectRatio;
    return {
        x: (100 - width) / 2,
        y: 100 - PRINT_SAFE_MARGIN_PCT - height,
        width,
        height,
    };
}

function getRotatedBounds(width: number, height: number, rotation: number) {
    const angle = (rotation * Math.PI) / 180;
    const cos = Math.cos(angle);
    const sin = Math.sin(angle);
    const xs = [0, width * cos, -height * sin, width * cos - height * sin];
    const ys = [0, width * sin, height * cos, width * sin + height * cos];
    return {
        left: Math.min(...xs),
        right: Math.max(...xs),
        top: Math.min(...ys),
        bottom: Math.max(...ys),
    };
}

export function getTextBlockLayout(
    block: TextBlock,
    measure: MeasureText = measureBookText,
) {
    const lines = (block.text || "Type here").split(/\r?\n/);
    let fontSize = Math.max(0.1, block.fontSize ?? 2.5);
    // Include space for glyph overhangs at both ends of each line.
    let padding = fontSize * 0.1;
    let width =
        Math.max(
            ...lines.map((line) => measure(line, fontSize, true)),
            fontSize,
        ) +
        padding * 2;
    let height = lines.length * fontSize * TEXT_LINE_HEIGHT;
    const rotation = block.rotation ?? 0;
    let bounds = getRotatedBounds(width, height, rotation);
    const scale = Math.min(
        1,
        SAFE_AREA.width / (bounds.right - bounds.left),
        SAFE_AREA.height / (bounds.bottom - bounds.top),
    );
    fontSize *= scale;
    padding *= scale;
    width *= scale;
    height *= scale;
    bounds = getRotatedBounds(width, height, rotation);
    const x = Math.max(
        SAFE_AREA.x - bounds.left,
        Math.min(100 - SAFE_AREA.x - bounds.right, block.x),
    );
    const y = Math.max(
        SAFE_AREA.y - bounds.top,
        Math.min(100 - SAFE_AREA.y - bounds.bottom, block.y),
    );
    return {
        ...block,
        x,
        y,
        width,
        height,
        fontSize,
        rotation,
        padding,
        lines,
    };
}

export function constrainTextBlock(block: TextBlock): TextBlock {
    const { x, y, width, height, fontSize } = getTextBlockLayout(block);
    if (
        x === block.x &&
        y === block.y &&
        width === block.width &&
        height === block.height &&
        fontSize === block.fontSize
    )
        return block;
    return { ...block, x, y, width, height, fontSize };
}
