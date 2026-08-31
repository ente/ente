import { lowercaseExtension, nameAndExtension } from "ente-base/file-name";
import { isHEICExtension } from "ente-media/formats";
import { heicToJPEG } from "ente-media/heic-convert";
import { thumbHashBase64FromCanvas } from "utils/thumbhash";

export interface PreparedSpaceImage {
    file: File;
    height: number;
    width: number;
}

export type PreparedSpaceAvatarImage = PreparedSpaceImage;
export type PreparedSpaceCoverImage = PreparedSpaceImage;
export interface PreparedSpacePostImage extends PreparedSpaceImage {
    thumbHash: string;
}

export interface SpaceAvatarCropImage {
    url: string;
}

export interface SpacePostPreviewImage {
    height: number;
    url: string;
    width: number;
}

export interface SpaceImageCropArea {
    height: number;
    width: number;
    x: number;
    y: number;
}

export const spaceAvatarImageInputAccept =
    "image/jpeg,image/png,image/webp,image/heic,image/heif,.jpg,.jpeg,.png,.webp,.heic,.heif";
export const spaceCoverImageInputAccept = spaceAvatarImageInputAccept;
export const spacePostImageInputAccept =
    "image/jpeg,image/png,image/webp,image/heic,image/heif,.jpg,.jpeg,.png,.webp,.heic,.heif";

export const spaceDefaultCoverImagePath = "/images/default-cover-image.jpg";
export const spaceProfileCoverAspectRatio = 39 / 17;
const spaceAvatarImageMaxEdge = 512;
const spaceCoverImageMaxWidth = 1170;
const spacePostImageMaxLongEdge = 1600;
const spacePostImageWebPQuality = 0.82;
const spacePostImageMimeType = "image/webp";
const spaceAssetEncryptionOverheadBytes = 42;
const spaceAvatarUploadMaxBytes = 2 * 1024 * 1024;
const spaceCoverUploadMaxBytes = 2 * 1024 * 1024;
const spacePostUploadMaxBytes = 5 * 1024 * 1024;

export const maxSpaceAvatarImageBytes =
    spaceAvatarUploadMaxBytes - spaceAssetEncryptionOverheadBytes;
export const maxSpaceCoverImageBytes =
    spaceCoverUploadMaxBytes - spaceAssetEncryptionOverheadBytes;
export const maxSpacePostImageBytes =
    spacePostUploadMaxBytes - spaceAssetEncryptionOverheadBytes;
export const spaceAvatarImageMaxSizeMessage =
    "This photo is too large. Try a smaller one.";
export const spaceCoverImageMaxSizeMessage = spaceAvatarImageMaxSizeMessage;
export const spacePostImageMaxSizeMessage =
    "This photo is too large. Try a smaller one.";
const unsupportedSpaceImageMessage = "Only photos can be uploaded.";
const supportedSpaceImageMimeTypes = new Set([
    "image/jpeg",
    "image/jpg",
    "image/png",
    "image/webp",
    "image/heic",
    "image/heif",
]);
const supportedSpaceImageExtensions = new Set([
    "jpg",
    "jpeg",
    "png",
    "webp",
    "heic",
    "heif",
]);

export const prepareSpacePostImage = async (
    file: File,
): Promise<PreparedSpacePostImage> => {
    const renderableBlob = await renderableBlobForSpaceImage(file);
    const { blob, height, thumbHash, width } = await webPBlobFromImage(
        renderableBlob,
        postCanvasPlan,
        true,
    );
    assertSpaceImageSize(
        blob,
        maxSpacePostImageBytes,
        spacePostImageMaxSizeMessage,
    );

    return {
        file: new File([blob], webPFileName(file.name), {
            lastModified: file.lastModified || Date.now(),
            type: spacePostImageMimeType,
        }),
        height,
        thumbHash,
        width,
    };
};

