import { expose } from "comlink";
import { logUnhandledErrorsAndRejectionsInWorker } from "ente-base/log-web";
import { ensureAuthToken } from "ente-base/token";
import { changePassword } from "ente-prelogin-wasm";
import { withAccountsClient } from "./accounts-client";
import { generateInteractiveKeyAttributes } from "./key-attributes";
import { RemoteKeyAttributes, type KeyAttributes } from "./user";

export class PasswordWorker {
    async changePassword(
        password: string,
        masterKey: string,
        keyAttributes: KeyAttributes,
    ) {
        const interactiveKeyAttributes = await generateInteractiveKeyAttributes(
            password,
            keyAttributes,
            masterKey,
        );
        const token = await ensureAuthToken();
        const response = await withAccountsClient((client) =>
            changePassword(client, token, password, masterKey, keyAttributes),
        );
        return {
            interactiveKeyAttributes,
            remoteKeyAttributes: RemoteKeyAttributes.parse(response),
        };
    }
}

expose(PasswordWorker);

logUnhandledErrorsAndRejectionsInWorker();
