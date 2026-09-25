import React from "react";

export const SpaceEmoji: React.FC<{ emoji: string; size?: number }> = ({
    emoji,
    size = 24,
}) => {
    return (
        <span
            aria-hidden="true"
            style={{
                alignItems: "center",
                display: "inline-flex",
                flexShrink: 0,
                fontFamily:
                    '"Apple Color Emoji", "Segoe UI Emoji", "Noto Color Emoji", sans-serif',
                fontSize: size,
                justifyContent: "center",
                lineHeight: 1,
                width: size,
                height: size,
                verticalAlign: "middle",
            }}
        >
            {emoji}
        </span>
    );
};
