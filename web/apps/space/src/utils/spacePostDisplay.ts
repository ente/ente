import type { ProfilePostGroup } from "screens/ProfileScreen";
import type { SpaceProfilePost } from "services/space";

const profilePostDateLabel = (timestampMs: number) => {
    const date = new Date(timestampMs);
    const today = new Date();
    const yesterday = new Date(today);
    yesterday.setDate(today.getDate() - 1);
    if (date.toDateString() == today.toDateString()) return "Today";
    if (date.toDateString() == yesterday.toDateString()) return "Yesterday";
    return date.toLocaleDateString(
        typeof navigator == "undefined" ? "en-US" : navigator.language,
        { day: "numeric", month: "short", weekday: "short" },
    );
};

export const profilePostGroupsFromPosts = (
    posts: SpaceProfilePost[],
): ProfilePostGroup[] => {
    const groups = new Map<string, ProfilePostGroup>();
    posts.forEach((post) => {
        const label = profilePostDateLabel(post.timestampMs);
        const group = groups.get(label) ?? { items: [], label };
        group.items.push({
            avatarUrl: post.avatarUrl,
            caption: post.caption,
            friendID: post.friendID,
            height: post.height,
            id: String(post.postId),
            imageAsset: post.imageAsset,
            imageUrl: post.imageUrl,
            name: post.name,
            postId: post.postId,
            spaceId: post.spaceId,
            timestampMs: post.timestampMs,
            thumbHash: post.thumbHash,
            viewerLiked: post.viewerLiked,
            width: post.width,
        });
        groups.set(label, group);
    });
    return [...groups.values()];
};
