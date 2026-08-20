import {
    deriveSubKeyBytes,
    generateSRPSetupAttributesRust,
    toB64,
} from "ente-accounts/services/crypto";
import {
    authenticatedRequestHeaders,
    ensureOk,
    publicRequestHeaders,
} from "ente-base/http";
import { apiURL } from "ente-base/origins";
import { loadEnteWasm } from "ente-core-wasm/load";
import { ensure } from "ente-utils/ensure";
import { v4 as uuidv4 } from "uuid";
import { z } from "zod";
import { saveSRPAttributes } from "./accounts-db";
import {
    RemoteSRPVerificationResponse,
    type EmailOrSRPVerificationResponse,
} from "./user";

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

export const SRPSetupAttributes = z.object({
    srpUserID: z.string(),
    srpSalt: z.string(),
    srpVerifier: z.string(),
    loginSubKey: z.string(),
});

export type SRPSetupAttributes = z.infer<typeof SRPSetupAttributes>;

export const generateSRPSetupAttributes = async (
    kek: string,
): Promise<SRPSetupAttributes> => {
    const srpUserID = uuidv4();
    return {
        srpUserID,
        ...(await generateSRPSetupAttributesRust(kek, srpUserID)),
    };
};

export const setupSRP = async (srpSetupAttributes: SRPSetupAttributes) =>
    srpSetupOrReconfigure(srpSetupAttributes, completeSRPSetup);

type SRPSetupOrReconfigureExchangeCallback = ({
    setupID,
    srpM1,
}: {
    setupID: string;
    srpM1: string;
}) => Promise<{ srpM2: string }>;

const srpSetupOrReconfigure = async (
    { srpSalt, srpUserID, srpVerifier, loginSubKey }: SRPSetupAttributes,
    exchangeCB: SRPSetupOrReconfigureExchangeCallback,
) => {
    const session = await createSRPSession(srpSalt, srpUserID, loginSubKey);

    const { setupID, srpB } = await startSRPSetup({
        srpUserID,
        srpSalt,
        srpVerifier,
        srpA: session.public_a(),
    });

    const { srpM2 } = await exchangeCB({
        setupID,
        srpM1: session.compute_m1(srpB),
    });

    session.verify_m2(srpM2);
};

const createSRPSession = async (
    srpSalt: string,
    srpUserID: string,
    loginSubKey: string,
) => {
    const wasm = await loadEnteWasm();
    return new wasm.SrpSession(srpUserID, srpSalt, loginSubKey);
};

interface SetupSRPRequest {
    srpUserID: string;
    srpSalt: string;
    srpVerifier: string;
    srpA: string;
}

const SetupSRPResponse = z.object({ setupID: z.string(), srpB: z.string() });

const startSRPSetup = async (
    setupSRPRequest: SetupSRPRequest,
): Promise<z.infer<typeof SetupSRPResponse>> => {
    const res = await fetch(await apiURL("/users/srp/setup"), {
        method: "POST",
        headers: await authenticatedRequestHeaders(),
        body: JSON.stringify(setupSRPRequest),
    });
    ensureOk(res);
    return SetupSRPResponse.parse(await res.json());
};

const CompleteSRPSetupResponse = z.object({
    setupID: z.string(),
    srpM2: z.string(),
});

const completeSRPSetup = async ({
    setupID,
    srpM1,
}: {
    setupID: string;
    srpM1: string;
}) => {
    const res = await fetch(await apiURL("/users/srp/complete"), {
        method: "POST",
        headers: await authenticatedRequestHeaders(),
        body: JSON.stringify({ setupID, srpM1 }),
    });
    ensureOk(res);
    return CompleteSRPSetupResponse.parse(await res.json());
};

export const getAndSaveSRPAttributes = async (userEmail: string) =>
    saveSRPAttributes(ensure(await getSRPAttributes(userEmail)));

export interface UpdatedKeyAttr {
    kekSalt: string;
    encryptedKey: string;
    keyDecryptionNonce: string;
    opsLimit: number;
    memLimit: number;
}

export const updateSRPAndKeyAttributes = (
    srpSetupAttributes: SRPSetupAttributes,
    updatedKeyAttr: UpdatedKeyAttr,
) =>
    srpSetupOrReconfigure(srpSetupAttributes, ({ setupID, srpM1 }) =>
        updateSRPAndKeys({ setupID, srpM1, updatedKeyAttr }),
    );

interface UpdateSRPAndKeysRequest {
    setupID: string;
    srpM1: string;
    updatedKeyAttr: UpdatedKeyAttr;
    logOutOtherDevices?: boolean;
}

const UpdateSRPAndKeysResponse = z.object({
    srpM2: z.string(),
    setupID: z.string(),
});

const updateSRPAndKeys = async (
    updateSRPAndKeysRequest: UpdateSRPAndKeysRequest,
): Promise<z.infer<typeof UpdateSRPAndKeysResponse>> => {
    const res = await fetch(await apiURL("/users/srp/update"), {
        method: "POST",
        headers: await authenticatedRequestHeaders(),
        body: JSON.stringify(updateSRPAndKeysRequest),
    });
    ensureOk(res);
    return UpdateSRPAndKeysResponse.parse(await res.json());
};

export const srpVerificationUnauthorizedErrorMessage =
    "SRP verification failed (HTTP 401 Unauthorized)";

const deriveSRPLoginSubKey = async (kek: string) => {
    const kekSubKeyBytes = await deriveSubKeyBytes(kek, 32, 1, "loginctx");
    return toB64(kekSubKeyBytes.slice(0, 16));
};

export const verifySRP = async (
    { srpUserID, srpSalt }: SRPAttributes,
    kek: string,
): Promise<EmailOrSRPVerificationResponse> => {
    const session = await createSRPSession(
        srpSalt,
        srpUserID,
        await deriveSRPLoginSubKey(kek),
    );

    const { srpB, sessionID } = await createSRPSessionOnRemote({
        srpUserID,
        srpA: session.public_a(),
    });

    const { srpM2, ...rest } = await verifySRPSession({
        sessionID,
        srpUserID,
        srpM1: session.compute_m1(srpB),
    });

    session.verify_m2(srpM2);

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
}): Promise<z.infer<typeof RemoteSRPVerificationResponse>> => {
    const res = await fetch(await apiURL("/users/srp/verify-session"), {
        method: "POST",
        headers: publicRequestHeaders(),
        body: JSON.stringify({ sessionID, srpUserID, srpM1 }),
    });
    if (res.status == 401) {
        throw new Error(srpVerificationUnauthorizedErrorMessage);
    }
    ensureOk(res);
    return RemoteSRPVerificationResponse.parse(await res.json());
};
