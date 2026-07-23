const probeWidth = 2;
const probeHeight = 2;

const expectedProbeData = Uint8ClampedArray.from([
    17, 83, 149, 255, 203, 29, 101, 255, 67, 131, 197, 255, 239, 53, 11, 255,
]);

const hasSamePixels = (
    lhs: Uint8ClampedArray,
    rhs: Uint8ClampedArray,
): boolean => {
    if (lhs.length !== rhs.length) return false;
    for (let i = 0; i < lhs.length; i++) {
        if (lhs[i] !== rhs[i]) return false;
    }
    return true;
};

export const hasReliableCanvasReadback = (): boolean => {
    try {
        const canvas = document.createElement("canvas");
        canvas.width = probeWidth;
        canvas.height = probeHeight;

        const ctx = canvas.getContext("2d", { willReadFrequently: true });
        if (!ctx) return false;

        const probeImageData = new ImageData(
            new Uint8ClampedArray(expectedProbeData),
            probeWidth,
            probeHeight,
        );
        ctx.putImageData(probeImageData, 0, 0);

        const firstReadback = ctx.getImageData(
            0,
            0,
            probeWidth,
            probeHeight,
        ).data;
        if (!hasSamePixels(firstReadback, expectedProbeData)) return false;

        const secondReadback = ctx.getImageData(
            0,
            0,
            probeWidth,
            probeHeight,
        ).data;

        return hasSamePixels(firstReadback, secondReadback);
    } catch {
        return false;
    }
};
