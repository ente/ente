import type React from "react";
import type { SpacePost } from "services/space";
import type {
    FailedSpaceFeedPost,
    LocalSpaceFeedPost,
} from "state/spaceAppState";

let nextLocalFeedPostID = 0;

const postedConfirmationDurationMs = 1500;

export const createLocalFeedPostID = () =>
    `space-local-post-${Date.now()}-${nextLocalFeedPostID++}`;

export const confirmLocalFeedPost = (
    setLocalFeedPosts: React.Dispatch<
        React.SetStateAction<LocalSpaceFeedPost[]>
    >,
    localPostId: string,
    post: SpacePost,
) => {
    setLocalFeedPosts((currentPosts) =>
        currentPosts.map((item) =>
            item.id == localPostId
                ? { id: localPostId, post, status: "posted" }
                : item,
        ),
    );

    window.setTimeout(() => {
        setLocalFeedPosts((currentPosts) =>
            currentPosts.map((item) =>
                item.id == localPostId && item.status == "posted"
                    ? { id: localPostId, post: item.post, status: "ready" }
                    : item,
            ),
        );
    }, postedConfirmationDurationMs);
};

export const failLocalFeedPost = (
    setLocalFeedPosts: React.Dispatch<
        React.SetStateAction<LocalSpaceFeedPost[]>
    >,
    localPostId: string,
    reason?: FailedSpaceFeedPost["reason"],
) => {
    setLocalFeedPosts((currentPosts) =>
        currentPosts.map((item) =>
            item.id == localPostId && item.status == "pending"
                ? { ...item, reason, status: "failed" }
                : item,
        ),
    );
};
