import type { ProfilePostItem } from "screens/ProfileScreen";
import type { SpaceProfilePost } from "services/space";

export const profilePostItemsFromPosts = (
    posts: SpaceProfilePost[],
): ProfilePostItem[] =>
    posts.map((post) => ({
        avatarUrl: post.avatarUrl,
        caption: post.caption,
        friendID: post.friendID,
        height: post.height,
        id: String(post.postId),
        imageAsset: post.imageAsset,
        imageUrl: post.imageUrl,
        isUnavailable: post.isUnavailable,
        name: post.name,
        postId: post.postId,
        spaceId: post.spaceId,
        timestampMs: post.timestampMs,
        thumbHash: post.thumbHash,
        viewerLiked: post.viewerLiked,
        width: post.width,
    }));
