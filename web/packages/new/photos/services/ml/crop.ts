import { blobCache } from "ente-base/blob-cache";
import type { EnteFile } from "ente-media/file";
import { fetchRenderableEnteFileBlob } from "./blob";
import type { Box, FaceIndex } from "./face";
import { clamp } from "./math";

/**
 * Regenerate and locally save face crops for faces in the given file.
 *
 * Face crops (the rectangular regions of the original image where a particular
 * face was detected) are not stored on remote and are generated on demand. On
 * the client where the indexing occurred, they get generated during the face
 * indexing pipeline itself. But we need to regenerate them locally if the user
 * views that item on any other client.
 *
 * @param file The {@link EnteFile} whose face crops we want to generate.
 *
 * @param faceIndex The {@link FaceIndex} containing information about the faces
 * detected in the given image.
 *
 * The generated face crops are saved in a local cache and can subsequently be
 * retrieved from the {@link BlobCache} named "face-crops".
 */
export const regenerateFaceCrops = async (
    file: EnteFile,
    faceIndex: FaceIndex,
) => {
    const renderableBlob = await fetchRenderableEnteFileBlob(file);
    const imageBitmap = await createImageBitmap(renderableBlob);

    try {
        await saveFaceCrops(imageBitmap, faceIndex);
    } finally {
        imageBitmap.close();
    }
};

/**
 * Extract and locally save the face crops (the rectangle of the original image
 * that contain the detected face) for each of the faces detected in an image.
 *
 * @param imageBitmap The original image.
 *
 * @param faceIndex The {@link FaceIndex} containing information about the faces
 * detected in the given image.
 *
 * The face crops are saved in a local cache and can subsequently be retrieved
 * from the {@link BlobCache} named "face-crops".
 */
export const saveFaceCrops = async (
    imageBitmap: ImageBitmap,
    faceIndex: FaceIndex,
) => {
    const cache = await blobCache("face-crops");

    return Promise.all(
        faceIndex.faces.map(({ faceID, detection }) =>
            extractFaceCrop(imageBitmap, detection.box).then((b) =>
                cache.put(faceID, b),
            ),
        ),
    );
};

/**
 * Return the face crops corresponding to each of the given face detections.
 *
 * @param imageBitmap The original image.
 *
 * @param faceBox A box (a rectangle relative to the image size) marking the
 * bounds of face in the given image.
 *
 * @returns a JPEG blob.
 */
export const extractFaceCrop = (imageBitmap: ImageBitmap, faceBox: Box) => {
    const { width: imageWidth, height: imageHeight } = imageBitmap;

    // The faceBox coordinates are normalized 0-1 relative to the image size,
    // and we need to convert them back to absolute values first.
    const faceX = faceBox.x * imageWidth;
    const faceY = faceBox.y * imageHeight;
    const faceWidth = faceBox.width * imageWidth;
    const faceHeight = faceBox.height * imageHeight;

    // Calculate the crop values by adding some padding around the face and
    // making sure it's centered.
    const regularPadding = 0.4;
    const minimumPadding = 0.1;
    const xCrop = faceX - faceWidth * regularPadding;
    const xOvershoot = Math.abs(Math.min(0, xCrop)) / faceWidth;
    const widthCrop =
        faceWidth * (1 + 2 * regularPadding) -
        2 * Math.min(xOvershoot, regularPadding - minimumPadding) * faceWidth;

    const yCrop = faceY - faceHeight * regularPadding;
    const yOvershoot = Math.abs(Math.min(0, yCrop)) / faceHeight;
    const heightCrop =
        faceHeight * (1 + 2 * regularPadding) -
        2 * Math.min(yOvershoot, regularPadding - minimumPadding) * faceHeight;

    // Prevent the crop from going out of image bounds.
    const x = clamp(xCrop, 0, imageWidth);
    const y = clamp(yCrop, 0, imageHeight);
    const width = clamp(widthCrop, 0, imageWidth - x);
    const height = clamp(heightCrop, 0, imageHeight - y);

    const canvas = new OffscreenCanvas(width, height);
    const ctx = canvas.getContext("2d")!;
    ctx.imageSmoothingQuality = "high";

    ctx.drawImage(imageBitmap, x, y, width, height, 0, 0, width, height);

    return canvas.convertToBlob({ type: "image/jpeg", quality: 0.8 });
};
