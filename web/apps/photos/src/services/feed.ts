import type { Collection } from "ente-media/collection";
import type { EnteFile } from "ente-media/file";
import { FileType } from "ente-media/file-type";
import type { Comment } from "ente-new/photos/services/comment";
import type { UnifiedReaction } from "ente-new/photos/services/social";

export type FeedItemType =
    | "photoLike"
    | "comment"
    | "reply"
    | "commentLike"
    | "replyLike"
    | "sharedPhoto"
    | "sharedCollection";

export interface FeedActor {
    userID: number;
    anonUserID?: string;
}

export interface FeedItem {
    id: string;
    type: FeedItemType;
    collectionID: number;
    collectionName: string;
    fileID?: number;
    commentID?: string;
    actors: FeedActor[];
    createdAt: number;
    isOwnedByCurrentUser: boolean;
    isVideo: boolean;
    files: EnteFile[];
}

export interface FeedSocialData {
    comments: Comment[];
    reactions: UnifiedReaction[];
    anonNames: Record<string, string>;
}

export const emptyFeedSocialData = (): FeedSocialData => ({
    comments: [],
    reactions: [],
    anonNames: {},
});

export const feedActorKey = (actor: FeedActor) =>
    actor.anonUserID ? `anonymous:${actor.anonUserID}` : `user:${actor.userID}`;

const additionSessionGap = 10 * 60 * 1_000_000;