export const prepareSpacePostImageFromEdit = async (
    file: File,
    cropArea?: SpaceImageCropArea,
    rotationDegrees = 0,
): Promise<PreparedSpacePostImage> => {
    const normalizedRotationDegrees =
        normalizeSpaceImageRotation(rotationDegrees);
    if (!cropArea && normalizedRotationDegrees == 0) {
        return await prepareSpacePostImage(file);
    }

    const renderableBlob = await renderableBlobForSpaceImage(file);
    const { blob, height, thumbHash, width } = await webPBlobFromEditedImage(
        renderableBlob,
        cropArea,
        normalizedRotationDegrees,
    );
    assertSpaceImageSize(
        blob,
        maxSpacePostImageBytes,
        spacePostImageMaxSizeMessage,
    );

    return {
        file: new File([blob], webPFileName(file.name), {
            lastModified: file.lastModified || Date.now(),
            type: spacePostImageMimeType,
        }),
        height,
        thumbHash,
        width,
    };
};

export const canPreviewSpaceImageFile = (file: File) => {
    try {
        assertSupportedSpaceImageFile(file);
    } catch {
        return false;
    }

    return !isHEICSpaceImageFile(file);
};

export const spacePostPreviewImageForFile = async (
    file: File,
): Promise<SpacePostPreviewImage> => {
    const renderableBlob = await renderableBlobForSpaceImage(file);
    const imageURL = URL.createObjectURL(renderableBlob);

    try {
        const image = await loadImage(imageURL);
        return {
            height: image.naturalHeight,
            url: imageURL,
            width: image.naturalWidth,
        };
    } catch (error) {
        URL.revokeObjectURL(imageURL);
        throw error;
    }
};

export const prepareSpaceAvatarImage = async (
    file: File,
): Promise<PreparedSpaceAvatarImage> => {
    const renderableBlob = await renderableBlobForSpaceImage(file);
    const { blob, height, width } = await webPBlobFromImage(
        renderableBlob,
        avatarCanvasPlan,
    );
    assertSpaceImageSize(
        blob,
        maxSpaceAvatarImageBytes,
        spaceAvatarImageMaxSizeMessage,
    );

    return {
        file: new File([blob], webPFileName(file.name), {
            lastModified: file.lastModified || Date.now(),
            type: spacePostImageMimeType,
        }),
        height,
        width,
    };
};

export const spaceAvatarCropImageForFile = async (
    file: File,
): Promise<SpaceAvatarCropImage> => {
    const renderableBlob = await renderableBlobForSpaceImage(file);
    const imageURL = URL.createObjectURL(renderableBlob);

    try {
        await loadImage(imageURL);
        return { url: imageURL };
    } catch (error) {
        URL.revokeObjectURL(imageURL);
        throw error;
    }
};

export const spaceCoverCropImageForFile = spaceAvatarCropImageForFile;

export const prepareSpaceAvatarImageFromCrop = async (
    file: File,
    imageURL: string,
    cropArea: SpaceImageCropArea,
): Promise<PreparedSpaceAvatarImage> => {
    const { blob, height, width } = await webPBlobFromImage(
        imageURL,
        (width, height) => avatarCanvasPlanForCrop(width, height, cropArea),
        false,
        false,
    );
    assertSpaceImageSize(
        blob,
        maxSpaceAvatarImageBytes,
        spaceAvatarImageMaxSizeMessage,
    );

    return {
        file: new File([blob], webPFileName(file.name), {
            lastModified: file.lastModified || Date.now(),
            type: spacePostImageMimeType,
        }),
        height,
        width,
    };
};

export const prepareSpaceCoverImageFromCrop = async (
    file: File,
    imageURL: string,
    cropArea: SpaceImageCropArea,
): Promise<PreparedSpaceCoverImage> => {
    const { blob, height, width } = await webPBlobFromImage(
        imageURL,
        (width, height) => coverCanvasPlanForCrop(width, height, cropArea),
        false,
        false,
    );
    assertSpaceImageSize(
        blob,
        maxSpaceCoverImageBytes,
        spaceCoverImageMaxSizeMessage,
    );

    return {
        file: new File([blob], webPFileName(file.name), {
            lastModified: file.lastModified || Date.now(),
            type: spacePostImageMimeType,
        }),
        height,
        width,
    };
};

