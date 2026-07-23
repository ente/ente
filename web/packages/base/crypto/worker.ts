import { expose } from "comlink";
import { logUnhandledErrorsAndRejectionsInWorker } from "ente-base/log-web";
import * as libsodium from "./libsodium";

/**
 * A web worker that exposes the functions defined by libsodium.ts.
 *
 * See: [Note: Crypto code hierarchy].
 *
 * Note: Keep these methods logic free. They are meant to be trivial proxies.
 */
export class CryptoWorker {
    toB64 = libsodium.toB64;
    fromB64 = libsodium.fromB64;
    toB64URLSafe = libsodium.toB64URLSafe;
    toB64URLSafeNoPadding = libsodium.toB64URLSafeNoPadding;
    fromB64URLSafeNoPadding = libsodium.fromB64URLSafeNoPadding;
    toHex = libsodium.toHex;
    fromHex = libsodium.fromHex;
    generateKey = libsodium.generateKey;
    generateBlobOrStreamKey = libsodium.generateBlobOrStreamKey;
    encryptBox = libsodium.encryptBox;
    encryptBlob = libsodium.encryptBlob;
    encryptBlobBytes = libsodium.encryptBlobBytes;
    encryptMetadataJSON = libsodium.encryptMetadataJSON;
    encryptStreamBytes = libsodium.encryptStreamBytes;
    initChunkEncryption = libsodium.initChunkEncryption;
    encryptStreamChunk = libsodium.encryptStreamChunk;
    decryptBox = libsodium.decryptBox;
    decryptBoxBytes = libsodium.decryptBoxBytes;
    decryptBlob = libsodium.decryptBlob;
    decryptBlobBytes = libsodium.decryptBlobBytes;
    decryptMetadataJSON = libsodium.decryptMetadataJSON;
    decryptStreamBytes = libsodium.decryptStreamBytes;
    initChunkDecryption = libsodium.initChunkDecryption;
    decryptStreamChunk = libsodium.decryptStreamChunk;
    chunkHashInit = libsodium.chunkHashInit;
    chunkHashUpdate = libsodium.chunkHashUpdate;
    chunkHashFinal = libsodium.chunkHashFinal;
    generateKeyPair = libsodium.generateKeyPair;
    boxSeal = libsodium.boxSeal;
    boxSealOpen = libsodium.boxSealOpen;
    boxSealOpenBytes = libsodium.boxSealOpenBytes;
    generateDeriveKeySalt = libsodium.generateDeriveKeySalt;
    deriveKey = libsodium.deriveKey;
    deriveSensitiveKey = libsodium.deriveSensitiveKey;
    deriveInteractiveKey = libsodium.deriveInteractiveKey;
    deriveModerateKey = libsodium.deriveModerateKey;
    deriveSubKeyBytes = libsodium.deriveSubKeyBytes;
}

expose(CryptoWorker);

logUnhandledErrorsAndRejectionsInWorker();
