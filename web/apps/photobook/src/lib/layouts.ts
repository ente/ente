import { BOOK_LAYOUT, BOOK_SIZE_MM } from "./bookFormats";
import { makeBlankPage, normalizeBookPages } from "./bookPages";
import type { BookPage, Photo, PhotoSlot } from "./types";

export interface LayoutMetrics {
    marginH: number;
    marginV: number;
    hGap: number;
    vGap: number;
    left: number;
    top: number;
    cw: number;
    ch: number;
}

function mmToPct(mm: number, totalMm: number): number {
    return (mm / totalMm) * 100;
}

export function getLayoutMetrics(): LayoutMetrics {
    const format = BOOK_LAYOUT;
    const marginH = mmToPct(format.marginMm.h, BOOK_SIZE_MM);
    const marginV = mmToPct(format.marginMm.v, BOOK_SIZE_MM);

    return {
        marginH,
        marginV,
        hGap: mmToPct(format.gapMm.h, BOOK_SIZE_MM),
        vGap: mmToPct(format.gapMm.v, BOOK_SIZE_MM),
        left: marginH,
        top: marginV,
        cw: 100 - 2 * marginH,
        ch: 100 - 2 * marginV,
    };
}

type Orientation = "landscape" | "portrait" | "square";

function getOrientation(photo: Photo): Orientation {
    const ratio = photo.width / photo.height;
    if (ratio > 1.15) return "landscape";
    if (ratio < 0.85) return "portrait";
    return "square";
}

function makeSlot(
    photoId: string,
    x: number,
    y: number,
    w: number,
    h: number,
): PhotoSlot {
    return {
        id: crypto.randomUUID(),
        photoId,
        x,
        y,
        width: w,
        height: h,
        cropX: 0.5,
        cropY: 0.5,
        cropZoom: 1,
    };
}

// ── Layout variant system ──────────────────────────────────────────

export interface LayoutVariant {
    key: string;
    photoCount: number;
    generate: (photoIds: string[], metrics: LayoutMetrics) => PhotoSlot[];
}

// Slot position (no photo ID) for thumbnail preview rendering
export interface SlotPosition {
    x: number;
    y: number;
    width: number;
    height: number;
}

// ── 1-photo variants ──────────────────────────────────────────────

function gen1Padded(ids: string[]): PhotoSlot[] {
    const left = mmToPct(BOOK_LAYOUT.coverInsetMarginMm.h, BOOK_SIZE_MM);
    const top = mmToPct(BOOK_LAYOUT.coverInsetMarginMm.v, BOOK_SIZE_MM);
    return [makeSlot(ids[0]!, left, top, 100 - 2 * left, 100 - 2 * top)];
}

function gen1Moderate(ids: string[], m: LayoutMetrics): PhotoSlot[] {
    return [makeSlot(ids[0]!, m.left, m.top, m.cw, m.ch)];
}

function gen1Full(ids: string[]): PhotoSlot[] {
    return [makeSlot(ids[0]!, 0, 0, 100, 100)];
}

// ── 2-photo variants ──────────────────────────────────────────────

function gen2Stacked(ids: string[], m: LayoutMetrics): PhotoSlot[] {
    const { left: LEFT, top: TOP, cw: CW, ch: CH, vGap: V_GAP } = m;
    const halfH = (CH - V_GAP) / 2;
    return [
        makeSlot(ids[0]!, LEFT, TOP, CW, halfH),
        makeSlot(ids[1]!, LEFT, TOP + halfH + V_GAP, CW, halfH),
    ];
}

function gen2SideBySide(ids: string[], m: LayoutMetrics): PhotoSlot[] {
    const { left: LEFT, top: TOP, cw: CW, ch: CH, hGap: H_GAP } = m;
    const halfW = (CW - H_GAP) / 2;
    return [
        makeSlot(ids[0]!, LEFT, TOP, halfW, CH),
        makeSlot(ids[1]!, LEFT + halfW + H_GAP, TOP, halfW, CH),
    ];
}

