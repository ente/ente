import assets from "data/emoji-assets.json";
import React from "react";
import { emojiKey } from "utils/emoji";

const indices: Record<string, number> = assets.indices;

export const SpaceEmoji: React.FC<{ emoji: string; size?: number }> = ({
    emoji,
    size = 24,
}) => {
    const index = indices[emojiKey(emoji)];
    const sheetSize = assets.columns * assets.columns;
    return (
        <span
            aria-hidden="true"
            style={{
                display: "inline-block",
                flexShrink: 0,
                width: size,
                height: size,
                fontSize: size,
                lineHeight: `${size}px`,
                overflow: "hidden",
                verticalAlign: "middle",
                ...(index !== undefined && {
                    backgroundImage: `url(/emoji/${assets.version}/${Math.floor(index / sheetSize)}.webp)`,
                    backgroundSize: `${size * assets.columns}px ${size * assets.columns}px`,
                    backgroundPosition: `${-(index % assets.columns) * size}px ${-Math.floor((index % sheetSize) / assets.columns) * size}px`,
                }),
            }}
        >
            {index === undefined ? emoji : null}
        </span>
    );
};
