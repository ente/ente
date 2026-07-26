/**
 * Compute the largest axis-aligned rectangle, sharing the aspect ratio of a
 * `width` x `height` canvas, that fits entirely within that canvas after it
 * has been rotated by `angleDegrees` around its center.
 *
 * This is the "inscribed rectangle" used to auto-crop a straightened photo
 * so no empty corners remain: rotating a rectangle by a non-90° angle leaves
 * its corners outside any axis-aligned frame, so the only way to end up with
 * a clean rectangular result is to shrink inward to the largest rectangle
 * that still lies fully within the rotated bounds.
 */
export const computeInscribedCrop = (
    width: number,
    height: number,
    angleDegrees: number,
): { width: number; height: number } => {
    const radians = (angleDegrees * Math.PI) / 180;
    const sinT = Math.abs(Math.sin(radians));
    const cosT = Math.abs(Math.cos(radians));

    if (sinT === 0) return { width, height };

    const wide = Math.min(width, height);
    const long = Math.max(width, height);

    if (wide <= 2 * sinT * cosT * long) {
        const x = wide / 2;
        const cropW = x / sinT;
        const cropH = x / cosT;
        return width <= height
            ? { width: cropW, height: cropH }
            : { width: cropH, height: cropW };
    }

    const d = cosT * cosT - sinT * sinT;
    const cropW = (width * cosT - height * sinT) / d;
    const cropH = (height * cosT - width * sinT) / d;
    return { width: cropW, height: cropH };
};
