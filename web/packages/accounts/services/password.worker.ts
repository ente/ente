import { expose } from "comlink";
import { logUnhandledErrorsAndRejectionsInWorker } from "ente-base/log-web";
import { deriveSensitiveKey, encryptBox } from "ente-prelogin-wasm";
import { ensure } from "ente-utils/ensure";
import { generateInteractiveKeyAttributes } from "./key-attributes";
import {
    generateSRPSetupAttributes,
    getSRPAttributes,
    updateSRPAndKeyAttributes,
} from "./srp";
import type { KeyAttributes } from "./user";

export class PasswordWorker {
    async changePassword(
        password: string,
        masterKey: string,
        keyAttributes: KeyAttributes,
        email: string,
    ) {
        const {
            key: kek,
            salt: kekSalt,
            opsLimit,
            memLimit,
        } = await deriveSensitiveKey(password);
        const { encryptedData: encryptedKey, nonce: keyDecryptionNonce } =
            await encryptBox(masterKey, kek);
        const updatedKeyAttr = {
            encryptedKey,
            keyDecryptionNonce,
            kekSalt,
            opsLimit,
            memLimit,
        };

        await updateSRPAndKeyAttributes(
            await generateSRPSetupAttributes(kek),
            updatedKeyAttr,
        );

        const srpAttributes = ensure(await getSRPAttributes(email));
        const interactiveKeyAttributes = await generateInteractiveKeyAttributes(
            password,
            { ...keyAttributes, ...updatedKeyAttr },
            masterKey,
        );
        return { srpAttributes, keyAttributes: interactiveKeyAttributes };
    }
}

expose(PasswordWorker);

logUnhandledErrorsAndRejectionsInWorker();
