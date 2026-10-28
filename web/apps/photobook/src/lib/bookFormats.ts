export const BOOK_SIZE_MM = 210;
const PRINT_SAFE_MARGIN_MM = 10;
export const PRINT_SAFE_MARGIN_PCT =
    (PRINT_SAFE_MARGIN_MM / BOOK_SIZE_MM) * 100;

export const BOOK_LAYOUT = {
    marginMm: { h: 25, v: 25 },
    coverInsetMarginMm: { h: 29.4, v: 29.4 },
    gapMm: { h: 0.9472, v: 0.945 },
};
