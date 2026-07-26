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

/**
 * Rotate the contents of `canvas` by `angle` degrees around its center,
 * resizing the canvas to the new rotated bounding box. Resolves once the
 * rotated pixels have actually been drawn — callers that need to read the
 * canvas's post-rotation dimensions (e.g. to crop it next) must await this
 * before doing so.
 */
export const rotateCanvas = (
    canvas: HTMLCanvasElement,
    angle: number,
): Promise<void> => {
    const context = canvas.getContext("2d");
    if (!context) return Promise.resolve();
    context.imageSmoothingEnabled = false;

    const image = new Image();

    return new Promise((resolve, reject) => {
        // onload must be attached before src is set: some environments
        // (e.g. server-side canvas implementations used in tests) decode
        // already-available image data synchronously during assignment.
        image.onload = () => {
            try {
                context.clearRect(0, 0, canvas.width, canvas.height);

                context.save();

                const radians = (angle * Math.PI) / 180;
                const sin = Math.sin(radians);
                const cos = Math.cos(radians);
                const newWidth =
                    Math.abs(image.width * cos) + Math.abs(image.height * sin);
                const newHeight =
                    Math.abs(image.width * sin) + Math.abs(image.height * cos);

                canvas.width = newWidth;
                canvas.height = newHeight;

                context.translate(canvas.width / 2, canvas.height / 2);
                context.rotate(radians);

                context.drawImage(
                    image,
                    -image.width / 2,
                    -image.height / 2,
                    image.width,
                    image.height,
                );

                context.restore();
                resolve();
            } catch (e) {
                reject(e instanceof Error ? e : new Error(String(e)));
            }
        };
        image.onerror = () =>
            reject(new Error("Failed to load canvas image data for rotate"));
        image.src = canvas.toDataURL();
    });
};

/**
 * Crop `canvas` to the region between (topLeftX, topLeftY) and
 * (bottomRightX, bottomRightY) (in the canvas's current coordinate space,
 * scaled by `scale`), resizing the canvas to the cropped region's size.
 * Resolves once the cropped pixels have actually been drawn.
 */
export const cropRegionOfCanvas = (
    canvas: HTMLCanvasElement,
    topLeftX: number,
    topLeftY: number,
    bottomRightX: number,
    bottomRightY: number,
    scale = 1,
): Promise<void> => {
    const context = canvas.getContext("2d");
    if (!context) return Promise.resolve();
    context.imageSmoothingEnabled = false;

    const width = (bottomRightX - topLeftX) * scale;
    const height = (bottomRightY - topLeftY) * scale;

    const img = new Image();
    return new Promise((resolve, reject) => {
        img.onload = () => {
            try {
                context.clearRect(0, 0, canvas.width, canvas.height);

                canvas.width = width;
                canvas.height = height;

                context.drawImage(
                    img,
                    topLeftX,
                    topLeftY,
                    width,
                    height,
                    0,
                    0,
                    width,
                    height,
                );
                resolve();
            } catch (e) {
                reject(e instanceof Error ? e : new Error(String(e)));
            }
        };
        img.onerror = () =>
            reject(new Error("Failed to load canvas image data for crop"));
        img.src = canvas.toDataURL();
    });
};
