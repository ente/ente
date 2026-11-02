import type { SpaceComment, SpaceNotification } from "services/space";
import { firstNameFrom } from "utils/display";

export const commentNotificationText = (
    notification: SpaceNotification,
    viewer: string,
) => {
    if (notification.kind == "comment_reply") return "Replied to your comment";
    if (notification.kind == "comment_reaction")
        return "Reacted to your comment";
    const isOwnPost = notification.postSpaceId == viewer;
    const ownerName = firstNameFrom(notification.postOwnerName ?? "");
    const post = isOwnPost
        ? "your post"
        : notification.actorCount == 1 &&
            notification.actors[0]?.spaceId == notification.postSpaceId
          ? "their post"
          : ownerName
            ? `${ownerName}'s post`
            : notification.postOwnerSlug
              ? `@${notification.postOwnerSlug}'s post`
              : "a post";
    return `Commented on ${post}`;
};

export type CommentReplyTarget =
    | { status: "selected"; commentId: string }
    | { status: "unavailable" }
    | undefined;

export interface CommentDraft {
    text: string;
    replyTarget?: CommentReplyTarget;
    sending?: boolean;
    pendingSubmission?: { commentId: string; text: string; replyToId?: string };
}

export const validateCommentReplyTarget = (
    target: CommentReplyTarget,
    comments: SpaceComment[],
): CommentReplyTarget => {
    if (target?.status != "selected") return target;
    const comment = comments.find((item) => item.commentId == target.commentId);
    if (
        !comment ||
        comment.deleted ||
        (comment.parentId &&
            !comments.some(
                (root) => root.commentId == comment.parentId && !root.deleted,
            ))
    ) {
        return { status: "unavailable" };
    }
    return target;
};

export const commentThreads = (comments: SpaceComment[]) => {
    const ordered = comments
        .filter((comment) => !comment.deleted)
        .sort((a, b) => Date.parse(a.createdAt) - Date.parse(b.createdAt));
    return ordered
        .filter((comment) => !comment.parentId)
        .map((comment) => ({
            comment,
            replies: ordered.filter(
                (reply) => reply.parentId == comment.commentId,
            ),
        }));
};

export const groupCommentReactions = (reactions: SpaceComment["reactions"]) => {
    const ordered = [...reactions].sort(
        (a, b) => Number(b.isOwn) - Number(a.isOwn),
    );
    const groups = new Map<string, SpaceComment["reactions"]>();
    for (const reaction of ordered) {
        const group = groups.get(reaction.emoji);
        if (group) group.push(reaction);
        else groups.set(reaction.emoji, [reaction]);
    }
    return [...groups.values()].flat();
};

export const commentReactionGroups = (
    reactions: SpaceComment["reactions"],
    ownEmoji: string | undefined,
) => {
    const counts = new Map<string, number>();
    for (const { emoji, isOwn } of reactions) {
        if (!isOwn) counts.set(emoji, (counts.get(emoji) ?? 0) + 1);
    }
    if (ownEmoji) counts.set(ownEmoji, (counts.get(ownEmoji) ?? 0) + 1);
    return [...counts].map(([emoji, count]) => ({
        emoji,
        count,
        isOwn: emoji == ownEmoji,
    }));
};

const commentEmojiSegmenter =
    typeof Intl !== "undefined" && typeof Intl.Segmenter == "function"
        ? new Intl.Segmenter(undefined, { granularity: "grapheme" })
        : null;

export const isEmojiOnlyComment = (text: string) => {
    const compact = text.replace(/\s/g, "");
    const segments = commentEmojiSegmenter
        ? Array.from(
              commentEmojiSegmenter.segment(compact),
              ({ segment }) => segment,
          )
        : Array.from(compact);
    return (
        segments.length > 0 &&
        segments.length <= 3 &&
        segments.every((segment) =>
            /\p{Extended_Pictographic}|\p{Regional_Indicator}|\u20E3/u.test(
                segment,
            ),
        )
    );
};