function gen2BigTop(ids: string[], m: LayoutMetrics): PhotoSlot[] {
    const { left: LEFT, top: TOP, cw: CW, ch: CH, vGap: V_GAP } = m;
    const bigH = CH * 0.62;
    const smallH = CH - bigH - V_GAP;
    return [
        makeSlot(ids[0]!, LEFT, TOP, CW, bigH),
        makeSlot(ids[1]!, LEFT, TOP + bigH + V_GAP, CW, smallH),
    ];
}

function gen2BigLeft(ids: string[], m: LayoutMetrics): PhotoSlot[] {
    const { left: LEFT, top: TOP, cw: CW, ch: CH, hGap: H_GAP } = m;
    const bigW = CW * 0.62;
    const smallW = CW - bigW - H_GAP;
    return [
        makeSlot(ids[0]!, LEFT, TOP, bigW, CH),
        makeSlot(ids[1]!, LEFT + bigW + H_GAP, TOP, smallW, CH),
    ];
}

function gen2BigBottom(ids: string[], m: LayoutMetrics): PhotoSlot[] {
    const { left: LEFT, top: TOP, cw: CW, ch: CH, vGap: V_GAP } = m;
    const bigH = CH * 0.62;
    const smallH = CH - bigH - V_GAP;
    return [
        makeSlot(ids[0]!, LEFT, TOP, CW, smallH),
        makeSlot(ids[1]!, LEFT, TOP + smallH + V_GAP, CW, bigH),
    ];
}

function gen2BigRight(ids: string[], m: LayoutMetrics): PhotoSlot[] {
    const { left: LEFT, top: TOP, cw: CW, ch: CH, hGap: H_GAP } = m;
    const bigW = CW * 0.62;
    const smallW = CW - bigW - H_GAP;
    return [
        makeSlot(ids[0]!, LEFT, TOP, smallW, CH),
        makeSlot(ids[1]!, LEFT + smallW + H_GAP, TOP, bigW, CH),
    ];
}

// ── 3-photo variants ──────────────────────────────────────────────

function gen3Top1Bot2(ids: string[], m: LayoutMetrics): PhotoSlot[] {
    const {
        left: LEFT,
        top: TOP,
        cw: CW,
        ch: CH,
        hGap: H_GAP,
        vGap: V_GAP,
    } = m;
    const topH = CH * 0.55;
    const botH = CH - topH - V_GAP;
    const halfW = (CW - H_GAP) / 2;
    return [
        makeSlot(ids[0]!, LEFT, TOP, CW, topH),
        makeSlot(ids[1]!, LEFT, TOP + topH + V_GAP, halfW, botH),
        makeSlot(
            ids[2]!,
            LEFT + halfW + H_GAP,
            TOP + topH + V_GAP,
            halfW,
            botH,
        ),
    ];
}

function gen3Left1Right2(ids: string[], m: LayoutMetrics): PhotoSlot[] {
    const {
        left: LEFT,
        top: TOP,
        cw: CW,
        ch: CH,
        hGap: H_GAP,
        vGap: V_GAP,
    } = m;
    const leftW = CW * 0.55;
    const rightW = CW - leftW - H_GAP;
    const halfH = (CH - V_GAP) / 2;
    return [
        makeSlot(ids[0]!, LEFT, TOP, leftW, CH),
        makeSlot(ids[1]!, LEFT + leftW + H_GAP, TOP, rightW, halfH),
        makeSlot(
            ids[2]!,
            LEFT + leftW + H_GAP,
            TOP + halfH + V_GAP,
            rightW,
            halfH,
        ),
    ];
}

function gen3Bot1Top2(ids: string[], m: LayoutMetrics): PhotoSlot[] {
    const {
        left: LEFT,
        top: TOP,
        cw: CW,
        ch: CH,
        hGap: H_GAP,
        vGap: V_GAP,
    } = m;
    const botH = CH * 0.55;
    const topH = CH - botH - V_GAP;
    const halfW = (CW - H_GAP) / 2;
    return [
        makeSlot(ids[0]!, LEFT, TOP, halfW, topH),
        makeSlot(ids[1]!, LEFT + halfW + H_GAP, TOP, halfW, topH),
        makeSlot(ids[2]!, LEFT, TOP + topH + V_GAP, CW, botH),
    ];
}

