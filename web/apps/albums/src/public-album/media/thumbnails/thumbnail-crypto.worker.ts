import { expose } from "comlink";
import { decryptBlobBytes } from "ente-base/crypto/libsodium";
import type { BytesOrB64, EncryptedBlob } from "ente-base/crypto/types";
import { logUnhandledErrorsAndRejectionsInWorker } from "ente-base/log-web";

export class ThumbnailCryptoWorker {
    decryptBlobBytes(blob: EncryptedBlob, key: BytesOrB64) {
        return decryptBlobBytes(blob, key);
    }
}

expose(ThumbnailCryptoWorker);

logUnhandledErrorsAndRejectionsInWorker();
