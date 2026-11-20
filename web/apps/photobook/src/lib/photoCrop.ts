import type { PhotoSlot } from "./types";

export function getPhotoDrawLayout(
    slot: PhotoSlot,
    imageWidth: number,
    imageHeight: number,
    pageWidth: number,
    pageHeight: number,
) {
    const slotWidth = (slot.width / 100) * pageWidth;
    const slotHeight = (slot.height / 100) * pageHeight;
    const rotation = slot.rotation ?? 0;
    const sideways = rotation % 180 !== 0;
    const rotatedWidth = sideways ? imageHeight : imageWidth;
    const rotatedHeight = sideways ? imageWidth : imageHeight;
    const scale =
        Math.max(slotWidth / rotatedWidth, slotHeight / rotatedHeight) *
        slot.cropZoom;
    const width = imageWidth * scale;
    const height = imageHeight * scale;
    const boundsWidth = rotatedWidth * scale;
    const boundsHeight = rotatedHeight * scale;
    const slackX = slotWidth - boundsWidth;
    const slackY = slotHeight - boundsHeight;

    return {
        x: (slot.x / 100) * pageWidth + slackX * slot.cropX + boundsWidth / 2,
        y: (slot.y / 100) * pageHeight + slackY * slot.cropY + boundsHeight / 2,
        width,
        height,
        rotation,
        slackX,
        slackY,
    };
}
