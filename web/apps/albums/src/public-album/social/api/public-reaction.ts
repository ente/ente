import { decryptBox, encryptBox } from "ente-base/crypto";
import {
    authenticatedPublicAlbumsRequestHeaders,
    ensureOk,
    type PublicAlbumsCredentials,
} from "ente-base/http";
import log from "ente-base/log";
import { apiURL } from "ente-base/origins";
import { z } from "zod";

// Fixed-size plaintext prevents ciphertext length from revealing the reaction.
// The longest reaction name is about 70 characters.
const paddedReactionLength = 100;

const padReaction = (reactionType: string): string =>
    reactionType.padEnd(paddedReactionLength, "\0");

const unpadReaction = (paddedReaction: string): string =>
    paddedReaction.replace(/\0+$/, "");

export interface AnonIdentity {
    anonUserID: string;
    token: string;
    expiresAt: number;
}

const AnonIdentityResponse = z.object({
    anonUserID: z.string(),
    token: z.string(),
    expiresAt: z.number(),
});

const ANON_IDENTITY_STORAGE_KEY_PREFIX = "ente_anon_identity";

const getStorageKey = (collectionID: number): string =>
    `${ANON_IDENTITY_STORAGE_KEY_PREFIX}_${collectionID}`;

export const getStoredAnonIdentity = (
    collectionID: number,
): AnonIdentity | undefined => {
    if (typeof window === "undefined") return undefined;
    const stored = localStorage.getItem(getStorageKey(collectionID));
    if (!stored) return undefined;
    try {
        const identity = AnonIdentityResponse.parse(JSON.parse(stored));
        // expiresAt is in microseconds.
        const nowMicroseconds = Date.now() * 1000;
        if (identity.expiresAt && nowMicroseconds > identity.expiresAt) {
            clearAnonIdentity(collectionID);
            return undefined;
        }
        return identity;
    } catch {
        clearAnonIdentity(collectionID);
        return undefined;
    }
};

export const storeAnonIdentity = (
    collectionID: number,
    identity: AnonIdentity,
): void => {
    if (typeof window === "undefined") return;
    localStorage.setItem(getStorageKey(collectionID), JSON.stringify(identity));
};

export const clearAnonIdentity = (collectionID: number): void => {
    if (typeof window === "undefined") return;
    localStorage.removeItem(getStorageKey(collectionID));
};

export const createAnonIdentity = async (
    credentials: PublicAlbumsCredentials,
    collectionID: number,
    userName: string,
    collectionKey: string,
): Promise<AnonIdentity> => {
    const { encryptedData: cipher, nonce } = await encryptBox(
        new TextEncoder().encode(userName),
        collectionKey,
    );

    const res = await fetch(await apiURL("/public-collection/anon-identity"), {
        method: "POST",
        headers: {
            ...authenticatedPublicAlbumsRequestHeaders(credentials),
            "Content-Type": "application/json",
        },
        body: JSON.stringify({ cipher, nonce }),
    });
    ensureOk(res);
    const identity = AnonIdentityResponse.parse(await res.json());

    storeAnonIdentity(collectionID, identity);

    return identity;
};

export const addPublicReaction = async (
    credentials: PublicAlbumsCredentials,
    collectionID: number,
    fileID: number,
    reactionType: string,
    collectionKey: string,
    anonIdentity?: AnonIdentity,
): Promise<string> => {
    const identity = anonIdentity ?? getStoredAnonIdentity(collectionID);
    if (!identity) {
        throw new Error("No anonymous identity available");
    }

    const { encryptedData: cipher, nonce } = await encryptBox(
        new TextEncoder().encode(padReaction(reactionType)),
        collectionKey,
    );

    const res = await fetch(await apiURL("/public-collection/reactions"), {
        method: "POST",
        headers: {
            ...authenticatedPublicAlbumsRequestHeaders(credentials),
            "Content-Type": "application/json",
        },
        body: JSON.stringify({
            fileID,
            cipher,
            nonce,
            anonUserID: identity.anonUserID,
            anonToken: identity.token,
        }),
    });
    ensureOk(res);
    const { id } = UpsertReactionResponse.parse(await res.json());
    return id;
};