export const spacePostImageErrorMessage = (error: unknown) =>
    error instanceof SpaceImageSizeError || error instanceof SpaceImageTypeError
        ? error.message
        : "Choose a JPEG, PNG, WebP, HEIC, or HEIF image.";

export const spaceAvatarImageErrorMessage = (error: unknown) =>
    error instanceof SpaceImageSizeError || error instanceof SpaceImageTypeError
        ? error.message
        : "Choose a JPEG, PNG, WebP, HEIC, or HEIF image.";

export const spaceCoverImageErrorMessage = spaceAvatarImageErrorMessage;

const renderableBlobForSpaceImage = async (file: File): Promise<Blob> => {
    assertSupportedSpaceImageFile(file);

    return isHEICSpaceImageFile(file) ? await heicToJPEG(file) : file;
};

const isHEICSpaceImageFile = (file: File) => {
    const extension = lowercaseExtension(file.name);
    const mediaType = file.type.toLowerCase();
    return (
        (extension != undefined && isHEICExtension(extension)) ||
        mediaType == "image/heic" ||
        mediaType == "image/heif"
    );
};

class SpaceImageSizeError extends Error {
    constructor(message: string) {
        super(message);
        this.name = "SpaceImageSizeError";
    }
}

class SpaceImageTypeError extends Error {
    constructor(message: string) {
        super(message);
        this.name = "SpaceImageTypeError";
    }
}

const assertSupportedSpaceImageFile = (file: File) => {
    const extension = lowercaseExtension(file.name);
    const mediaType = file.type.trim().toLowerCase();
    if (supportedSpaceImageMimeTypes.has(mediaType)) return;
    if (
        (mediaType == "" || mediaType == "application/octet-stream") &&
        extension != undefined &&
        supportedSpaceImageExtensions.has(extension)
    ) {
        return;
    }

    throw new SpaceImageTypeError(unsupportedSpaceImageMessage);
};

const assertSpaceImageSize = (
    blob: Blob,
    maxBytes: number,
    message: string,
) => {
    if (blob.size > maxBytes) throw new SpaceImageSizeError(message);
};

interface CanvasPlan {
    height: number;
    sourceHeight: number;
    sourceWidth: number;
    sourceX: number;
    sourceY: number;
    width: number;
}

const webPBlobFromImage = async (
    imageSource: Blob | string,
    planForSource: (width: number, height: number) => CanvasPlan,
    includeThumbHash = false,
    revokeImageURL = true,
): Promise<{
    blob: Blob;
    height: number;
    thumbHash: string;
    width: number;
}> => {
    const imageURL =
        typeof imageSource == "string"
            ? imageSource
            : URL.createObjectURL(imageSource);
    try {
        const image = await loadImage(imageURL);
        const plan = planForSource(
            image.naturalWidth || image.width,
            image.naturalHeight || image.height,
        );
        if (plan.width <= 0 || plan.height <= 0) {
            throw new Error("Invalid image dimensions");
        }

        const canvas = document.createElement("canvas");
        canvas.width = plan.width;
        canvas.height = plan.height;

        const context = canvas.getContext("2d");
        if (!context) throw new Error("Could not create image canvas");

        context.drawImage(
            image,
            plan.sourceX,
            plan.sourceY,
            plan.sourceWidth,
            plan.sourceHeight,
            0,
            0,
            plan.width,
            plan.height,
        );

        const result = {
            blob: await canvasToBlob(canvas, spacePostImageMimeType),
            height: plan.height,
            thumbHash: "",
            width: plan.width,
        };
        if (includeThumbHash) {
            result.thumbHash = thumbHashBase64FromCanvas(canvas);
        }
        return result;
    } finally {
        if (revokeImageURL) URL.revokeObjectURL(imageURL);
    }
};

