export const spaceProfilePostRadius = 16;

export const spaceTileCornerStyles = (radius: number) => ({
    "--space-tile-radius": `${radius}px`,
    "--space-tile-padding": `${radius / 2}px`,
    borderRadius: "var(--space-tile-radius)",
});

export const spaceTileInnerRadius =
    "calc(var(--space-tile-radius) - var(--space-tile-padding))";

export const spaceTilePillInset = (height: number) =>
    `calc(var(--space-tile-padding) + max(0px, ${spaceTileInnerRadius} - ${height / 2}px) * ${1 - Math.SQRT1_2})`;