function gen3Right1Left2(ids: string[], m: LayoutMetrics): PhotoSlot[] {
    const {
        left: LEFT,
        top: TOP,
        cw: CW,
        ch: CH,
        hGap: H_GAP,
        vGap: V_GAP,
    } = m;
    const rightW = CW * 0.55;
    const leftW = CW - rightW - H_GAP;
    const halfH = (CH - V_GAP) / 2;
    return [
        makeSlot(ids[0]!, LEFT, TOP, leftW, halfH),
        makeSlot(ids[1]!, LEFT, TOP + halfH + V_GAP, leftW, halfH),
        makeSlot(ids[2]!, LEFT + leftW + H_GAP, TOP, rightW, CH),
    ];
}

function gen3EqualRows(ids: string[], m: LayoutMetrics): PhotoSlot[] {
    const { left: LEFT, top: TOP, cw: CW, ch: CH, vGap: V_GAP } = m;
    const rowH = (CH - V_GAP * 2) / 3;
    return [
        makeSlot(ids[0]!, LEFT, TOP, CW, rowH),
        makeSlot(ids[1]!, LEFT, TOP + rowH + V_GAP, CW, rowH),
        makeSlot(ids[2]!, LEFT, TOP + (rowH + V_GAP) * 2, CW, rowH),
    ];
}

function gen3EqualCols(ids: string[], m: LayoutMetrics): PhotoSlot[] {
    const { left: LEFT, top: TOP, cw: CW, ch: CH, hGap: H_GAP } = m;
    const colW = (CW - H_GAP * 2) / 3;
    return [
        makeSlot(ids[0]!, LEFT, TOP, colW, CH),
        makeSlot(ids[1]!, LEFT + colW + H_GAP, TOP, colW, CH),
        makeSlot(ids[2]!, LEFT + (colW + H_GAP) * 2, TOP, colW, CH),
    ];
}

function gen3DominantTop(ids: string[], m: LayoutMetrics): PhotoSlot[] {
    const {
        left: LEFT,
        top: TOP,
        cw: CW,
        ch: CH,
        hGap: H_GAP,
        vGap: V_GAP,
    } = m;
    const bigH = CH * 0.75;
    const smallH = CH - bigH - V_GAP;
    const halfW = (CW - H_GAP) / 2;
    return [
        makeSlot(ids[0]!, LEFT, TOP, CW, bigH),
        makeSlot(ids[1]!, LEFT, TOP + bigH + V_GAP, halfW, smallH),
        makeSlot(
            ids[2]!,
            LEFT + halfW + H_GAP,
            TOP + bigH + V_GAP,
            halfW,
            smallH,
        ),
    ];
}

function gen3DominantBottom(ids: string[], m: LayoutMetrics): PhotoSlot[] {
    const {
        left: LEFT,
        top: TOP,
        cw: CW,
        ch: CH,
        hGap: H_GAP,
        vGap: V_GAP,
    } = m;
    const bigH = CH * 0.75;
    const smallH = CH - bigH - V_GAP;
    const halfW = (CW - H_GAP) / 2;
    return [
        makeSlot(ids[0]!, LEFT, TOP, halfW, smallH),
        makeSlot(ids[1]!, LEFT + halfW + H_GAP, TOP, halfW, smallH),
        makeSlot(ids[2]!, LEFT, TOP + smallH + V_GAP, CW, bigH),
    ];
}

function gen3DominantLeft(ids: string[], m: LayoutMetrics): PhotoSlot[] {
    const {
        left: LEFT,
        top: TOP,
        cw: CW,
        ch: CH,
        hGap: H_GAP,
        vGap: V_GAP,
    } = m;
    const bigW = CW * 0.75;
    const smallW = CW - bigW - H_GAP;
    const halfH = (CH - V_GAP) / 2;
    return [
        makeSlot(ids[0]!, LEFT, TOP, bigW, CH),
        makeSlot(ids[1]!, LEFT + bigW + H_GAP, TOP, smallW, halfH),
        makeSlot(
            ids[2]!,
            LEFT + bigW + H_GAP,
            TOP + halfH + V_GAP,
            smallW,
            halfH,
        ),
    ];
}

