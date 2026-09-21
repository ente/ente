import type { SpaceImageCropArea } from "utils/post-image";

export type CropHandle = "nw" | "n" | "ne" | "e" | "se" | "s" | "sw" | "w";
export interface ImageSize {
    width: number;
    height: number;
}

const clamp = (value: number, min: number, max: number) =>
    Math.min(Math.max(value, min), max);

export const rotatedImageSize = (
    size: ImageSize,
    rotation: number,
): ImageSize =>
    rotation % 180 == 0 ? size : { width: size.height, height: size.width };

export const fullImageCrop = (size: ImageSize): SpaceImageCropArea => ({
    x: 0,
    y: 0,
    width: size.width,
    height: size.height,
});

export const cropWithAspect = (
    crop: SpaceImageCropArea,
    aspect: number,
    size: ImageSize,
): SpaceImageCropArea => {
    const width = Math.min(
        Math.sqrt(crop.width * crop.height * aspect),
        size.width,
        size.height * aspect,
    );
    const height = width / aspect;
    return {
        x: clamp(crop.x + crop.width / 2 - width / 2, 0, size.width - width),
        y: clamp(
            crop.y + crop.height / 2 - height / 2,
            0,
            size.height - height,
        ),
        width,
        height,
    };
};

export const rotateImageCrop = (
    crop: SpaceImageCropArea,
    size: ImageSize,
): SpaceImageCropArea => ({
    x: size.height - crop.y - crop.height,
    y: crop.x,
    width: crop.height,
    height: crop.width,
});

export const moveImageCrop = (
    crop: SpaceImageCropArea,
    dx: number,
    dy: number,
    size: ImageSize,
): SpaceImageCropArea => ({
    ...crop,
    x: clamp(crop.x + dx, 0, size.width - crop.width),
    y: clamp(crop.y + dy, 0, size.height - crop.height),
});

export const resizeImageCrop = (
    crop: SpaceImageCropArea,
    handle: CropHandle,
    dx: number,
    dy: number,
    size: ImageSize,
    minSize: number,
    aspect?: number,
): SpaceImageCropArea => {
    const west = handle.includes("w");
    const north = handle.includes("n");
    const horizontal = west || handle.includes("e");
    const vertical = north || handle.includes("s");
    const anchorX = west ? crop.x + crop.width : crop.x;
    const anchorY = north ? crop.y + crop.height : crop.y;
    const maxWidth = west ? anchorX : size.width - anchorX;
    const maxHeight = north ? anchorY : size.height - anchorY;
    let width = horizontal ? crop.width + (west ? -dx : dx) : crop.width;
    let height = vertical ? crop.height + (north ? -dy : dy) : crop.height;
    if (aspect) {
        const proposedWidth =
            Math.abs(dx) >= Math.abs(dy * aspect) ? width : height * aspect;
        const max = Math.min(maxWidth, maxHeight * aspect);
        width = clamp(
            proposedWidth,
            Math.min(minSize * Math.max(1, aspect), max),
            max,
        );
        height = width / aspect;
    } else {
        width = clamp(width, Math.min(minSize, maxWidth), maxWidth);
        height = clamp(height, Math.min(minSize, maxHeight), maxHeight);
    }
    return {
        x: west ? anchorX - width : crop.x,
        y: north ? anchorY - height : crop.y,
        width,
        height,
    };
};
