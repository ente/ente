export const profilePhotoGap = 3;
export const profilePhotoMinRowHeight = 100;

export const profilePhotoRows = <Tile extends { aspectRatio: number }>(
    tiles: Tile[],
    width: number,
) => {
    const rows: { aspectRatio: number; tiles: Tile[] }[] = [];
    let nextTileIndex = 0;

    while (nextTileIndex < tiles.length) {
        const remainingTiles = tiles.length - nextTileIndex;
        let rowSize =
            remainingTiles <= 3
                ? remainingTiles
                : remainingTiles == 4 || remainingTiles == 5
                  ? 2
                  : remainingTiles % 2 == 0
                    ? 2
                    : 3;
        const rowTiles = tiles.slice(nextTileIndex, nextTileIndex + rowSize);
        let aspectRatio = rowTiles.reduce(
            (sum, tile) => sum + tile.aspectRatio,
            0,
        );

        while (
            rowSize > 1 &&
            (width - (rowSize - 1) * profilePhotoGap) / aspectRatio <
                profilePhotoMinRowHeight
        ) {
            aspectRatio -= rowTiles.pop()!.aspectRatio;
            rowSize--;
        }

        rows.push({ aspectRatio, tiles: rowTiles });
        nextTileIndex += rowSize;
    }

    return rows;
};
