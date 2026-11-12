import { decryptBoxBytes } from "ente-base/crypto";
import { authenticatedRequestHeaders, ensureOk } from "ente-base/http";
import { apiURL } from "ente-base/origins";
import { z } from "zod";
import type { Comment } from "./comment";

const unpadReaction = (paddedReaction: string): string =>
    paddedReaction.replace(/\0+$/, "");

export interface UnifiedReaction {
    id: string;
    collectionID: number;
    fileID?: number;
    commentID?: string;
    // Only present in feed responses.
    isCommentReply?: boolean;
    reactionType: string;
    userID: number;
    anonUserID?: string;
    isDeleted: boolean;
    createdAt: number;
    updatedAt: number;
}

export interface UnifiedSocialDiff {
    comments: Comment[];
    reactions: UnifiedReaction[];
    hasMoreComments: boolean;
    hasMoreReactions: boolean;
}

export const getUnifiedSocialDiff = async (
    collectionID: number,
    collectionKey: string,
    {
        fileID,
        commentsSinceTime = 0,
        reactionsSinceTime = 0,
        signal,
    }: {
        fileID?: number;
        commentsSinceTime?: number;
        reactionsSinceTime?: number;
        signal?: AbortSignal;
    } = {},
) => {
    const res = await fetch(
        await apiURL("/social/diff", {
            collectionID,
            ...(fileID === undefined ? {} : { fileID }),
            commentsSinceTime,
            reactionsSinceTime,
            limit: 1000,
        }),
        { headers: await authenticatedRequestHeaders(), signal },
    );
    ensureOk(res);
    const data = UnifiedDiffResponse.parse(await res.json());
    return {
        ...(await decryptSocialDiff(collectionKey, data)),
        commentsUpdatedAt: Math.max(
            commentsSinceTime,
            ...data.comments.map((c) => c.updatedAt),
        ),
        reactionsUpdatedAt: Math.max(
            reactionsSinceTime,
            ...data.reactions.map((r) => r.updatedAt),
        ),
    };
};

const decryptSocialDiff = async (
    collectionKey: string,
    responseJson: unknown,
): Promise<UnifiedSocialDiff> => {
    const data = UnifiedDiffResponse.parse(responseJson);

    const comments: Comment[] = [];
    for (const comment of data.comments) {
        if (comment.isDeleted || !comment.cipher || !comment.nonce) {
            comments.push({
                id: comment.id,
                collectionID: comment.collectionID,
                fileID: comment.fileID ?? undefined,
                parentCommentID: comment.parentCommentID ?? undefined,
                parentCommentUserID: comment.parentCommentUserID ?? undefined,
                userID: comment.userID,
                anonUserID: comment.anonUserID ?? undefined,
                text: "",
                isDeleted: comment.isDeleted,
                createdAt: comment.createdAt,
                updatedAt: comment.updatedAt,
            });
            continue;
        }
        try {
            const decrypted = await decryptBoxBytes(
                { encryptedData: comment.cipher, nonce: comment.nonce },
                collectionKey,
            );
            const text = new TextDecoder().decode(decrypted);
            const decryptedComment = {
                id: comment.id,
                collectionID: comment.collectionID,
                fileID: comment.fileID ?? undefined,
                parentCommentID: comment.parentCommentID ?? undefined,
                parentCommentUserID: comment.parentCommentUserID ?? undefined,
                userID: comment.userID,
                anonUserID: comment.anonUserID ?? undefined,
                text,
                isDeleted: comment.isDeleted,
                createdAt: comment.createdAt,
                updatedAt: comment.updatedAt,
            };
            comments.push(decryptedComment);
        } catch {
            // Skip comments that fail to decrypt
        }
    }

    const reactions: UnifiedReaction[] = [];
    for (const reaction of data.reactions) {
        if (reaction.isDeleted || !reaction.cipher || !reaction.nonce) continue;
        try {
            const decrypted = await decryptBoxBytes(
                { encryptedData: reaction.cipher, nonce: reaction.nonce },
                collectionKey,
            );
            const reactionType = unpadReaction(
                new TextDecoder().decode(decrypted),
            );
            reactions.push({
                id: reaction.id,
                collectionID: reaction.collectionID,
                fileID: reaction.fileID ?? undefined,
                commentID: reaction.commentID ?? undefined,
                isCommentReply: reaction.isCommentReply ?? undefined,
                reactionType,
                userID: reaction.userID,
                anonUserID: reaction.anonUserID ?? undefined,
                isDeleted: reaction.isDeleted,
                createdAt: reaction.createdAt,
                updatedAt: reaction.updatedAt,
            });
        } catch {
            // Skip reactions that fail to decrypt
        }
    }

    const result = {
        comments,
        reactions,
        hasMoreComments: data.hasMoreComments,
        hasMoreReactions: data.hasMoreReactions,
    };
    return result;
};