function gen3DominantRight(ids: string[], m: LayoutMetrics): PhotoSlot[] {
    const {
        left: LEFT,
        top: TOP,
        cw: CW,
        ch: CH,
        hGap: H_GAP,
        vGap: V_GAP,
    } = m;
    const bigW = CW * 0.75;
    const smallW = CW - bigW - H_GAP;
    const halfH = (CH - V_GAP) / 2;
    return [
        makeSlot(ids[0]!, LEFT, TOP, smallW, halfH),
        makeSlot(ids[1]!, LEFT, TOP + halfH + V_GAP, smallW, halfH),
        makeSlot(ids[2]!, LEFT + smallW + H_GAP, TOP, bigW, CH),
    ];
}

// ── 4-photo variants ──────────────────────────────────────────────

function gen4Grid(ids: string[], m: LayoutMetrics): PhotoSlot[] {
    const {
        left: LEFT,
        top: TOP,
        cw: CW,
        ch: CH,
        hGap: H_GAP,
        vGap: V_GAP,
    } = m;
    const halfW = (CW - H_GAP) / 2;
    const halfH = (CH - V_GAP) / 2;
    return [
        makeSlot(ids[0]!, LEFT, TOP, halfW, halfH),
        makeSlot(ids[1]!, LEFT + halfW + H_GAP, TOP, halfW, halfH),
        makeSlot(ids[2]!, LEFT, TOP + halfH + V_GAP, halfW, halfH),
        makeSlot(
            ids[3]!,
            LEFT + halfW + H_GAP,
            TOP + halfH + V_GAP,
            halfW,
            halfH,
        ),
    ];
}

function gen4Staggered(ids: string[], m: LayoutMetrics): PhotoSlot[] {
    const { left, top, cw, ch, hGap, vGap } = m;
    const largeW = (cw - hGap) / 2;
    const largeH = (ch - vGap) * 0.56;
    const smallW = largeW * 0.68;
    const smallH = (ch - vGap) * 0.32;
    const rightX = left + largeW + hGap;
    const lowerY = top + ch - largeH;

    // The large photos anchor opposite corners; the smaller photos sit
    // against the center gutter, leaving white space at the other corners.
    return [
        makeSlot(ids[0]!, left, top, largeW, largeH),
        makeSlot(ids[1]!, rightX, lowerY - vGap - smallH, smallW, smallH),
        makeSlot(
            ids[2]!,
            left + largeW - smallW,
            top + largeH + vGap,
            smallW,
            smallH,
        ),
        makeSlot(ids[3]!, rightX, lowerY, largeW, largeH),
    ];
}

function gen4StaggeredReverse(ids: string[], m: LayoutMetrics): PhotoSlot[] {
    return gen4Staggered(ids, m).map((slot) => ({
        ...slot,
        x: m.left + m.cw - (slot.x - m.left) - slot.width,
    }));
}

function gen4Top1Bot3(ids: string[], m: LayoutMetrics): PhotoSlot[] {
    const {
        left: LEFT,
        top: TOP,
        cw: CW,
        ch: CH,
        hGap: H_GAP,
        vGap: V_GAP,
    } = m;
    const topH = CH * 0.5;
    const botH = CH - topH - V_GAP;
    const thirdW = (CW - H_GAP * 2) / 3;
    return [
        makeSlot(ids[0]!, LEFT, TOP, CW, topH),
        makeSlot(ids[1]!, LEFT, TOP + topH + V_GAP, thirdW, botH),
        makeSlot(
            ids[2]!,
            LEFT + thirdW + H_GAP,
            TOP + topH + V_GAP,
            thirdW,
            botH,
        ),
        makeSlot(
            ids[3]!,
            LEFT + thirdW * 2 + H_GAP * 2,
            TOP + topH + V_GAP,
            thirdW,
            botH,
        ),
    ];
}

function gen4Bot1Top3(ids: string[], m: LayoutMetrics): PhotoSlot[] {
    const {
        left: LEFT,
        top: TOP,
        cw: CW,
        ch: CH,
        hGap: H_GAP,
        vGap: V_GAP,
    } = m;
    const botH = CH * 0.5;
    const topH = CH - botH - V_GAP;
    const thirdW = (CW - H_GAP * 2) / 3;
    return [
        makeSlot(ids[0]!, LEFT, TOP, thirdW, topH),
        makeSlot(ids[1]!, LEFT + thirdW + H_GAP, TOP, thirdW, topH),
        makeSlot(ids[2]!, LEFT + thirdW * 2 + H_GAP * 2, TOP, thirdW, topH),
        makeSlot(ids[3]!, LEFT, TOP + topH + V_GAP, CW, botH),
    ];
}

