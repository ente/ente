type LottiePoint = [number, number];

interface LottieShapePath {
    c: boolean;
    i: LottiePoint[];
    o: LottiePoint[];
    v: LottiePoint[];
}

export interface ParsedArrowPath {
    color: string;
    d: string;
    lineCap: "butt" | "round" | "square";
    lineJoin: "miter" | "round" | "bevel";
    name: string;
    strokeScale: number;
    width: number;
}

export interface ParsedArrow {
    height: number;
    paths: ParsedArrowPath[];
    transform: string;
    width: number;
}

const isRecord = (value: unknown): value is Record<string, unknown> =>
    typeof value === "object" && value !== null;

const toRecordArray = (
    value: unknown,
): Record<string, unknown>[] | undefined => {
    if (!Array.isArray(value)) return undefined;

    const records: Record<string, unknown>[] = [];
    for (const item of value) {
        if (isRecord(item)) records.push(item);
    }

    return records;
};

const toNumber = (value: unknown, fallback: number) =>
    typeof value === "number" ? value : fallback;

const toNumberArray = (value: unknown): number[] | undefined =>
    Array.isArray(value) && value.every((item) => typeof item === "number")
        ? value
        : undefined;

const toNestedRecord = (
    object: Record<string, unknown>,
    key: string,
): Record<string, unknown> | undefined => {
    const value = object[key];
    return isRecord(value) ? value : undefined;
};

const toPoint = (value: unknown): LottiePoint | null => {
    if (!Array.isArray(value)) return null;

    const coordinates = value as unknown[];
    const x = coordinates[0];
    const y = coordinates[1];
    if (typeof x !== "number" || typeof y !== "number") return null;

    return [x, y];
};

const toPoints = (value: unknown): LottiePoint[] | null => {
    if (!Array.isArray(value)) return null;

    const points: LottiePoint[] = [];
    for (const item of value) {
        const point = toPoint(item);
        if (!point) return null;
        points.push(point);
    }

    return points;
};

const toShapePath = (value: unknown): LottieShapePath | null => {
    if (!isRecord(value)) return null;

    const i = toPoints(value.i);
    const o = toPoints(value.o);
    const v = toPoints(value.v);
    if (!i || !o || !v) return null;

    return { c: value.c === true, i, o, v };
};

const safePoint = (point?: LottiePoint): [number, number] => [
    point?.[0] ?? 0,
    point?.[1] ?? 0,
];

const toPathD = (shape: LottieShapePath) => {
    if (!shape.v.length) return "";

    const { c, i, o, v } = shape;
    const [startX, startY] = safePoint(v[0]);
    let d = `M ${startX} ${startY}`;

    for (let idx = 1; idx < v.length; idx++) {
        const [prevX, prevY] = safePoint(v[idx - 1]);
        const [currX, currY] = safePoint(v[idx]);
        const [prevOutX, prevOutY] = safePoint(o[idx - 1]);
        const [currInX, currInY] = safePoint(i[idx]);
        const hasCurve =
            prevOutX !== 0 || prevOutY !== 0 || currInX !== 0 || currInY !== 0;

        if (hasCurve) {
            d += ` C ${prevX + prevOutX} ${prevY + prevOutY} ${
                currX + currInX
            } ${currY + currInY} ${currX} ${currY}`;
        } else {
            d += ` L ${currX} ${currY}`;
        }
    }

    if (c) {
        const lastIdx = v.length - 1;
        const [prevX, prevY] = safePoint(v[lastIdx]);
        const [currX, currY] = safePoint(v[0]);
        const [prevOutX, prevOutY] = safePoint(o[lastIdx]);
        const [currInX, currInY] = safePoint(i[0]);
        const hasCurve =
            prevOutX !== 0 || prevOutY !== 0 || currInX !== 0 || currInY !== 0;

        if (hasCurve) {
            d += ` C ${prevX + prevOutX} ${prevY + prevOutY} ${
                currX + currInX
            } ${currY + currInY} ${currX} ${currY}`;
        } else {
            d += ` L ${currX} ${currY}`;
        }
        d += " Z";
    }

    return d;
};

const toLineCap = (value: number): ParsedArrowPath["lineCap"] =>
    value === 2 ? "round" : value === 3 ? "square" : "butt";

const toLineJoin = (value: number): ParsedArrowPath["lineJoin"] =>
    value === 2 ? "round" : value === 3 ? "bevel" : "miter";

const toRGB = (rgb: readonly number[]) => {
    const r = rgb[0] ?? 1;
    const g = rgb[1] ?? 1;
    const b = rgb[2] ?? 1;
    return `rgb(${Math.round(r * 255)} ${Math.round(g * 255)} ${Math.round(b * 255)})`;
};

export const parseArrowLottie = (lottie: unknown): ParsedArrow | null => {
    if (!isRecord(lottie)) return null;

    const layers = toRecordArray(lottie.layers);
    const layer = layers?.[0];
    if (!layer) return null;

    const groups = toRecordArray(layer.shapes);
    if (!groups?.length) return null;

    const ks = toNestedRecord(layer, "ks");
    const scaleValues = ks
        ? toNumberArray(toNestedRecord(ks, "s")?.k)
        : undefined;
    const positionValues = ks
        ? toNumberArray(toNestedRecord(ks, "p")?.k)
        : undefined;

    const sx = toNumber(scaleValues?.[0], 100) / 100;
    const sy = toNumber(scaleValues?.[1], scaleValues?.[0] ?? 100) / 100;
    const px = toNumber(positionValues?.[0], 0) || 0;
    const py = toNumber(positionValues?.[1], 0) || 0;

    const paths: ParsedArrowPath[] = [];
    for (const group of groups) {
        if (group.ty !== "gr") continue;

        const items = toRecordArray(group.it);
        if (!items) continue;

        const shapeItem = items.find((item) => item.ty === "sh");
        const stroke = items.find((item) => item.ty === "st");

        const shape = shapeItem
            ? toShapePath(toNestedRecord(shapeItem, "ks")?.k)
            : null;
        if (!shape || !stroke) continue;

        const groupName = typeof group.nm === "string" ? group.nm : "";
        const d = toPathD(shape);
        if (!d) continue;

        const strokeColor = toNumberArray(toNestedRecord(stroke, "c")?.k) ?? [
            1, 1, 1,
        ];
        const strokeWidth = toNumber(toNestedRecord(stroke, "w")?.k, 2);

        paths.push({
            color: toRGB(strokeColor),
            d,
            lineCap: toLineCap(toNumber(stroke.lc, 1)),
            lineJoin: toLineJoin(toNumber(stroke.lj, 1)),
            name: groupName,
            strokeScale: 0.58,
            width: strokeWidth,
        });
    }

    if (!paths.length) return null;

    return {
        height: toNumber(lottie.h, 84) || 84,
        paths,
        transform: `translate(${px} ${py}) scale(${sx} ${sy})`,
        width: toNumber(lottie.w, 150) || 150,
    };
};
