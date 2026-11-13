import { savedKeyAttributes } from "ente-accounts/services/accounts-db";
import { decryptBox } from "ente-accounts/services/crypto";
import { ensureMasterKeyFromSession } from "ente-accounts/services/prelogin-session";
import { recoveryKeyToMnemonic } from "ente-prelogin-wasm";

const preloginRecoveryKey = async () => {
    const masterKey = await ensureMasterKeyFromSession();

    const keyAttributes = savedKeyAttributes();
    const { recoveryKeyEncryptedWithMasterKey, recoveryKeyDecryptionNonce } =
        keyAttributes ?? {};

    if (!recoveryKeyEncryptedWithMasterKey || !recoveryKeyDecryptionNonce)
        throw new Error("Missing recovery key");

    return decryptBox(
        {
            encryptedData: recoveryKeyEncryptedWithMasterKey,
            nonce: recoveryKeyDecryptionNonce,
        },
        masterKey,
    );
};

export const getPreloginRecoveryKeyMnemonic = async () =>
    recoveryKeyToMnemonic(await preloginRecoveryKey());