function gen4Left1Right3(ids: string[], m: LayoutMetrics): PhotoSlot[] {
    const {
        left: LEFT,
        top: TOP,
        cw: CW,
        ch: CH,
        hGap: H_GAP,
        vGap: V_GAP,
    } = m;
    const leftW = CW * 0.5;
    const rightW = CW - leftW - H_GAP;
    const thirdH = (CH - V_GAP * 2) / 3;
    return [
        makeSlot(ids[0]!, LEFT, TOP, leftW, CH),
        makeSlot(ids[1]!, LEFT + leftW + H_GAP, TOP, rightW, thirdH),
        makeSlot(
            ids[2]!,
            LEFT + leftW + H_GAP,
            TOP + thirdH + V_GAP,
            rightW,
            thirdH,
        ),
        makeSlot(
            ids[3]!,
            LEFT + leftW + H_GAP,
            TOP + (thirdH + V_GAP) * 2,
            rightW,
            thirdH,
        ),
    ];
}

function gen4Right1Left3(ids: string[], m: LayoutMetrics): PhotoSlot[] {
    const {
        left: LEFT,
        top: TOP,
        cw: CW,
        ch: CH,
        hGap: H_GAP,
        vGap: V_GAP,
    } = m;
    const rightW = CW * 0.5;
    const leftW = CW - rightW - H_GAP;
    const thirdH = (CH - V_GAP * 2) / 3;
    return [
        makeSlot(ids[0]!, LEFT, TOP, leftW, thirdH),
        makeSlot(ids[1]!, LEFT, TOP + thirdH + V_GAP, leftW, thirdH),
        makeSlot(ids[2]!, LEFT, TOP + (thirdH + V_GAP) * 2, leftW, thirdH),
        makeSlot(ids[3]!, LEFT + leftW + H_GAP, TOP, rightW, CH),
    ];
}

function gen4WideLeft(ids: string[], m: LayoutMetrics): PhotoSlot[] {
    const {
        left: LEFT,
        top: TOP,
        cw: CW,
        ch: CH,
        hGap: H_GAP,
        vGap: V_GAP,
    } = m;
    const bigW = CW * 0.62;
    const smallW = CW - bigW - H_GAP;
    const halfH = (CH - V_GAP) / 2;
    return [
        makeSlot(ids[0]!, LEFT, TOP, bigW, halfH),
        makeSlot(ids[1]!, LEFT + bigW + H_GAP, TOP, smallW, halfH),
        makeSlot(ids[2]!, LEFT, TOP + halfH + V_GAP, bigW, halfH),
        makeSlot(
            ids[3]!,
            LEFT + bigW + H_GAP,
            TOP + halfH + V_GAP,
            smallW,
            halfH,
        ),
    ];
}

function gen4WideRight(ids: string[], m: LayoutMetrics): PhotoSlot[] {
    const {
        left: LEFT,
        top: TOP,
        cw: CW,
        ch: CH,
        hGap: H_GAP,
        vGap: V_GAP,
    } = m;
    const bigW = CW * 0.62;
    const smallW = CW - bigW - H_GAP;
    const halfH = (CH - V_GAP) / 2;
    return [
        makeSlot(ids[0]!, LEFT, TOP, smallW, halfH),
        makeSlot(ids[1]!, LEFT + smallW + H_GAP, TOP, bigW, halfH),
        makeSlot(ids[2]!, LEFT, TOP + halfH + V_GAP, smallW, halfH),
        makeSlot(
            ids[3]!,
            LEFT + smallW + H_GAP,
            TOP + halfH + V_GAP,
            bigW,
            halfH,
        ),
    ];
}

