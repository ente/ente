export const spacePostTileRadius = 28;
export const spaceProfilePostRadius = 16;

export const spaceTileAvatarSize = (
    tile: { width: number; height: number },
    isNineTileLayout = false,
) =>
    Math.max(
        isNineTileLayout ? 28 : 0,
        Math.min(36, Math.min(tile.width, tile.height) * 0.22),
    );

export const spaceTileCornerStyles = (radius: number) => ({
    "--space-tile-radius": `${radius}px`,
    "--space-tile-padding": `${radius / 2}px`,
    borderRadius: "var(--space-tile-radius)",
});

export const spaceTileInnerRadius =
    "calc(var(--space-tile-radius) - var(--space-tile-padding))";

export const spaceTileCircleInset = (diameter: number) =>
    `max(var(--space-tile-padding), calc(var(--space-tile-radius) - ${diameter / 2}px))`;

export const spaceTilePillInset = (height: number) =>
    `calc(var(--space-tile-padding) + max(0px, ${spaceTileInnerRadius} - ${height / 2}px) * ${1 - Math.SQRT1_2})`;
