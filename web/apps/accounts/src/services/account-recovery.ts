import { ensureOk, HTTPError, publicRequestHeaders } from "ente-base/http";
import { apiURL } from "ente-base/origins";
import { z } from "zod";

const AccountRecoveryResponse = z.object({
    status: z.enum(["ready", "recovered"]),
});

export type AccountRecoveryResponse = z.infer<typeof AccountRecoveryResponse>;

const AccountRecoveryErrorCode = z.enum([
    "ACCOUNT_RECOVERY_INVALID_LINK",
    "ACCOUNT_RECOVERY_LINK_EXPIRED",
    "ACCOUNT_RECOVERY_EMAIL_IN_USE",
    "ACCOUNT_RECOVERY_UNAVAILABLE",
]);

export type AccountRecoveryErrorCode = z.infer<typeof AccountRecoveryErrorCode>;

const postAccountRecoveryToken = async (path: string, token: string) => {
    const res = await fetch(await apiURL(path), {
        method: "POST",
        headers: {
            ...publicRequestHeaders(),
            "Content-Type": "application/json",
        },
        body: JSON.stringify({ token }),
    });
    ensureOk(res);
    return AccountRecoveryResponse.parse(await res.json());
};

export const validateAccountRecovery = (token: string) =>
    postAccountRecoveryToken("/users/recover-account/validate", token);

export const recoverAccount = (token: string) =>
    postAccountRecoveryToken("/users/recover-account", token);

export const accountRecoveryErrorCode = async (error: unknown) => {
    if (!(error instanceof HTTPError)) return undefined;

    try {
        const payload = z
            .object({ code: AccountRecoveryErrorCode })
            .parse(await error.res.clone().json());
        return payload.code;
    } catch {
        return undefined;
    }
};
