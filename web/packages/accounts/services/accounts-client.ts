import { clientPackageName, desktopAppVersion, isDesktop } from "ente-base/app";
import { namedError } from "ente-base/error";
import { apiOrigin } from "ente-base/origins";
import { createAccountsClient, type AccountsClient } from "ente-prelogin-wasm";

let current: { origin: string; client: Promise<AccountsClient> } | undefined;

export const getAccountsClient = async () => {
    const origin = await apiOrigin();
    if (current?.origin !== origin) {
        const client = createAccountsClient({
            origin,
            clientPackage: clientPackageName,
            ...(isDesktop && { clientVersion: desktopAppVersion }),
        }).catch((error: unknown) => {
            if (current?.client === client) current = undefined;
            throw error;
        });
        current = { origin, client };
    }
    return current.client;
};

export const withAccountsClient = async <T>(
    operation: (client: AccountsClient) => Promise<T>,
): Promise<T> => {
    const client = await getAccountsClient();
    const result = await operation(client);
    if (client !== (await getAccountsClient())) {
        throw namedError("session_expired", "Authentication session changed");
    }
    return result;
};

export const clearAccountsClient = () => {
    current = undefined;
};
