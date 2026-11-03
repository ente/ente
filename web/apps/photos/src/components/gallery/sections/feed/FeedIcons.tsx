import type { FeedItemType } from "@/services/feed";
import {
    Add01Icon,
    BubbleChatIcon,
    FavouriteIcon,
    ReplyIcon,
} from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { Box } from "@mui/material";

export const FeedActivityIcon = ({ type }: { type: FeedItemType }) => {
    const isReply = type === "reply" || type === "replyLike";
    const commentLike = type === "commentLike" || type === "replyLike";
    return (
        <Box
            aria-hidden
            sx={{
                width: 32,
                height: 32,
                borderRadius: "50%",
                bgcolor: "fill.faint",
                position: "relative",
                display: "grid",
                placeItems: "center",
                flexShrink: 0,
                color: type === "photoLike" ? "accent.main" : "text.base",
            }}
        >
            <HugeiconsIcon
                icon={
                    type === "photoLike"
                        ? FavouriteIcon
                        : type === "sharedPhoto" || type === "sharedCollection"
                          ? Add01Icon
                          : isReply
                            ? ReplyIcon
                            : BubbleChatIcon
                }
                size={18}
                strokeWidth={1.8}
                fill={type === "photoLike" ? "currentColor" : "none"}
            />
            {commentLike && (
                <Box
                    sx={{
                        position: "absolute",
                        right: 3,
                        bottom: 3,
                        width: 10,
                        height: 10,
                        display: "flex",
                        color: "accent.main",
                    }}
                >
                    <HugeiconsIcon
                        icon={FavouriteIcon}
                        size={10}
                        strokeWidth={1.8}
                        fill="currentColor"
                    />
                </Box>
            )}
        </Box>
    );
};