export const buildFeedItems = ({
    userID,
    collections,
    files,
    socialByCollection,
    hiddenCollectionIDs,
    excludedFileIDs,
}: {
    userID: number;
    collections: readonly Collection[];
    files: readonly EnteFile[];
    socialByCollection: Readonly<Record<number, FeedSocialData>>;
    hiddenCollectionIDs: ReadonlySet<number>;
    excludedFileIDs: ReadonlySet<number>;
}): FeedItem[] => {
    const albums = new Map(
        collections
            .filter((c) => !hiddenCollectionIDs.has(c.id))
            .map((c) => [c.id, c]),
    );
    const visibleFiles = files.filter(
        (f) => albums.has(f.collectionID) && !excludedFileIDs.has(f.id),
    );
    const fileByKey = new Map(
        visibleFiles.map((f) => [`${f.collectionID}:${f.id}`, f]),
    );
    const items = new Map<string, FeedItem>();

    for (const album of albums.values()) {
        const social = socialByCollection[album.id];
        if (!social) continue;
        const comments = new Map(social.comments.map((c) => [c.id, c]));
        const add = (
            type: FeedItemType,
            group: string | number,
            actor: FeedActor,
            createdAt: number,
            fileID: number | undefined,
            commentID: string | undefined,
            owned: boolean,
        ) => {
            if (actor.userID === userID) return;
            const file = fileByKey.get(`${album.id}:${fileID}`);
            if (!file) return;
            const id = `${type}:${album.id}:${group}`;
            const existing = items.get(id);
            if (existing) {
                if (
                    !existing.actors.some(
                        (a) => feedActorKey(a) === feedActorKey(actor),
                    )
                )
                    existing.actors.push(actor);
            } else {
                items.set(id, {
                    id,
                    type,
                    collectionID: album.id,
                    collectionName: album.name,
                    fileID: file.id,
                    commentID,
                    actors: [actor],
                    createdAt,
                    isOwnedByCurrentUser: owned,
                    isVideo: file.metadata.fileType === FileType.video,
                    files: [file],
                });
            }
        };
        for (const comment of [...comments.values()].sort(
            (a, b) => b.createdAt - a.createdAt,
        )) {
            if (comment.isDeleted) continue;
            const parent = comment.parentCommentID
                ? comments.get(comment.parentCommentID)
                : undefined;
            if (comment.parentCommentID) {
                add(
                    "reply",
                    comment.parentCommentID,
                    comment,
                    comment.createdAt,
                    comment.fileID ?? parent?.fileID,
                    comment.id,
                    (parent?.userID ?? comment.parentCommentUserID) === userID,
                );
            } else if (comment.fileID !== undefined) {
                add(
                    "comment",
                    comment.fileID,
                    comment,
                    comment.createdAt,
                    comment.fileID,
                    comment.id,
                    fileByKey.get(`${album.id}:${comment.fileID}`)?.ownerID ===
                        userID,
                );
            }
        }
        for (const reaction of [...social.reactions].sort(
            (a, b) => b.createdAt - a.createdAt,
        )) {
            if (reaction.isDeleted) continue;
            if (reaction.commentID) {
                const comment = comments.get(reaction.commentID);
                if (!comment || comment.isDeleted) continue;
                add(
                    comment.parentCommentID ? "replyLike" : "commentLike",
                    comment.id,
                    reaction,
                    reaction.createdAt,
                    comment.fileID,
                    comment.id,
                    comment.userID === userID,
                );
            } else if (reaction.fileID !== undefined) {
                add(
                    "photoLike",
                    reaction.fileID,
                    reaction,
                    reaction.createdAt,
                    reaction.fileID,
                    undefined,
                    fileByKey.get(`${album.id}:${reaction.fileID}`)?.ownerID ===
                        userID,
                );
            }
        }
    }

    const initialFiles = new Map<number, EnteFile[]>();
    const sessions = new Map<string, { item: FeedItem; oldestAt: number }>();
    const recentlyAdded = visibleFiles
        .filter((f) => {
            if (f.ownerID === userID || (f.collectionAddedAt ?? 0) <= 0)
                return false;
            const album = albums.get(f.collectionID)!;
            return (
                f.pubMagicMetadata?.data.uploaderName == null ||
                (album.owner.id !== userID &&
                    !!album.sharedAt &&
                    f.collectionAddedAt! <= album.sharedAt)
            );
        })
        .sort(
            (a, b) =>
                b.collectionAddedAt! - a.collectionAddedAt! || b.id - a.id,
        )
        .slice(0, 1000);
    for (const file of recentlyAdded) {
        const album = albums.get(file.collectionID)!;
        const addedAt = file.collectionAddedAt!;
        if (
            album.owner.id !== userID &&
            album.sharedAt &&
            addedAt <= album.sharedAt
        ) {
            const previews = initialFiles.get(album.id) ?? [];
            if (previews.length < 30) previews.push(file);
            initialFiles.set(album.id, previews);
            continue;
        }
        if (file.pubMagicMetadata?.data.uploaderName != null) continue;
        const group = `${album.id}:${file.ownerID}`;
        const session = sessions.get(group);
        if (session && session.oldestAt - addedAt <= additionSessionGap) {
            session.item.files.push(file);
            session.oldestAt = addedAt;
        } else {
            const item: FeedItem = {
                id: `sharedPhoto:${group}:${addedAt}`,
                type: "sharedPhoto",
                collectionID: album.id,
                collectionName: album.name,
                fileID: file.id,
                actors: [{ userID: file.ownerID }],
                createdAt: addedAt,
                isOwnedByCurrentUser: false,
                isVideo: false,
                files: [file],
            };
            items.set(item.id, item);
            sessions.set(group, { item, oldestAt: addedAt });
        }
    }
    for (const album of albums.values()) {
        if (album.owner.id === userID || !album.sharedAt || album.sharedAt <= 0)
            continue;
        const previews = initialFiles.get(album.id) ?? [];
        const id = `sharedCollection:${album.id}`;
        items.set(id, {
            id,
            type: "sharedCollection",
            collectionID: album.id,
            collectionName: album.name,
            actors: [{ userID: album.owner.id }],
            createdAt: album.sharedAt,
            fileID: previews[0]?.id,
            isOwnedByCurrentUser: false,
            isVideo: false,
            files: previews,
        });
    }
    return [...items.values()]
        .sort((a, b) => b.createdAt - a.createdAt || a.id.localeCompare(b.id))
        .slice(0, 500);
};
