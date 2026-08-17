import { ensureSavedKeyAttributes } from "ente-accounts/services/user";
import { boxSealOpenBytes, decryptBox } from "ente-base/crypto";
import type { KeyPair } from "ente-base/crypto/types";
import { authenticatedRequestHeaders, ensureOk } from "ente-base/http";
import { apiURL } from "ente-base/origins";
import { ensureMasterKeyFromSession } from "ente-base/session";
import { nullToUndefined } from "ente-utils/transform";
import { z } from "zod";

export const ensureUserKeyPair = async (): Promise<KeyPair> => {
    const { encryptedSecretKey, secretKeyDecryptionNonce, publicKey } =
        ensureSavedKeyAttributes();
    const privateKey = await decryptBox(
        { encryptedData: encryptedSecretKey, nonce: secretKeyDecryptionNonce },
        await ensureMasterKeyFromSession(),
    );
    return { publicKey, privateKey };
};

export const getPublicKey = async (email: string) => {
    const res = await fetch(await apiURL("/users/public-key", { email }), {
        headers: await authenticatedRequestHeaders(),
    });
    ensureOk(res);
    return z.object({ publicKey: z.string() }).parse(await res.json())
        .publicKey;
};

export const get2FAStatus = async () => {
    const res = await fetch(await apiURL("/users/two-factor/status"), {
        headers: await authenticatedRequestHeaders(),
    });
    ensureOk(res);
    return z.object({ status: z.boolean() }).parse(await res.json()).status;
};

export const disable2FA = async () =>
    ensureOk(
        await fetch(await apiURL("/users/two-factor/disable"), {
            method: "POST",
            headers: await authenticatedRequestHeaders(),
        }),
    );

const DeleteChallengeResponse = z.object({
    allowDelete: z.boolean(),
    encryptedChallenge: z.string().nullish().transform(nullToUndefined),
});

export interface AccountDeletionSummary {
    photosAndVideosCount: number;
    authenticatorCodesCount: number;
    lockerRecordsCount: number;
}

const AccountDeletionSummary = z.object({
    photosAndVideosCount: z.number().int(),
    authenticatorCodesCount: z.number().int(),
    lockerRecordsCount: z.number().int(),
});

export const getAccountDeletionSummary =
    async (): Promise<AccountDeletionSummary> => {
        const res = await fetch(await apiURL("/users/deletion-summary"), {
            headers: await authenticatedRequestHeaders(),
        });
        ensureOk(res);
        return AccountDeletionSummary.parse(await res.json());
    };

export const getAccountDeleteChallenge = async () => {
    const res = await fetch(await apiURL("/users/delete-challenge"), {
        headers: await authenticatedRequestHeaders(),
    });
    ensureOk(res);
    return DeleteChallengeResponse.parse(await res.json());
};

export const decryptDeleteAccountChallenge = async (
    encryptedChallenge: string,
) =>
    new TextDecoder().decode(
        await boxSealOpenBytes(encryptedChallenge, await ensureUserKeyPair()),
    );

export const deleteAccount = async (
    challenge: string,
    reason: string,
    feedback: string,
) =>
    ensureOk(
        await fetch(await apiURL("/users/delete"), {
            method: "DELETE",
            headers: await authenticatedRequestHeaders(),
            body: JSON.stringify({ challenge, reason, feedback }),
        }),
    );
