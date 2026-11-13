import { encryptBox } from "ente-base/crypto";
import { authenticatedRequestHeaders, ensureOk } from "ente-base/http";
import { apiURL } from "ente-base/origins";
import { z } from "zod";

export interface Comment {
    id: string;
    collectionID: number;
    fileID?: number;
    parentCommentID?: string;
    // Only present in feed responses.
    parentCommentUserID?: number;
    userID: number;
    anonUserID?: string;
    text: string;
    isDeleted: boolean;
    createdAt: number;
    updatedAt: number;
}

export const addComment = async (
    collectionID: number,
    fileID: number,
    text: string,
    collectionKey: string,
    parentCommentID?: string,
): Promise<string> => {
    const { encryptedData: cipher, nonce } = await encryptBox(
        new TextEncoder().encode(text),
        collectionKey,
    );

    const res = await fetch(await apiURL("/comments"), {
        method: "POST",
        headers: {
            ...(await authenticatedRequestHeaders()),
            "Content-Type": "application/json",
        },
        body: JSON.stringify({
            collectionID,
            fileID,
            cipher,
            nonce,
            parentCommentID,
        }),
    });
    ensureOk(res);
    const { id } = CreateCommentResponse.parse(await res.json());
    return id;
};

export const deleteComment = async (commentID: string): Promise<void> => {
    const res = await fetch(await apiURL(`/comments/${commentID}`), {
        method: "DELETE",
        headers: await authenticatedRequestHeaders(),
    });
    ensureOk(res);
};

const CreateCommentResponse = z.object({ id: z.string() });