export const addPublicCommentReaction = async (
    credentials: PublicAlbumsCredentials,
    collectionID: number,
    commentID: string,
    reactionType: string,
    collectionKey: string,
    anonIdentity?: AnonIdentity,
    fileID?: number,
): Promise<string> => {
    const identity = anonIdentity ?? getStoredAnonIdentity(collectionID);
    if (!identity) {
        throw new Error("No anonymous identity available");
    }

    const { encryptedData: cipher, nonce } = await encryptBox(
        new TextEncoder().encode(padReaction(reactionType)),
        collectionKey,
    );

    const res = await fetch(await apiURL("/public-collection/reactions"), {
        method: "POST",
        headers: {
            ...authenticatedPublicAlbumsRequestHeaders(credentials),
            "Content-Type": "application/json",
        },
        body: JSON.stringify({
            commentID,
            fileID,
            cipher,
            nonce,
            anonUserID: identity.anonUserID,
            anonToken: identity.token,
        }),
    });
    ensureOk(res);
    const { id } = UpsertReactionResponse.parse(await res.json());
    return id;
};

export const deletePublicReaction = async (
    credentials: PublicAlbumsCredentials,
    collectionID: number,
    reactionID: string,
    anonIdentity?: AnonIdentity,
): Promise<void> => {
    const identity = anonIdentity ?? getStoredAnonIdentity(collectionID);
    if (!identity) {
        throw new Error("No anonymous identity available");
    }

    const res = await fetch(
        await apiURL(`/public-collection/reactions/${reactionID}`),
        {
            method: "DELETE",
            headers: {
                ...authenticatedPublicAlbumsRequestHeaders(credentials),
                "Content-Type": "application/json",
            },
            body: JSON.stringify({
                anonUserID: identity.anonUserID,
                anonToken: identity.token,
            }),
        },
    );
    ensureOk(res);
};

const UpsertReactionResponse = z.object({ id: z.string() });

export interface PublicReaction {
    id: string;
    fileID: number;
    commentID?: string;
    reactionType: string;
    userID: number;
    anonUserID?: string;
    isDeleted: boolean;
    createdAt: number;
    updatedAt: number;
}

const RemotePublicReaction = z.object({
    id: z.string(),
    collectionID: z.number(),
    fileID: z.number().nullish(),
    commentID: z.string().nullish(),
    userID: z.number(),
    anonUserID: z.string().nullish(),
    cipher: z.string().nullish(),
    nonce: z.string().nullish(),
    isDeleted: z.boolean(),
    createdAt: z.number(),
    updatedAt: z.number(),
});

export interface AnonProfile {
    anonUserID: string;
    userName: string;
}