function gen4TallTop(ids: string[], m: LayoutMetrics): PhotoSlot[] {
    const {
        left: LEFT,
        top: TOP,
        cw: CW,
        ch: CH,
        hGap: H_GAP,
        vGap: V_GAP,
    } = m;
    const bigH = CH * 0.62;
    const smallH = CH - bigH - V_GAP;
    const halfW = (CW - H_GAP) / 2;
    return [
        makeSlot(ids[0]!, LEFT, TOP, halfW, bigH),
        makeSlot(ids[1]!, LEFT + halfW + H_GAP, TOP, halfW, bigH),
        makeSlot(ids[2]!, LEFT, TOP + bigH + V_GAP, halfW, smallH),
        makeSlot(
            ids[3]!,
            LEFT + halfW + H_GAP,
            TOP + bigH + V_GAP,
            halfW,
            smallH,
        ),
    ];
}

function gen4TallBottom(ids: string[], m: LayoutMetrics): PhotoSlot[] {
    const {
        left: LEFT,
        top: TOP,
        cw: CW,
        ch: CH,
        hGap: H_GAP,
        vGap: V_GAP,
    } = m;
    const bigH = CH * 0.62;
    const smallH = CH - bigH - V_GAP;
    const halfW = (CW - H_GAP) / 2;
    return [
        makeSlot(ids[0]!, LEFT, TOP, halfW, smallH),
        makeSlot(ids[1]!, LEFT + halfW + H_GAP, TOP, halfW, smallH),
        makeSlot(ids[2]!, LEFT, TOP + smallH + V_GAP, halfW, bigH),
        makeSlot(
            ids[3]!,
            LEFT + halfW + H_GAP,
            TOP + smallH + V_GAP,
            halfW,
            bigH,
        ),
    ];
}

function gen4EqualCols(ids: string[], m: LayoutMetrics): PhotoSlot[] {
    const { left: LEFT, top, cw: CW, ch: height, hGap: H_GAP } = m;
    const colW = (CW - H_GAP * 3) / 4;
    return [
        makeSlot(ids[0]!, LEFT, top, colW, height),
        makeSlot(ids[1]!, LEFT + colW + H_GAP, top, colW, height),
        makeSlot(ids[2]!, LEFT + (colW + H_GAP) * 2, top, colW, height),
        makeSlot(ids[3]!, LEFT + (colW + H_GAP) * 3, top, colW, height),
    ];
}

// ── Variant registry ──────────────────────────────────────────────

const ALL_VARIANTS: LayoutVariant[] = [
    // 1 photo
    { key: "1-padded", photoCount: 1, generate: gen1Padded },
    { key: "1-moderate", photoCount: 1, generate: gen1Moderate },
    { key: "1-full", photoCount: 1, generate: gen1Full },
    // 2 photos
    { key: "2-stacked", photoCount: 2, generate: gen2Stacked },
    { key: "2-side", photoCount: 2, generate: gen2SideBySide },
    { key: "2-big-top", photoCount: 2, generate: gen2BigTop },
    { key: "2-big-left", photoCount: 2, generate: gen2BigLeft },
    { key: "2-big-bottom", photoCount: 2, generate: gen2BigBottom },
    { key: "2-big-right", photoCount: 2, generate: gen2BigRight },
    // 3 photos
    { key: "3-top1-bot2", photoCount: 3, generate: gen3Top1Bot2 },
    { key: "3-left1-right2", photoCount: 3, generate: gen3Left1Right2 },
    { key: "3-bot1-top2", photoCount: 3, generate: gen3Bot1Top2 },
    { key: "3-right1-left2", photoCount: 3, generate: gen3Right1Left2 },
    { key: "3-dominant-top", photoCount: 3, generate: gen3DominantTop },
    { key: "3-dominant-bottom", photoCount: 3, generate: gen3DominantBottom },
    { key: "3-dominant-left", photoCount: 3, generate: gen3DominantLeft },
    { key: "3-dominant-right", photoCount: 3, generate: gen3DominantRight },
    { key: "3-equal-rows", photoCount: 3, generate: gen3EqualRows },
    { key: "3-equal-cols", photoCount: 3, generate: gen3EqualCols },
    // 4 photos
    { key: "4-grid", photoCount: 4, generate: gen4Grid },
    { key: "4-staggered", photoCount: 4, generate: gen4Staggered },
    {
        key: "4-staggered-reverse",
        photoCount: 4,
        generate: gen4StaggeredReverse,
    },
    { key: "4-top1-bot3", photoCount: 4, generate: gen4Top1Bot3 },
    { key: "4-bot1-top3", photoCount: 4, generate: gen4Bot1Top3 },
    { key: "4-left1-right3", photoCount: 4, generate: gen4Left1Right3 },
    { key: "4-right1-left3", photoCount: 4, generate: gen4Right1Left3 },
    { key: "4-wide-left", photoCount: 4, generate: gen4WideLeft },
    { key: "4-wide-right", photoCount: 4, generate: gen4WideRight },
    { key: "4-tall-top", photoCount: 4, generate: gen4TallTop },
    { key: "4-tall-bottom", photoCount: 4, generate: gen4TallBottom },
    { key: "4-equal-cols", photoCount: 4, generate: gen4EqualCols },
];

