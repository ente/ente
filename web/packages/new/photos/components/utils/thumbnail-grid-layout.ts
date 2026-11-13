export const thumbnailGap = 4;
export const thumbnailGridPadding = 24;
const thumbnailMaxHeight = 180;
const thumbnailMaxWidth = 180;
const thumbnailLayoutMinColumns = 4;

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
    {
        smallLayoutPadding = thumbnailGridPadding,
    }: { smallLayoutPadding?: number } = {},
): ThumbnailGridLayoutParams => {
    const isSmallerLayout = !(
        containerWidth >
        thumbnailLayoutMinColumns * thumbnailMaxWidth
    );
    const paddingInline = isSmallerLayout
        ? smallLayoutPadding
        : thumbnailGridPadding;
    const fittableColumns = getFractionFittableColumns(
        containerWidth,
        paddingInline,
    );

    let columns = Math.floor(fittableColumns);
    if (columns < thumbnailLayoutMinColumns) {
        columns = thumbnailLayoutMinColumns;
    }

    const shrinkRatio = getShrinkRatio(containerWidth, columns, paddingInline);
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

const getFractionFittableColumns = (
    width: number,
    paddingInline: number,
): number =>
    (width - 2 * paddingInline + thumbnailGap) /
    (thumbnailMaxWidth + thumbnailGap);

const getShrinkRatio = (
    width: number,
    columns: number,
    paddingInline: number,
) =>
    (width - 2 * paddingInline - (columns - 1) * thumbnailGap) /
    (columns * thumbnailMaxWidth);
