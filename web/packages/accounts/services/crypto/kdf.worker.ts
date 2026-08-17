import { expose } from "comlink";
import { logUnhandledErrorsAndRejectionsInWorker } from "ente-base/log-web";
import * as kdf from "./kdf";

export class KDFWorker {
    deriveKey = kdf.deriveKey;
    deriveSensitiveKey = kdf.deriveSensitiveKey;
    deriveInteractiveKey = kdf.deriveInteractiveKey;
}

expose(KDFWorker);

logUnhandledErrorsAndRejectionsInWorker();