const VARIANT_MAP = new Map(ALL_VARIANTS.map((v) => [v.key, v]));

const MIRROR_MAP = new Map<string, string>([
    ["2-big-top", "2-big-bottom"],
    ["2-big-bottom", "2-big-top"],
    ["2-big-left", "2-big-right"],
    ["2-big-right", "2-big-left"],
    ["3-top1-bot2", "3-bot1-top2"],
    ["3-bot1-top2", "3-top1-bot2"],
    ["3-left1-right2", "3-right1-left2"],
    ["3-right1-left2", "3-left1-right2"],
    ["3-dominant-top", "3-dominant-bottom"],
    ["3-dominant-bottom", "3-dominant-top"],
    ["3-dominant-left", "3-dominant-right"],
    ["3-dominant-right", "3-dominant-left"],
    ["4-staggered", "4-staggered-reverse"],
    ["4-staggered-reverse", "4-staggered"],
    ["4-top1-bot3", "4-bot1-top3"],
    ["4-bot1-top3", "4-top1-bot3"],
    ["4-left1-right3", "4-right1-left3"],
    ["4-right1-left3", "4-left1-right3"],
    ["4-wide-left", "4-wide-right"],
    ["4-wide-right", "4-wide-left"],
    ["4-tall-top", "4-tall-bottom"],
    ["4-tall-bottom", "4-tall-top"],
]);

const HIDDEN_MIRRORS = new Set([
    "2-big-bottom",
    "2-big-right",
    "3-bot1-top2",
    "3-right1-left2",
    "3-dominant-bottom",
    "3-dominant-right",
    "4-staggered-reverse",
    "4-bot1-top3",
    "4-right1-left3",
    "4-wide-right",
    "4-tall-bottom",
]);

export function getMirrorVariant(key: string): string | undefined {
    return MIRROR_MAP.get(key);
}

export function getVariantsForCount(
    count: number,
    isFrontCover = false,
): LayoutVariant[] {
    return ALL_VARIANTS.filter(
        (v) =>
            v.photoCount === count &&
            !HIDDEN_MIRRORS.has(v.key) &&
            (isFrontCover || v.key !== "1-padded"),
    );
}

export function getCaptionZones(page: BookPage): {
    topPct: number;
    bottomPct: number;
} {
    if (page.slots.length === 0) {
        const metrics = getLayoutMetrics();
        return { topPct: metrics.marginV, bottomPct: metrics.marginV };
    }
    const topPct = Math.min(...page.slots.map((s) => s.y));
    const bottomPct = 100 - Math.max(...page.slots.map((s) => s.y + s.height));
    return { topPct, bottomPct };
}

export function getVariantPreview(key: string): SlotPosition[] {
    const variant = VARIANT_MAP.get(key);
    if (!variant) return [];
    const dummyIds = Array.from(
        { length: variant.photoCount },
        (_, i) => `d${i}`,
    );
    const slots = applyVariant(key, dummyIds);
    return slots.map((s) => ({
        x: s.x,
        y: s.y,
        width: s.width,
        height: s.height,
    }));
}

export function applyVariant(key: string, photoIds: string[]): PhotoSlot[] {
    const variant = VARIANT_MAP.get(key);
    if (!variant) return [];
    const metrics = getLayoutMetrics();
    return variant.generate(photoIds, metrics);
}

