// Adapted from `web/packages/accounts/services/srp.ts` (login path only).
import { z } from "zod";
import { createSRPSession, deriveSRPLoginKey } from "./crypto";
import { ensureOk, publicRequestHeaders } from "./http";
import type { EmailOrSRPVerificationResponseShape } from "./keys";
import { RemoteSRPVerificationResponse } from "./keys";
import { apiURL } from "./origins";

export interface SRPAttributes {
    srpUserID: string;
    srpSalt: string;
    memLimit: number;
    opsLimit: number;
    kekSalt: string;
    isEmailMFAEnabled: boolean;
}

export const RemoteSRPAttributes = z.object({
    srpUserID: z.string(),
    srpSalt: z.string(),
    memLimit: z.number(),
    opsLimit: z.number(),
    kekSalt: z.string(),
    isEmailMFAEnabled: z.boolean(),
});

export const getSRPAttributes = async (
    email: string,
): Promise<SRPAttributes | undefined> => {
    const res = await fetch(await apiURL("/users/srp/attributes", { email }), {
        headers: publicRequestHeaders(),
    });
    if (res.status == 404) return undefined;
    ensureOk(res);
    return z.object({ attributes: RemoteSRPAttributes }).parse(await res.json())
        .attributes;
};

// Verifies the derived KEK against the SRP verifier, returning either the
// account's key attributes + auth token, or a second-factor session handle.
export const verifySRP = async (
    { srpUserID, srpSalt }: SRPAttributes,
    kek: string,
): Promise<EmailOrSRPVerificationResponseShape> => {
    const session = await createSRPSession(
        srpSalt,
        srpUserID,
        await deriveSRPLoginKey(kek),
    );

    const { srpB, sessionID } = await createSRPSessionOnRemote({
        srpUserID,
        srpA: session.publicA(),
    });

    const { srpM2, ...rest } = await verifySRPSession({
        sessionID,
        srpUserID,
        srpM1: session.computeM1(srpB),
    });

    session.verifyM2(srpM2);

    return rest;
};

const CreateSRPSessionResponse = z.object({
    sessionID: z.string(),
    srpB: z.string(),
});

const createSRPSessionOnRemote = async ({
    srpUserID,
    srpA,
}: {
    srpUserID: string;
    srpA: string;
}): Promise<z.infer<typeof CreateSRPSessionResponse>> => {
    const res = await fetch(await apiURL("/users/srp/create-session"), {
        method: "POST",
        headers: publicRequestHeaders(),
        body: JSON.stringify({ srpUserID, srpA }),
    });
    ensureOk(res);
    return CreateSRPSessionResponse.parse(await res.json());
};

const verifySRPSession = async ({
    sessionID,
    srpUserID,
    srpM1,
}: {
    sessionID: string;
    srpUserID: string;
    srpM1: string;
}) => {
    const res = await fetch(await apiURL("/users/srp/verify-session"), {
        method: "POST",
        headers: publicRequestHeaders(),
        body: JSON.stringify({ sessionID, srpUserID, srpM1 }),
    });
    if (res.status == 401) {
        throw new SRPVerificationError();
    }
    ensureOk(res);
    return RemoteSRPVerificationResponse.parse(await res.json());
};

export class SRPVerificationError extends Error {
    constructor() {
        super("Incorrect password or no account");
        this.name = "SRPVerificationError";
    }
}
