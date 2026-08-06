import { encryptBox } from "ente-base/crypto";
import {
    authenticatedPublicAlbumsRequestHeaders,
    ensureOk,
    type PublicAlbumsCredentials,
} from "ente-base/http";
import { apiURL } from "ente-base/origins";
import { z } from "zod";
import { type AnonIdentity, getStoredAnonIdentity } from "./public-reaction";

export const addPublicComment = async (
    credentials: PublicAlbumsCredentials,
    collectionID: number,
    fileID: number,
    text: string,
    collectionKey: string,
    parentCommentID?: string,
    anonIdentity?: AnonIdentity,
): Promise<string> => {
    const identity = anonIdentity ?? getStoredAnonIdentity(collectionID);
    if (!identity) {
        throw new Error("No anonymous identity available");
    }

    const { encryptedData: cipher, nonce } = await encryptBox(
        new TextEncoder().encode(text),
        collectionKey,
    );

    const res = await fetch(await apiURL("/public-collection/comments"), {
        method: "POST",
        headers: {
            ...authenticatedPublicAlbumsRequestHeaders(credentials),
            "Content-Type": "application/json",
        },
        body: JSON.stringify({
            fileID,
            cipher,
            nonce,
            parentCommentID,
            anonUserID: identity.anonUserID,
            anonToken: identity.token,
        }),
    });
    ensureOk(res);
    const { id } = CreateCommentResponse.parse(await res.json());
    return id;
};

export const deletePublicComment = async (
    credentials: PublicAlbumsCredentials,
    collectionID: number,
    commentID: string,
    anonIdentity?: AnonIdentity,
): Promise<void> => {
    const identity = anonIdentity ?? getStoredAnonIdentity(collectionID);
    if (!identity) {
        throw new Error("No anonymous identity available");
    }

    const res = await fetch(
        await apiURL(`/public-collection/comments/${commentID}`),
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

const CreateCommentResponse = z.object({ id: z.string() });