export function chooseBestVariantKey(photos: Photo[]): string {
    const count = photos.length;
    if (count <= 1) return "1-moderate";

    if (count === 2) {
        const o0 = getOrientation(photos[0]!);
        const o1 = getOrientation(photos[1]!);
        if (o0 === "landscape" && o1 === "landscape") return "2-stacked";
        return "2-side";
    }

    if (count === 3) {
        const o0 = getOrientation(photos[0]!);
        if (o0 === "landscape") return "3-top1-bot2";
        return "3-left1-right2";
    }

    const landscapes = photos.filter((p) => getOrientation(p) === "landscape");
    if (landscapes.length >= 1) return "4-top1-bot3";
    return "4-grid";
}

export function defaultVariantKeyForCount(count: number): string {
    if (count <= 1) return "1-moderate";
    if (count === 2) return "2-side";
    if (count === 3) return "3-left1-right2";
    return "4-grid";
}

export function chooseBestLayout(photos: Photo[]): PhotoSlot[] {
    if (photos.length === 0) return [];
    const variantKey = chooseBestVariantKey(photos);
    return applyVariant(
        variantKey,
        photos.map((p) => p.id),
    );
}

function layoutCropLoss(photos: Photo[]): number {
    const slots = chooseBestLayout(photos);
    return photos.reduce((loss, photo, index) => {
        const photoRatio = photo.width / photo.height;
        const slotRatio = slots[index]!.width / slots[index]!.height;
        return (
            loss + 1 - Math.min(photoRatio / slotRatio, slotRatio / photoRatio)
        );
    }, 0);
}

function groupInteriorPhotos(photos: Photo[]): Photo[][] {
    const groups: Photo[][] = [];
    const layoutCycle = [2, 3, 1, 4, 2, 3, 1, 2];
    let idx = 0;

    while (idx < photos.length) {
        const remaining = photos.length - idx;
        let count = Math.min(
            layoutCycle[groups.length % layoutCycle.length]!,
            remaining,
        );

        // Avoid a lone final photo in the initial grouping where possible.
        if (remaining - count === 1 && count < 4) {
            count = Math.min(count + 1, remaining, 4);
        }
        groups.push(photos.slice(idx, idx + count));
        idx += count;
    }

    if (groups.length % 2 !== 0) {
        // Split the last multi-photo group, keeping photo order and the rest of
        // the book intact. With only one interior photo, a blank is unavoidable.
        let groupIndex = groups.length - 1;
        while (groupIndex >= 0 && groups[groupIndex]!.length < 2) groupIndex--;
        if (groupIndex >= 0) {
            const group = groups[groupIndex]!;
            const splits = Array.from({ length: group.length - 1 }, (_, i) => {
                const left = group.slice(0, i + 1);
                const right = group.slice(i + 1);
                return {
                    left,
                    right,
                    loss: layoutCropLoss(left) + layoutCropLoss(right),
                };
            });
            splits.sort(
                (a, b) =>
                    a.loss - b.loss ||
                    Math.abs(a.left.length - a.right.length) -
                        Math.abs(b.left.length - b.right.length),
            );
            const best = splits[0]!;
            groups.splice(groupIndex, 1, best.left, best.right);
        }
    }

    return groups;
}

export function generateAutoLayout(photos: Photo[]): BookPage[] {
    // Sort by dateTaken
    const sorted = [...photos].sort((a, b) => a.dateTaken - b.dateTaken);

    const pages: BookPage[] = [];

    if (sorted.length === 0) return pages;

    // First page (cover) — single photo, always full-bleed.
    pages.push({
        id: crypto.randomUUID(),
        slots: applyVariant("1-full", [sorted[0]!.id]),
        layoutVariant: "1-full",
        textBlocks: [],
        topCaption: "",
        bottomCaption: "",
    });

    // All remaining photos belong to the interior, including the last photo.
    for (const pagePhotos of groupInteriorPhotos(sorted.slice(1))) {
        const variantKey = chooseBestVariantKey(pagePhotos);

        pages.push({
            id: crypto.randomUUID(),
            slots: applyVariant(
                variantKey,
                pagePhotos.map((photo) => photo.id),
            ),
            layoutVariant: variantKey,
            textBlocks: [],
            topCaption: "",
            bottomCaption: "",
        });
    }

    // Branding is rendered separately on the photo-free back cover.
    pages.push(makeBlankPage());
    return normalizeBookPages(pages);
}
