import { Box } from "@mui/material";
import { SpaceEmoji } from "components/Emoji";
import React from "react";
import {
    spaceDialogBackground,
    spaceText,
    spaceTextMuted,
} from "styles/colors";
import { sameEmoji } from "utils/emoji";

const quickReactions = [
    { emoji: "❤️", name: "red heart" },
    { emoji: "😂", name: "face with tears of joy" },
    { emoji: "😮", name: "face with open mouth" },
    { emoji: "😢", name: "crying face" },
    { emoji: "👍", name: "thumbs up" },
    { emoji: "🎉", name: "party popper" },
];
const hoverBackground = "#525254";
const buttonStyle = {
    alignItems: "center",
    bgcolor: "transparent",
    border: 0,
    borderRadius: "50%",
    color: spaceText,
    cursor: "pointer",
    display: "inline-flex",
    height: 40,
    justifyContent: "center",
    p: 0,
    width: 40,
    "& > span": { transform: "translateY(2px)" },
    "&[aria-pressed=true]": { bgcolor: hoverBackground },
    "@media (hover: hover)": { "&:hover": { bgcolor: hoverBackground } },
    "&:focus-visible": {
        outline: `2px solid ${spaceTextMuted}`,
        outlineOffset: -2,
    },
};

export const SpaceQuickReactions: React.FC<{
    reaction?: string;
    onSelect: (emoji: string) => void;
    onMore: () => void;
}> = ({ reaction, onSelect, onMore }) => {
    const choices = reaction
        ? [
              ...quickReactions
                  .filter(({ emoji }) => !sameEmoji(reaction, emoji))
                  .slice(0, quickReactions.length - 1),
              {
                  emoji: reaction,
                  name:
                      quickReactions.find(({ emoji }) =>
                          sameEmoji(reaction, emoji),
                      )?.name ?? reaction,
              },
          ]
        : quickReactions;
    return (
        <Box
            role="group"
            aria-label="React to message"
            sx={{
                bgcolor: spaceDialogBackground,
                borderRadius: "28px",
                boxShadow: "0 14px 40px rgba(0, 0, 0, 0.14)",
                display: "flex",
                p: "4px",
            }}
        >
            {choices.map(({ emoji, name }, index) => (
                <Box
                    component="button"
                    type="button"
                    key={emoji}
                    autoFocus={index === 0}
                    aria-label={
                        sameEmoji(reaction, emoji)
                            ? `Remove ${name} reaction`
                            : `React with ${name}`
                    }
                    aria-pressed={sameEmoji(reaction, emoji)}
                    onClick={() => onSelect(emoji)}
                    sx={buttonStyle}
                >
                    <SpaceEmoji emoji={emoji} />
                </Box>
            ))}
            <Box
                component="button"
                type="button"
                aria-label="More emoji"
                aria-haspopup="dialog"
                onClick={onMore}
                sx={{ ...buttonStyle, fontSize: 28 }}
            >
                +
            </Box>
        </Box>
    );
};
