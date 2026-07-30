/**
 * An image bitmap and its RGBA data.
 *
 * This is data structure containing data about an image in all formats that the
 * various indexing steps need.
 */
export interface ImageBitmapAndData {
    /**
     * An {@link ImageBitmap} from the original or converted image.
     *
     * This bitmap is constructed from the original file's data if the
     * browser knows how to handle it; otherwise we first convert it to a JPEG
     * and then create the bitmap from that.
     */
    bitmap: ImageBitmap;
    /**
     * The RGBA {@link ImageData} of the {@link bitmap}, obtained by rendering
     * it to an offscreen canvas.
     */
    data: ImageData;
}

/**
 * Create an {@link ImageBitmap} from the given {@link imageBlob}, and return
 * both the image bitmap and its {@link ImageData}.
 *
 * @param maxPixels If specified, reject if the decoded image has more pixels
 * than this limit. The check happens before obtaining the image's data, which
 * would've required allocations proportional to the image size.
 */
export const createImageBitmapAndData = async (
    imageBlob: Blob,
    maxPixels?: number,
): Promise<ImageBitmapAndData> => {
    const imageBitmap = await createImageBitmap(imageBlob);

    const { width, height } = imageBitmap;

    if (maxPixels && width * height > maxPixels) {
        imageBitmap.close();
        throw new Error(`Image too large (${width}x${height})`);
    }

    // Use an OffscreenCanvas to get the bitmap's data.
    const offscreenCanvas = new OffscreenCanvas(width, height);
    const ctx = offscreenCanvas.getContext("2d")!;
    ctx.drawImage(imageBitmap, 0, 0, width, height);
    const imageData = ctx.getImageData(0, 0, width, height);

    return { bitmap: imageBitmap, data: imageData };
};
