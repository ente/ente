import { encryptBox } from "ente-base/crypto";
import { authenticatedRequestHeaders, ensureOk } from "ente-base/http";
import { apiURL } from "ente-base/origins";
import { z } from "zod";

// Pad every reaction before encryption so its ciphertext does not reveal its
// length. Emoji names are currently at most about 70 characters.
const paddedReactionLength = 100;

const padReaction = (reactionType: string): string =>
    reactionType.padEnd(paddedReactionLength, "\0");

export const addReaction = async (
    collectionID: number,
    fileID: number,
    reactionType: string,
    collectionKey: string,
): Promise<string> => {
    const { encryptedData: cipher, nonce } = await encryptBox(
        new TextEncoder().encode(padReaction(reactionType)),
        collectionKey,
    );

    const res = await fetch(await apiURL("/reactions"), {
        method: "PUT",
        headers: {
            ...(await authenticatedRequestHeaders()),
            "Content-Type": "application/json",
        },
        body: JSON.stringify({ collectionID, fileID, cipher, nonce }),
    });
    ensureOk(res);
    const { id } = UpsertReactionResponse.parse(await res.json());
    return id;
};

// fileID is required for file-scoped comments.
export const addCommentReaction = async (
    collectionID: number,
    commentID: string,
    reactionType: string,
    collectionKey: string,
    fileID?: number,
): Promise<string> => {
    const { encryptedData: cipher, nonce } = await encryptBox(
        new TextEncoder().encode(padReaction(reactionType)),
        collectionKey,
    );

    const res = await fetch(await apiURL("/reactions"), {
        method: "PUT",
        headers: {
            ...(await authenticatedRequestHeaders()),
            "Content-Type": "application/json",
        },
        body: JSON.stringify({
            collectionID,
            commentID,
            fileID,
            cipher,
            nonce,
        }),
    });
    ensureOk(res);
    const { id } = UpsertReactionResponse.parse(await res.json());
    return id;
};

const UpsertReactionResponse = z.object({ id: z.string() });

export const deleteReaction = async (reactionID: string): Promise<void> => {
    const res = await fetch(await apiURL(`/reactions/${reactionID}`), {
        method: "DELETE",
        headers: await authenticatedRequestHeaders(),
    });
    ensureOk(res);
};
