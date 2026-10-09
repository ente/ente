import type { SpacePost } from "services/space";
import type { LocalSpaceFeedPost } from "state/app-state";

export type HomeFeedEntry =
    | {
          identity: string;
          item: LocalSpaceFeedPost;
          kind: "local";
          renderKey: string;
      }
    | { identity: string; item: SpacePost; kind: "remote"; renderKey: string };

export const homeFeedEntries = (
    feedItems: SpacePost[],
    localFeedPosts: LocalSpaceFeedPost[],
    newPostsSinceMs: number | undefined,
    latestPostIDs?: ReadonlySet<number>,
    viewerSpaceId?: string,
) => {
    const localResolvedPostIds = new Set(
        localFeedPosts.map((item) =>
            item.status == "posted" || item.status == "ready"
                ? item.post.postId
                : item.postId,
        ),
    );
    const entries: HomeFeedEntry[] = [
        ...localFeedPosts.map((item): HomeFeedEntry => ({
            identity:
                item.status == "posted" || item.status == "ready"
                    ? `post:${item.post.postId}`
                    : item.postId
                      ? `post:${item.postId}`
                      : `local:${item.id}`,
            item,
            kind: "local",
            renderKey: `local:${item.id}`,
        })),
        ...feedItems
            .filter((item) => !localResolvedPostIds.has(item.postId))
            .map((item): HomeFeedEntry => ({
                identity: `post:${item.postId}`,
                item,
                kind: "remote",
                renderKey: `post:${item.postId}`,
            })),
    ];
    const latest: HomeFeedEntry[] = [];
    const history: SpacePost[] = [];
    for (const entry of entries) {
        let post: SpacePost;
        if (entry.kind == "remote") {
            post = entry.item;
        } else {
            if (entry.item.status != "ready") {
                latest.push(entry);
                continue;
            }
            post = entry.item.post;
        }
        if (
            latestPostIDs?.has(post.postId) ||
            (post.spaceId != viewerSpaceId &&
                newPostsSinceMs != undefined &&
                post.timestampMs > newPostsSinceMs)
        ) {
            latest.push(entry);
        } else {
            history.push(post);
        }
    }
    history.sort(
        (a, b) => b.timestampMs - a.timestampMs || b.postId - a.postId,
    );
    return { latest, history };
};
