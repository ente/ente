export const thumbnailGap = 4;
const thumbnailMaxHeight = 180;
export const thumbnailMaxWidth = 180;
export const thumbnailLayoutMinColumns = 4;

export interface ThumbnailGridLayoutParams {
    containerWidth: number;
    isSmallerLayout: boolean;
    paddingInline: number;
    columns: number;
    itemWidth: number;
    itemHeight: number;
    gap: number;
}

export const computeThumbnailGridLayoutParams = (
    containerWidth: number,
): ThumbnailGridLayoutParams => {
    const isSmallerLayout = !(
        containerWidth >
        thumbnailLayoutMinColumns * thumbnailMaxWidth
    );
    const paddingInline = getGapFromScreenEdge(containerWidth);
    const fittableColumns = getFractionFittableColumns(containerWidth);

    let columns = Math.floor(fittableColumns);
    if (columns < thumbnailLayoutMinColumns) {
        columns = thumbnailLayoutMinColumns;
    }

    const shrinkRatio = getShrinkRatio(containerWidth, columns);
    const itemHeight = thumbnailMaxHeight * shrinkRatio;
    const itemWidth = thumbnailMaxWidth * shrinkRatio;
    const gap = thumbnailGap;

    return {
        containerWidth,
        isSmallerLayout,
        paddingInline,
        columns,
        itemWidth,
        itemHeight,
        gap,
    };
};

const getFractionFittableColumns = (width: number): number =>
    (width - 2 * getGapFromScreenEdge(width) + thumbnailGap) /
    (thumbnailMaxWidth + thumbnailGap);

const getGapFromScreenEdge = (width: number) =>
    width > thumbnailLayoutMinColumns * thumbnailMaxWidth ? 24 : 4;

const getShrinkRatio = (width: number, columns: number) =>
    (width - 2 * getGapFromScreenEdge(width) - (columns - 1) * thumbnailGap) /
    (columns * thumbnailMaxWidth);
