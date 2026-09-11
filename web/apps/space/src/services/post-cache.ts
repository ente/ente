import { z } from "zod";

const CachedSpacePostAsset = z.object({
    encryptedPostKey: z.string(),
    keyVersion: z.number(),
    mediaType: z.string().optional(),
    objectKey: z.string(),
    postId: z.number(),
    spaceId: z.string(),
});

export const CachedSpacePost = z.object({
    avatarKeyVersion: z.number().optional(),
    avatarObjectID: z.string().optional(),
    avatarSize: z.number().optional(),
    avatarUpdatedAt: z.string().optional(),
    caption: z.string().optional(),
    friendID: z.string(),
    height: z.number().optional(),
    imageAsset: CachedSpacePostAsset.optional(),
    isUnavailable: z.boolean().optional(),
    name: z.string(),
    postId: z.number(),
    spaceId: z.string(),
    thumbHash: z.string().optional(),
    timestampMs: z.number(),
    username: z.string().optional(),
    viewerLiked: z.boolean(),
    width: z.number().optional(),
});