export const getPublicAnonProfiles = async (
    credentials: PublicAlbumsCredentials,
    collectionKey: string,
): Promise<Map<string, string>> => {
    const res = await fetch(await apiURL("/public-collection/anon-profiles"), {
        headers: authenticatedPublicAlbumsRequestHeaders(credentials),
    });
    ensureOk(res);
    const { profiles } = GetAnonProfilesResponse.parse(await res.json());

    const anonUserNames = new Map<string, string>();
    for (const profile of profiles) {
        if (!profile.cipher || !profile.nonce) continue;
        try {
            const decryptedB64 = await decryptBox(
                { encryptedData: profile.cipher, nonce: profile.nonce },
                collectionKey,
            );
            const userName = new TextDecoder().decode(
                Uint8Array.from(atob(decryptedB64), (c) => c.charCodeAt(0)),
            );
            if (userName) {
                anonUserNames.set(profile.anonUserID, userName);
            }
        } catch (e) {
            log.error(
                `Failed to decrypt public album profile ${profile.anonUserID}`,
                e,
            );
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

export interface Participant {
    userID: number;
    emailMasked: string;
}

export const getPublicParticipantsMaskedEmails = async (
    credentials: PublicAlbumsCredentials,
): Promise<Map<number, string>> => {
    const res = await fetch(
        await apiURL("/public-collection/participants/masked-emails"),
        { headers: authenticatedPublicAlbumsRequestHeaders(credentials) },
    );
    ensureOk(res);
    const { participants } = GetParticipantsResponse.parse(await res.json());

    const userIDToEmail = new Map<number, string>();
    for (const participant of participants) {
        userIDToEmail.set(participant.userID, participant.emailMasked);
    }
    return userIDToEmail;
};

const RemoteParticipant = z.object({
    userID: z.number(),
    emailMasked: z.string(),
});

const GetParticipantsResponse = z.object({
    participants: z.array(RemoteParticipant),
});

export interface PublicComment {
    id: string;
    collectionID: number;
    fileID?: number;
    parentCommentID?: string;
    userID: number;
    anonUserID?: string;
    text: string;
    isDeleted: boolean;
    createdAt: number;
    updatedAt: number;
}

export interface PublicSocialDiff {
    comments: PublicComment[];
    reactions: PublicReaction[];
}

export const getPublicSocialDiff = async (
    credentials: PublicAlbumsCredentials,
    fileID: number,
    collectionKey: string,
): Promise<PublicSocialDiff> => {
    const res = await fetch(
        await apiURL("/public-collection/social/diff", {
            fileID,
            sinceTime: 0,
            limit: 1000,
        }),
        { headers: authenticatedPublicAlbumsRequestHeaders(credentials) },
    );
    ensureOk(res);
    const data = GetPublicSocialDiffResponse.parse(await res.json());

    const comments: PublicComment[] = [];
    for (const comment of data.comments) {
        if (comment.isDeleted || !comment.cipher || !comment.nonce) {
            comments.push({
                id: comment.id,
                collectionID: comment.collectionID,
                fileID: comment.fileID ?? undefined,
                parentCommentID: comment.parentCommentID ?? undefined,
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
            const decryptedB64 = await decryptBox(
                { encryptedData: comment.cipher, nonce: comment.nonce },
                collectionKey,
            );
            const text = new TextDecoder().decode(
                Uint8Array.from(atob(decryptedB64), (c) => c.charCodeAt(0)),
            );
            comments.push({
                id: comment.id,
                collectionID: comment.collectionID,
                fileID: comment.fileID ?? undefined,
                parentCommentID: comment.parentCommentID ?? undefined,
                userID: comment.userID,
                anonUserID: comment.anonUserID ?? undefined,
                text,
                isDeleted: comment.isDeleted,
                createdAt: comment.createdAt,
                updatedAt: comment.updatedAt,
            });
        } catch (e) {
            log.error(
                `Failed to decrypt public album comment ${comment.id}`,
                e,
            );
        }
    }

    const reactions: PublicReaction[] = [];
    for (const reaction of data.reactions) {
        if (reaction.isDeleted || !reaction.cipher || !reaction.nonce) continue;
        try {
            const decryptedB64 = await decryptBox(
                { encryptedData: reaction.cipher, nonce: reaction.nonce },
                collectionKey,
            );
            const reactionType = unpadReaction(
                new TextDecoder().decode(
                    Uint8Array.from(atob(decryptedB64), (c) => c.charCodeAt(0)),
                ),
            );
            reactions.push({
                id: reaction.id,
                fileID: reaction.fileID ?? fileID,
                commentID: reaction.commentID ?? undefined,
                reactionType,
                userID: reaction.userID,
                anonUserID: reaction.anonUserID ?? undefined,
                isDeleted: reaction.isDeleted,
                createdAt: reaction.createdAt,
                updatedAt: reaction.updatedAt,
            });
        } catch (e) {
            log.error(
                `Failed to decrypt public album reaction ${reaction.id}`,
                e,
            );
        }
    }

    return { comments, reactions };
};

const RemotePublicComment = z.object({
    id: z.string(),
    collectionID: z.number(),
    fileID: z.number().nullish(),
    parentCommentID: z.string().nullish(),
    userID: z.number(),
    anonUserID: z.string().nullish(),
    cipher: z.string().nullish(),
    nonce: z.string().nullish(),
    isDeleted: z.boolean(),
    createdAt: z.number(),
    updatedAt: z.number(),
});

const GetPublicSocialDiffResponse = z.object({
    comments: z.array(RemotePublicComment),
    reactions: z.array(RemotePublicReaction),
    hasMoreComments: z.boolean(),
    hasMoreReactions: z.boolean(),
});

export interface PublicFeedComment extends PublicComment {
    isReply: boolean;
}

export interface PublicFeedReaction extends PublicReaction {
    isCommentReply?: boolean;
}

export interface PublicAlbumFeed {
    comments: PublicFeedComment[];
    reactions: PublicFeedReaction[];
}

export const getPublicAlbumFeed = async (
    credentials: PublicAlbumsCredentials,
    collectionKey: string,
): Promise<PublicAlbumFeed> => {
    const res = await fetch(
        await apiURL("/public-collection/social/diff", {
            sinceTime: 0,
            limit: 1000,
        }),
        { headers: authenticatedPublicAlbumsRequestHeaders(credentials) },
    );
    ensureOk(res);
    const data = GetPublicSocialDiffResponse.parse(await res.json());

    const commentParentMap = new Map<string, boolean>();

    const comments: PublicFeedComment[] = [];
    for (const comment of data.comments) {
        const isReply = !!comment.parentCommentID;
        commentParentMap.set(comment.id, isReply);

        if (comment.isDeleted || !comment.cipher || !comment.nonce) {
            comments.push({
                id: comment.id,
                collectionID: comment.collectionID,
                fileID: comment.fileID ?? undefined,
                parentCommentID: comment.parentCommentID ?? undefined,
                userID: comment.userID,
                anonUserID: comment.anonUserID ?? undefined,
                text: "",
                isDeleted: comment.isDeleted,
                createdAt: comment.createdAt,
                updatedAt: comment.updatedAt,
                isReply,
            });
            continue;
        }
        try {
            const decryptedB64 = await decryptBox(
                { encryptedData: comment.cipher, nonce: comment.nonce },
                collectionKey,
            );
            const text = new TextDecoder().decode(
                Uint8Array.from(atob(decryptedB64), (c) => c.charCodeAt(0)),
            );
            comments.push({
                id: comment.id,
                collectionID: comment.collectionID,
                fileID: comment.fileID ?? undefined,
                parentCommentID: comment.parentCommentID ?? undefined,
                userID: comment.userID,
                anonUserID: comment.anonUserID ?? undefined,
                text,
                isDeleted: comment.isDeleted,
                createdAt: comment.createdAt,
                updatedAt: comment.updatedAt,
                isReply,
            });
        } catch (e) {
            log.error(
                `Failed to decrypt public album comment ${comment.id}`,
                e,
            );
        }
    }

    const reactions: PublicFeedReaction[] = [];
    for (const reaction of data.reactions) {
        if (reaction.isDeleted || !reaction.cipher || !reaction.nonce) continue;
        try {
            const decryptedB64 = await decryptBox(
                { encryptedData: reaction.cipher, nonce: reaction.nonce },
                collectionKey,
            );
            const reactionType = unpadReaction(
                new TextDecoder().decode(
                    Uint8Array.from(atob(decryptedB64), (c) => c.charCodeAt(0)),
                ),
            );

            let isCommentReply: boolean | undefined;
            if (reaction.commentID) {
                isCommentReply = commentParentMap.get(reaction.commentID);
            }

            reactions.push({
                id: reaction.id,
                fileID: reaction.fileID ?? 0,
                commentID: reaction.commentID ?? undefined,
                isCommentReply,
                reactionType,
                userID: reaction.userID,
                anonUserID: reaction.anonUserID ?? undefined,
                isDeleted: reaction.isDeleted,
                createdAt: reaction.createdAt,
                updatedAt: reaction.updatedAt,
            });
        } catch (e) {
            log.error(
                `Failed to decrypt public album reaction ${reaction.id}`,
                e,
            );
        }
    }

    return { comments, reactions };
};
