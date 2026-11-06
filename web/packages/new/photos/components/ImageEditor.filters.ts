type ColorMatrix = readonly number[];

const identity = [1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0];

const scale = (r: number, g: number, b: number, offset = 0): ColorMatrix => [
    r,
    0,
    0,
    0,
    offset,
    0,
    g,
    0,
    0,
    offset,
    0,
    0,
    b,
    0,
    offset,
    0,
    0,
    0,
    1,
    0,
];

const brightness = (value: number) => scale(1, 1, 1, value * 100);

const contrast = (value: number) => {
    const factor = (259 * (value * 255 + 255)) / (255 * (259 - value * 255));
    return scale(factor, factor, factor, 128 * (1 - factor));
};

const saturation = (value: number): ColorMatrix => {
    const x = 1 + (value > 0 ? 3 * value : value);
    const r = 0.3086 * (1 - x);
    const g = 0.6094 * (1 - x);
    const b = 0.082 * (1 - x);
    return [
        r + x,
        g,
        b,
        0,
        0,
        r,
        g + x,
        b,
        0,
        0,
        r,
        g,
        b + x,
        0,
        0,
        0,
        0,
        0,
        1,
        0,
    ];
};

const sepia = (v: number): ColorMatrix => [
    1 - 0.607 * v,
    0.769 * v,
    0.189 * v,
    0,
    0,
    0.349 * v,
    1 - 0.314 * v,
    0.168 * v,
    0,
    0,
    0.272 * v,
    0.534 * v,
    1 - 0.869 * v,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
];

const overlay = (
    r: number,
    g: number,
    b: number,
    amount: number,
): ColorMatrix => [
    1 - amount,
    0,
    0,
    0,
    -r * amount,
    0,
    1 - amount,
    0,
    0,
    -g * amount,
    0,
    0,
    1 - amount,
    0,
    -b * amount,
    0,
    0,
    0,
    1,
    0,
];

const combine = (matrices: ColorMatrix[]) =>
    matrices.reduce(
        (previous, next) =>
            Array.from({ length: 20 }, (_, i) => {
                const row = Math.floor(i / 5);
                const column = i % 5;
                let value = column === 4 ? next[row * 5 + 4]! : 0;
                for (let k = 0; k < 4; k++) {
                    value += next[row * 5 + k]! * previous[k * 5 + column]!;
                }
                return value;
            }),
        identity,
    );

const definitions: { name: string; matrices: ColorMatrix[] }[] = [
    { name: "None", matrices: [] },
    { name: "Pop", matrices: [saturation(0.3), brightness(0.15)] },
    { name: "Amber", matrices: [scale(1.01, 1.04, 1), saturation(0.3)] },
    { name: "Dust", matrices: [sepia(0.4), brightness(0.13), contrast(-0.05)] },
    {
        name: "Carbon",
        matrices: [
            contrast(0.2),
            [
                0.2126, 0.7152, 0.0722, 0, 0, 0.2126, 0.7152, 0.0722, 0, 0,
                0.2126, 0.7152, 0.0722, 0, 0, 0, 0, 0, 1, 0,
            ],
        ],
    },
    {
        name: "Glacier",
        matrices: [
            [
                0.97, 0.02, 0, 0, 0, 0.01, 0.98, 0, 0, 0, 0.01, 0.02, 0.96, 0,
                0, 0, 0, 0, 1, 0,
            ],
            scale(0.8, 1, 1),
            [
                1.01, 0.4, -0.41, 0, 0, -0.04, 0.91, 0.14, 0, 0, 0.38, -0.25,
                0.87, 0, 0, 0, 0, 0, 1, 0,
            ],
            scale(0.94, 0.94, 0.94, 7.07),
        ],
    },
    {
        name: "Haze",
        matrices: [overlay(228, 130, 225, 0.13), saturation(-0.2)],
    },
    { name: "Meadow", matrices: [scale(1.05, 1.1, 1)] },
    {
        name: "Zest",
        matrices: [brightness(0.1), contrast(0.1), saturation(0.15)],
    },
    { name: "Retro", matrices: [overlay(25, 240, 252, 0.05), sepia(0.3)] },
    { name: "Sepia", matrices: [contrast(-0.15), saturation(0.1)] },
];

export const editorFilterPresets = definitions.map(({ name, matrices }) => ({
    name,
    matrix: combine(matrices),
}));

export const applyEditorFilter = (
    pixels: Uint8ClampedArray,
    matrix: ColorMatrix,
) => {
    for (let i = 0; i < pixels.length; i += 4) {
        const r = pixels[i]!;
        const g = pixels[i + 1]!;
        const b = pixels[i + 2]!;
        const a = pixels[i + 3]!;
        pixels[i] =
            matrix[0]! * r +
            matrix[1]! * g +
            matrix[2]! * b +
            matrix[3]! * a +
            matrix[4]!;
        pixels[i + 1] =
            matrix[5]! * r +
            matrix[6]! * g +
            matrix[7]! * b +
            matrix[8]! * a +
            matrix[9]!;
        pixels[i + 2] =
            matrix[10]! * r +
            matrix[11]! * g +
            matrix[12]! * b +
            matrix[13]! * a +
            matrix[14]!;
    }
};
