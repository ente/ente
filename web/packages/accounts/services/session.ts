import {
    savedOriginalKeyAttributes,
    savedSRPAttributes,
    saveSRPAttributes,
} from "ente-accounts/services/accounts-db";
import { isNamedError } from "ente-base/error";
import log from "ente-base/log";
import { ensureAuthToken, savedAuthToken } from "ente-base/token";
import {
    getSessionValidity,
    checkSessionValidity as rustCheckSessionValidity,
} from "ente-prelogin-wasm";
import { nullToUndefined } from "ente-utils/transform";
import { z } from "zod";
import { withAccountsClient } from "./accounts-client";
import { RemoteSRPAttributes } from "./srp";
import {
    ensureLocalUser,
    putUserKeyAttributes,
    RemoteKeyAttributes,
} from "./user";

const SessionValidity = z.discriminatedUnion("status", [
    z.object({ status: z.literal("invalid") }),
    z.object({ status: z.literal("valid") }),
    z.object({
        status: z.literal("validButPasswordChanged"),
        updatedKeyAttributes: RemoteKeyAttributes,
        updatedSRPAttributes: RemoteSRPAttributes,
    }),
]);

const SessionValidityResponse = z.object({
    hasSetKeys: z.boolean(),
    keyAttributes: RemoteKeyAttributes.nullish().transform(nullToUndefined),
});

export const checkSessionValidity = async () => {
    const token = await ensureAuthToken();
    const localSRPAttributes = savedSRPAttributes();
    const originalKeyAttributes = savedOriginalKeyAttributes();
    const result = SessionValidity.parse(
        await withAccountsClient((client) =>
            rustCheckSessionValidity(
                client,
                token,
                ensureLocalUser().email,
                localSRPAttributes,
            ),
        ),
    );
    if (
        result.status === "validButPasswordChanged" &&
        result.updatedSRPAttributes.kekSalt === originalKeyAttributes?.kekSalt
    ) {
        saveSRPAttributes(result.updatedSRPAttributes);
        return { status: "valid" as const };
    }
    return result;
};

export const isSessionInvalid = async (): Promise<boolean> => {
    const token = await savedAuthToken();
    if (!token) {
        return true;
    }

    try {
        const { hasSetKeys } = SessionValidityResponse.parse(
            await withAccountsClient((client) =>
                getSessionValidity(client, token),
            ),
        );
        if (!hasSetKeys) {
            const originalKeyAttributes = savedOriginalKeyAttributes();
            if (originalKeyAttributes)
                await putUserKeyAttributes(originalKeyAttributes);
        }
    } catch (e) {
        if (isNamedError(e, "session_invalid")) return true;
        log.warn("Failed to check session validity", e);
        // Returning true would log the user out, so do not do that on
        // potentially transient errors.
        return false;
    }

    return false;
};
