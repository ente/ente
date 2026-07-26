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

    // A crop rectangle sharing the original aspect ratio, centered at the
    // origin, has half-width a and half-height a*(height/width). Rotating
    // its corners by -angleDegrees into the original (unrotated) rectangle's
    // frame gives two constraints on how large a can be before a corner
    // pokes outside the original width/height bounds:
    //   a*cosT + a*(height/width)*sinT <= width/2   (stay within width)
    //   a*sinT + a*(height/width)*cosT <= height/2  (stay within height)
    // Solving each for the maximum a, and taking the tighter (smaller) one,
    // gives the largest inscribed rectangle. This also guarantees the result
    // keeps the original aspect ratio, since both bounds were derived from a
    // crop rectangle whose height was defined as a*(height/width) already.
    const maxAFromWidthBound =
        (width * width) / (2 * (width * cosT + height * sinT));
    const maxAFromHeightBound =
        (width * height) / (2 * (width * sinT + height * cosT));
    const a = Math.min(maxAFromWidthBound, maxAFromHeightBound);

    const cropW = 2 * a;
    const cropH = cropW * (height / width);
    return { width: cropW, height: cropH };
};
