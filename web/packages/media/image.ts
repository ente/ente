export const scaledImageDimensions = (
    width: number,
    height: number,
    maxDimension: number,
): { width: number; height: number } => {
    if (width == 0 || height == 0) return { width: 0, height: 0 };
    const widthScaleFactor = maxDimension / width;
    const heightScaleFactor = maxDimension / height;
    const scaleFactor = Math.min(1, widthScaleFactor, heightScaleFactor);
    const resizedDimensions = {
        width: Math.round(width * scaleFactor),
        height: Math.round(height * scaleFactor),
    };
    if (resizedDimensions.width == 0 || resizedDimensions.height == 0)
        return { width: 0, height: 0 };
    return resizedDimensions;
};
