import type { BytesOrB64, EncryptedBlob } from "ente-base/crypto/types";
import { ComlinkWorker } from "ente-base/worker/comlink-worker";
import type { ThumbnailCryptoWorker } from "./thumbnail-crypto.worker";

let _comlinkWorker: ComlinkWorker<typeof ThumbnailCryptoWorker> | undefined;

const sharedWorker = () =>
    (_comlinkWorker ??= new ComlinkWorker<typeof ThumbnailCryptoWorker>(
        "albums-thumbnail-crypto",
        new Worker(new URL("thumbnail-crypto.worker.ts", import.meta.url)),
    )).remote;

export const decryptThumbnailBlobBytes = (
    blob: EncryptedBlob,
    key: BytesOrB64,
) => sharedWorker().then((w) => w.decryptBlobBytes(blob, key));
