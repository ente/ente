import { useSyncExternalStore } from "react";
import {
    cachedCommentCount,
    subscribeToCommentCounts,
} from "services/comment-counts";

export const useCommentCount = (
    viewer: string | undefined,
    postId: number | undefined,
    initialCount = 0,
) =>
    useSyncExternalStore(
        subscribeToCommentCounts,
        () => cachedCommentCount(viewer, postId) ?? initialCount,
        () => initialCount,
    );
