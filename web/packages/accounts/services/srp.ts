import { isNamedError } from "ente-base/error";
import { ensureAuthToken } from "ente-base/token";
import {
    generateSRPSetup,
    completeSignup as rustCompleteSignup,
    getSRPAttributes as rustGetSRPAttributes,
    setupSRP as rustSetupSRP,
    verifySRP as rustVerifySRP,
} from "ente-prelogin-wasm";
import { ensure } from "ente-utils/ensure";
import { v4 as uuidv4 } from "uuid";
import { z } from "zod";
import { withAccountsClient } from "./accounts-client";
import {
    savedOriginalKeyAttributes,
    saveSRPAttributes,
    unstashAfterUseSRPSetupAttributes,
} from "./accounts-db";
import {
    RemoteEmailOrSRPVerificationResponse,
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
    try {
        return RemoteSRPAttributes.parse(
            await withAccountsClient((client) =>
                rustGetSRPAttributes(client, email),
            ),
        );
    } catch (error) {
        if (isNamedError(error, "srp_not_configured")) return undefined;
        throw error;
    }
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
): Promise<SRPSetupAttributes> => generateSRPSetup(kek, uuidv4());

export const setupSRP = async (srpSetupAttributes: SRPSetupAttributes) => {
    const token = await ensureAuthToken();
    return withAccountsClient((client) =>
        rustSetupSRP(client, token, srpSetupAttributes),
    );
};

export const completePendingSignup = async (email: string, token: string) => {
    const attributes = savedOriginalKeyAttributes();
    if (!attributes) return;
    await unstashAfterUseSRPSetupAttributes(async (setup) => {
        saveSRPAttributes(
            RemoteSRPAttributes.parse(
                await withAccountsClient((client) =>
                    rustCompleteSignup(client, email, token, attributes, setup),
                ),
            ),
        );
    });
};

export const getAndSaveSRPAttributes = async (userEmail: string) =>
    saveSRPAttributes(ensure(await getSRPAttributes(userEmail)));

export const verifySRP = async (
    attributes: SRPAttributes,
    kek: string,
): Promise<EmailOrSRPVerificationResponse> =>
    RemoteEmailOrSRPVerificationResponse.parse(
        await withAccountsClient((client) =>
            rustVerifySRP(client, attributes, kek),
        ),
    );
