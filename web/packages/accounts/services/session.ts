import {
    savedOriginalKeyAttributes,
    savedSRPAttributes,
} from "ente-accounts/services/accounts-db";
import type { KeyAttributes } from "ente-accounts/services/user";
import { authenticatedRequestHeaders, HTTPError } from "ente-base/http";
import log from "ente-base/log";
import { apiURL } from "ente-base/origins";
import { savedAuthToken } from "ente-base/token";
import { nullToUndefined } from "ente-utils/transform";
import { z } from "zod";
import { getSRPAttributes, type SRPAttributes } from "./srp";
import {
    ensureLocalUser,
    putUserKeyAttributes,
    RemoteKeyAttributes,
} from "./user";

type SessionValidity =
    | { status: "invalid" }
    | { status: "valid" }
    | {
          status: "validButPasswordChanged";
          updatedKeyAttributes: KeyAttributes;
          updatedSRPAttributes: SRPAttributes;
      };

const SessionValidityResponse = z.object({
    hasSetKeys: z.boolean(),
    keyAttributes: RemoteKeyAttributes.nullish().transform(nullToUndefined),
});

export const checkSessionValidity = async (): Promise<SessionValidity> => {
    const res = await fetch(await apiURL("/users/session-validity/v2"), {
        headers: await authenticatedRequestHeaders(),
    });
    if (!res.ok) {
        if (res.status == 401) return { status: "invalid" };
        else throw new HTTPError(res);
    }

    const { keyAttributes } = SessionValidityResponse.parse(await res.json());
    if (keyAttributes) {
        const remoteKeyAttributes = keyAttributes;

        // We should have these values locally if we reach here.
        const email = ensureLocalUser().email;
        const localSRPAttributes = savedSRPAttributes()!;

        // The key attributes we have saved locally are regenerated locally
        // for interactive usage and thus always differ from the remote ones,
        // so they cannot be compared to detect a password change. The SRP
        // attributes can be: they match remote when the password is the same.
        const remoteSRPAttributes = await getSRPAttributes(email);

        if (remoteSRPAttributes) {
            // The kekSalt changes when a new password is set, so it serves as
            // a proxy for comparing the entire SRP attributes object.
            if (remoteSRPAttributes.kekSalt != localSRPAttributes.kekSalt) {
                return {
                    status: "validButPasswordChanged",
                    updatedKeyAttributes: remoteKeyAttributes,
                    updatedSRPAttributes: remoteSRPAttributes,
                };
            }
        }
    }

    return { status: "valid" };
};

export const isSessionInvalid = async (): Promise<boolean> => {
    const token = await savedAuthToken();
    if (!token) {
        return true;
    }

    try {
        const res = await fetch(await apiURL("/users/session-validity/v2"), {
            headers: await authenticatedRequestHeaders(),
        });
        if (!res.ok) {
            if (res.status == 401) return true;
            else throw new HTTPError(res);
        }

        const { hasSetKeys } = SessionValidityResponse.parse(await res.json());
        if (!hasSetKeys) {
            const originalKeyAttributes = savedOriginalKeyAttributes();
            if (originalKeyAttributes)
                await putUserKeyAttributes(originalKeyAttributes);
        }
    } catch (e) {
        log.warn("Failed to check session validity", e);
        // Returning true would log the user out, so do not do that on
        // potentially transient errors.
        return false;
    }

    return false;
};