const webPBlobFromEditedImage = async (
    imageSource: Blob | string,
    cropArea: SpaceImageCropArea | undefined,
    rotationDegrees: number,
): Promise<{
    blob: Blob;
    height: number;
    thumbHash: string;
    width: number;
}> => {
    const imageURL =
        typeof imageSource == "string"
            ? imageSource
            : URL.createObjectURL(imageSource);
    try {
        const image = await loadImage(imageURL);
        const sourceWidth = image.naturalWidth || image.width;
        const sourceHeight = image.naturalHeight || image.height;
        if (sourceWidth <= 0 || sourceHeight <= 0) {
            throw new Error("Invalid image dimensions");
        }

        const rotatedCanvas = rotatedImageCanvas(
            image,
            sourceWidth,
            sourceHeight,
            rotationDegrees,
        );
        const sourceCanvas = cropArea
            ? croppedImageCanvas(rotatedCanvas, cropArea)
            : rotatedCanvas;
        const dimensions = scaledDimensions(
            sourceCanvas.width,
            sourceCanvas.height,
            spacePostImageMaxLongEdge,
        );
        if (dimensions.width <= 0 || dimensions.height <= 0) {
            throw new Error("Invalid image dimensions");
        }

        const canvas = document.createElement("canvas");
        canvas.width = dimensions.width;
        canvas.height = dimensions.height;

        const context = canvas.getContext("2d");
        if (!context) throw new Error("Could not create image canvas");

        context.drawImage(
            sourceCanvas,
            0,
            0,
            sourceCanvas.width,
            sourceCanvas.height,
            0,
            0,
            dimensions.width,
            dimensions.height,
        );

        return {
            blob: await canvasToBlob(canvas, spacePostImageMimeType),
            height: dimensions.height,
            thumbHash: thumbHashBase64FromCanvas(canvas),
            width: dimensions.width,
        };
    } finally {
        if (typeof imageSource != "string") URL.revokeObjectURL(imageURL);
    }
};

const loadImage = async (imageURL: string) =>
    await new Promise<HTMLImageElement>((resolve, reject) => {
        const image = new Image();
        image.decoding = "async";
        image.onload = () => resolve(image);
        image.onerror = () => reject(new Error("Could not decode image"));
        image.src = imageURL;
    });

const rotatedImageCanvas = (
    image: HTMLImageElement,
    width: number,
    height: number,
    rotationDegrees: number,
) => {
    const rotationRadians = (rotationDegrees * Math.PI) / 180;
    const rotatedWidth = Math.round(
        Math.abs(width * Math.cos(rotationRadians)) +
            Math.abs(height * Math.sin(rotationRadians)),
    );
    const rotatedHeight = Math.round(
        Math.abs(width * Math.sin(rotationRadians)) +
            Math.abs(height * Math.cos(rotationRadians)),
    );
    const canvas = document.createElement("canvas");
    canvas.width = rotatedWidth;
    canvas.height = rotatedHeight;

    const context = canvas.getContext("2d");
    if (!context) throw new Error("Could not create image canvas");

    context.translate(rotatedWidth / 2, rotatedHeight / 2);
    context.rotate(rotationRadians);
    context.drawImage(image, -width / 2, -height / 2, width, height);
    return canvas;
};

const croppedImageCanvas = (
    sourceCanvas: HTMLCanvasElement,
    cropArea: SpaceImageCropArea,
) => {
    const sourceWidth = Math.min(
        Math.max(1, Math.round(cropArea.width)),
        sourceCanvas.width,
    );
    const sourceHeight = Math.min(
        Math.max(1, Math.round(cropArea.height)),
        sourceCanvas.height,
    );
    const sourceX = clampNumber(
        Math.round(cropArea.x),
        0,
        Math.max(0, sourceCanvas.width - sourceWidth),
    );
    const sourceY = clampNumber(
        Math.round(cropArea.y),
        0,
        Math.max(0, sourceCanvas.height - sourceHeight),
    );
    const canvas = document.createElement("canvas");
    canvas.width = sourceWidth;
    canvas.height = sourceHeight;

    const context = canvas.getContext("2d");
    if (!context) throw new Error("Could not create image canvas");

    context.drawImage(
        sourceCanvas,
        sourceX,
        sourceY,
        sourceWidth,
        sourceHeight,
        0,
        0,
        sourceWidth,
        sourceHeight,
    );
    return canvas;
};

