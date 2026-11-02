import type { SpaceNotification } from "services/space";

export const notificationGroupKey = (notification: SpaceNotification) =>
    `${notification.kind}:${
        notification.kind == "post_like" || notification.kind == "comment"
            ? notification.postId
            : notification.kind == "comment_reaction"
              ? notification.commentId
              : notification.kind == "comment_reply"
                ? notification.replyToId
                : notification.id
    }`;
