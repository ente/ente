import { minimumPostPhotoFrameAspectRatio } from "../styles/tiles";

const gap = 8;

interface PostGridPhoto {
    batchIndex?: number;
    frameAspectRatio?: number;
    width?: number;
    height?: number;
}

interface TileRect {
    left: number;
    top: number;
    width: number;
    height: number;
}

interface PhotoGroup {
    kind: "single" | "row" | "split";
    side?: "left" | "right";
    height: number;
    tiles: TileRect[];
}

const photoGroups = (ratios: number[], width: number): PhotoGroup[] => {
    const [first, second, third] = ratios;
    const groups: PhotoGroup[] = [
        {
            kind: "single",
            height: width / first!,
            tiles: [{ left: 0, top: 0, width, height: width / first! }],
        },
    ];
    if (second != undefined) {
        const height = (width - gap) / (first! + second);
        const firstWidth = height * first!;
        groups.push({
            kind: "row",
            height,
            tiles: [
                { left: 0, top: 0, width: firstWidth, height },
                {
                    left: firstWidth + gap,
                    top: 0,
                    width: width - firstWidth - gap,
                    height,
                },
            ],
        });
    }
    if (second != undefined && third != undefined) {
        for (const side of ["left", "right"] as const) {
            const largeRatio = side == "left" ? first! : second;
            const topRatio = side == "left" ? second : first!;
            const stackRatio = 1 / (1 / topRatio + 1 / third);
            const height =
                (width - gap + gap * stackRatio) / (largeRatio + stackRatio);
            const largeWidth = height * largeRatio;
            const stackWidth = width - gap - largeWidth;
            const stackLeft = side == "left" ? largeWidth + gap : 0;
            const large = {
                left: side == "left" ? 0 : stackWidth + gap,
                top: 0,
                width: largeWidth,
                height,
            };
            const top = {
                left: stackLeft,
                top: 0,
                width: stackWidth,
                height: stackWidth / topRatio,
            };
            groups.push({
                kind: "split",
                side,
                height,
                tiles: [
                    ...(side == "left" ? [large, top] : [top, large]),
                    {
                        left: stackLeft,
                        top: top.height + gap,
                        width: stackWidth,
                        height: stackWidth / third,
                    },
                ],
            });
        }
    }
    return groups;
};

export const layoutPostGrid = (
    photos: PostGridPhoto[],
    width: number,
    fullWidth = false,
): { tiles: TileRect[]; height: number } => {
    const tiles: TileRect[] = [];
    if (width <= gap) return { tiles, height: 0 };

    const ratios = photos.map((photo) =>
        Math.max(
            minimumPostPhotoFrameAspectRatio,
            photo.frameAspectRatio ??
                (photo.width && photo.height ? photo.width / photo.height : 1),
        ),
    );
    let top = 0;
    let previousKind: PhotoGroup["kind"] | undefined;
    let previousSide: PhotoGroup["side"];
    while (tiles.length < photos.length) {
        const start = tiles.length;
        let end = start + 1;
        while (
            end < photos.length &&
            end < start + (fullWidth ? 1 : 3) &&
            photos[end]!.batchIndex == photos[start]!.batchIndex
        )
            end++;
        const candidates = photoGroups(ratios.slice(start, end), width);
        const score = (group: PhotoGroup) => {
            if (
                group.tiles.length > 1 &&
                group.tiles.some(
                    (tile) =>
                        tile.width < width * 0.28 || tile.height < width * 0.2,
                )
            )
                return Infinity;
            return (
                Math.abs(group.height / width - 0.65) +
                (group.kind == previousKind ? 0.35 : 0) +
                (group.side && group.side == previousSide ? 0.04 : 0)
            );
        };
        const group = candidates.reduce((best, candidate) =>
            score(candidate) < score(best) ? candidate : best,
        );
        tiles.push(
            ...group.tiles.map((tile) => ({ ...tile, top: tile.top + top })),
        );
        top += group.height + gap;
        previousKind = group.kind;
        if (group.side) previousSide = group.side;
    }
    return { tiles, height: tiles.length ? top - gap : 0 };
};