const postCanvasPlan = (width: number, height: number): CanvasPlan => {
    const dimensions = scaledDimensions(
        width,
        height,
        spacePostImageMaxLongEdge,
    );
    return {
        ...dimensions,
        sourceHeight: height,
        sourceWidth: width,
        sourceX: 0,
        sourceY: 0,
    };
};

const avatarCanvasPlan = (width: number, height: number): CanvasPlan => {
    if (width <= 0 || height <= 0) {
        return {
            height: 0,
            sourceHeight: 0,
            sourceWidth: 0,
            sourceX: 0,
            sourceY: 0,
            width: 0,
        };
    }

    const sourceEdge = Math.min(width, height);
    const outputEdge = Math.min(sourceEdge, spaceAvatarImageMaxEdge);
    return {
        height: outputEdge,
        sourceHeight: sourceEdge,
        sourceWidth: sourceEdge,
        sourceX: Math.floor((width - sourceEdge) / 2),
        sourceY: Math.floor((height - sourceEdge) / 2),
        width: outputEdge,
    };
};

const avatarCanvasPlanForCrop = (
    width: number,
    height: number,
    cropArea: SpaceImageCropArea,
): CanvasPlan => {
    if (width <= 0 || height <= 0) {
        return {
            height: 0,
            sourceHeight: 0,
            sourceWidth: 0,
            sourceX: 0,
            sourceY: 0,
            width: 0,
        };
    }

    const sourceEdge = Math.min(
        Math.max(1, Math.min(cropArea.width, cropArea.height)),
        width,
        height,
    );
    const outputEdge = spaceAvatarImageMaxEdge;

    return {
        height: outputEdge,
        sourceHeight: sourceEdge,
        sourceWidth: sourceEdge,
        sourceX: clampNumber(cropArea.x, 0, Math.max(0, width - sourceEdge)),
        sourceY: clampNumber(cropArea.y, 0, Math.max(0, height - sourceEdge)),
        width: outputEdge,
    };
};

const coverCanvasPlanForCrop = (
    width: number,
    height: number,
    cropArea: SpaceImageCropArea,
): CanvasPlan => {
    if (width <= 0 || height <= 0) {
        return {
            height: 0,
            sourceHeight: 0,
            sourceWidth: 0,
            sourceX: 0,
            sourceY: 0,
            width: 0,
        };
    }

    const sourceWidth = Math.min(Math.max(1, cropArea.width), width);
    const sourceHeight = Math.min(Math.max(1, cropArea.height), height);
    const dimensions = scaledDimensions(
        sourceWidth,
        sourceHeight,
        spaceCoverImageMaxWidth,
    );

    return {
        ...dimensions,
        sourceHeight,
        sourceWidth,
        sourceX: clampNumber(cropArea.x, 0, Math.max(0, width - sourceWidth)),
        sourceY: clampNumber(cropArea.y, 0, Math.max(0, height - sourceHeight)),
    };
};

const scaledDimensions = (
    width: number,
    height: number,
    maxLongEdge: number,
): { height: number; width: number } => {
    if (width <= 0 || height <= 0) return { height: 0, width: 0 };

    const longEdge = Math.max(width, height);
    if (longEdge <= maxLongEdge) {
        return { height, width };
    }

    const scale = maxLongEdge / longEdge;
    return {
        height: Math.max(1, Math.round(height * scale)),
        width: Math.max(1, Math.round(width * scale)),
    };
};

const clampNumber = (value: number, min: number, max: number) =>
    Math.min(Math.max(value, min), max);

const normalizeSpaceImageRotation = (rotationDegrees: number) =>
    ((rotationDegrees % 360) + 360) % 360;

const canvasToBlob = async (
    canvas: HTMLCanvasElement,
    mediaType: string,
): Promise<Blob> => {
    const blob = await new Promise<Blob | null>((resolve) =>
        canvas.toBlob(resolve, mediaType, spacePostImageWebPQuality),
    );
    if (!blob) throw new Error("Could not encode image");
    return blob;
};

const webPFileName = (fileName: string) => {
    const [name] = nameAndExtension(fileName.trim());
    return `${name || "post"}.webp`;
};