const RemoteComment = z.object({
    id: z.string(),
    collectionID: z.number(),
    fileID: z.number().nullish(),
    parentCommentID: z.string().nullish(),
    parentCommentUserID: z.number().nullish(),
    userID: z.number(),
    anonUserID: z.string().nullish(),
    cipher: z.string().nullish(),
    nonce: z.string().nullish(),
    isDeleted: z.boolean(),
    createdAt: z.number(),
    updatedAt: z.number(),
});

const RemoteReaction = z.object({
    id: z.string(),
    collectionID: z.number(),
    fileID: z.number().nullish(),
    commentID: z.string().nullish(),
    isCommentReply: z.boolean().nullish(),
    userID: z.number(),
    anonUserID: z.string().nullish(),
    cipher: z.string().nullish(),
    nonce: z.string().nullish(),
    isDeleted: z.boolean(),
    createdAt: z.number(),
    updatedAt: z.number(),
});

const UnifiedDiffResponse = z.object({
    comments: z.array(RemoteComment),
    reactions: z.array(RemoteReaction),
    hasMoreComments: z.boolean(),
    hasMoreReactions: z.boolean(),
});

export const getAnonProfiles = async (
    collectionID: number,
    collectionKey: string,
    signal?: AbortSignal,
): Promise<Map<string, string>> => {
    const res = await fetch(
        await apiURL("/social/anon-profiles", { collectionID }),
        { headers: await authenticatedRequestHeaders(), signal },
    );
    ensureOk(res);
    const { profiles } = GetAnonProfilesResponse.parse(await res.json());

    const anonUserNames = new Map<string, string>();
    for (const profile of profiles) {
        if (!profile.cipher || !profile.nonce) continue;
        try {
            const decrypted = await decryptBoxBytes(
                { encryptedData: profile.cipher, nonce: profile.nonce },
                collectionKey,
            );
            const userName = new TextDecoder().decode(decrypted);
            if (userName) {
                anonUserNames.set(profile.anonUserID, userName);
            }
        } catch {
            // Skip profiles that fail to decrypt
        }
    }
    return anonUserNames;
};

const RemoteAnonProfile = z.object({
    anonUserID: z.string(),
    collectionID: z.number(),
    cipher: z.string().nullish(),
    nonce: z.string().nullish(),
    createdAt: z.number(),
    updatedAt: z.number(),
});

const GetAnonProfilesResponse = z.object({
    profiles: z
        .array(RemoteAnonProfile)
        .nullish()
        .transform((v) => v ?? []),
});

const SocialUpdatesResponse = z.object({
    updates: z
        .array(
            z.object({
                collectionID: z.number(),
                commentsUpdatedAt: z.number().nullish(),
                reactionsUpdatedAt: z.number().nullish(),
                anonProfilesUpdatedAt: z.number().nullish(),
            }),
        )
        .nullish()
        .transform((updates) => updates ?? []),
});

export const getSocialUpdates = async (signal?: AbortSignal) => {
    const response = await fetch(
        await apiURL("/comments-reactions/updated-at"),
        { headers: await authenticatedRequestHeaders(), signal },
    );
    ensureOk(response);
    return SocialUpdatesResponse.parse(await response.json()).updates;
};
