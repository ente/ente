import { deriveKey } from "ente-accounts/services/crypto";
import type { SRPAttributes } from "ente-accounts/services/srp";
import type { KeyAttributes } from "ente-accounts/services/user";
import { isNamedError } from "ente-base/error";
import log from "ente-base/log";
import type { SessionStorageCrypto } from "ente-base/session-storage";
import { t } from "i18next";

export interface MasterPasswordVerificationOptions {
    decryptBox: SessionStorageCrypto["decryptBox"];
    srpAttributes?: SRPAttributes;
    keyAttributes: KeyAttributes | undefined;
    getKeyAttributes?: (
        srpAttributes: SRPAttributes,
        kek: string,
    ) => Promise<KeyAttributes | "redirecting-second-factor" | undefined>;
    onVerify: (
        key: string,
        kek: string,
        keyAttributes: KeyAttributes,
        password: string,
    ) => void | Promise<void>;
}

export const verifyMasterPassword = async (
    {
        decryptBox,
        keyAttributes,
        srpAttributes,
        getKeyAttributes,
        onVerify,
    }: MasterPasswordVerificationOptions,
    password: string,
    setFieldError: (message: string) => void,
) => {
    const kdfAttributes = srpAttributes ?? keyAttributes;
    if (!kdfAttributes)
        throw new Error("Both SRP and key attributes are missing");

    let kek: string;
    try {
        kek = await deriveKey(
            password,
            kdfAttributes.kekSalt,
            kdfAttributes.opsLimit,
            kdfAttributes.memLimit,
        );
    } catch (e) {
        log.error("Failed to derive kek", e);
        setFieldError(t("weak_device_hint"));
        return;
    }

    if (!keyAttributes && getKeyAttributes && srpAttributes) {
        try {
            const result = await getKeyAttributes(srpAttributes, kek);
            if (result == "redirecting-second-factor") {
                return;
            } else {
                keyAttributes = result;
            }
        } catch (e) {
            if (isNamedError(e, "incorrect_password")) {
                log.error("Incorrect password or no account", e);
                setFieldError(t("incorrect_password_or_no_account"));
                return;
            }
            if (isNamedError(e, "session_expired")) {
                log.info("SRP session expired", e);
                setFieldError(t("session_expired_message"));
                return;
            }
            throw e;
        }
    }

    if (!keyAttributes) throw Error("Couldn't get key attributes");

    let key: string;
    try {
        key = await decryptBox(
            {
                encryptedData: keyAttributes.encryptedKey,
                nonce: keyAttributes.keyDecryptionNonce,
            },
            kek,
        );
    } catch {
        setFieldError(t("incorrect_password"));
        return;
    }

    await onVerify(key, kek, keyAttributes, password);
};
