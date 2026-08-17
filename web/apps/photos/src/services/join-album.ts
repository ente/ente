import { savedKeyAttributes } from "ente-accounts/services/accounts-db";
import { boxSeal, fromB64 } from "ente-base/crypto";
import { authenticatedRequestHeaders } from "ente-base/http";
import {
    clearJoinAlbumContext,
    getJoinAlbumContext,
} from "ente-base/join-album";
import log from "ente-base/log";
import { apiURL } from "ente-base/origins";

// libsodium secretbox keys are 32 bytes.
const collectionKeyBytes = 32;

const joinPublicAlbum = async (
    accessToken: string,
    collectionID: number,
    encryptedKey: string,
    accessTokenJWT?: string,
): Promise<void> => {
    const authHeaders = await authenticatedRequestHeaders();
    const url = await apiURL("/collections/join-link");

    const headers = {
        "Content-Type": "application/json",
        ...authHeaders,
        "X-Auth-Access-Token": accessToken,
        ...(accessTokenJWT && { "X-Auth-Access-Token-JWT": accessTokenJWT }),
    };

    const response = await fetch(url, {
        method: "POST",
        headers,
        body: JSON.stringify({ collectionID, encryptedKey }),
    });

    if (!response.ok) {
        log.error("Album join API failed", {
            collectionID,
            status: response.status,
        });
        let errorMessage = `Failed to join album (status: ${response.status})`;
        try {
            const errorData = (await response.json()) as {
                message?: string;
                code?: string;
            };
            errorMessage = errorData.message ?? errorMessage;
        } catch {
            // Ignore parse error, use default message
        }
        throw new Error(errorMessage);
    }
};

export const processPendingAlbumJoin = async (): Promise<number | null> => {
    const context = getJoinAlbumContext();

    if (!context) {
        return null;
    }

    try {
        const collectionID = context.collectionID;

        const keyAttributes = savedKeyAttributes();
        if (!keyAttributes) {
            throw new Error(
                "Key attributes not found. Please try logging in again.",
            );
        }

        const publicKey = keyAttributes.publicKey;

        const collectionKeyBytes_ = await fromB64(context.collectionKey);
        if (collectionKeyBytes_.length !== collectionKeyBytes) {
            log.warn("Invalid collection key length in join album context");
            clearJoinAlbumContext();
            return null;
        }

        // boxSeal accepts the already-base64 collection key.
        const encryptedKey = await boxSeal(context.collectionKey, publicKey);

        await joinPublicAlbum(
            context.accessToken,
            collectionID,
            encryptedKey,
            context.accessTokenJWT,
        );

        clearJoinAlbumContext();

        return collectionID;
    } catch (error) {
        // Do not retry a failed join on every login.
        clearJoinAlbumContext();
        log.error("Failed to process pending album join", {
            collectionID: context.collectionID,
            error,
        });
        throw error;
    }
};
