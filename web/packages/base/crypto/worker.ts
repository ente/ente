import { expose } from "comlink";
import { logUnhandledErrorsAndRejectionsInWorker } from "ente-base/log-web";
import * as libsodium from "./libsodium";

// Keep these as direct proxies; crypto logic belongs in libsodium.ts.
export class CryptoWorker {
    toB64 = libsodium.toB64;
    fromB64 = libsodium.fromB64;
    toB64URLSafeNoPadding = libsodium.toB64URLSafeNoPadding;
    fromB64URLSafeNoPadding = libsodium.fromB64URLSafeNoPadding;
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
    decryptBlobBytes = libsodium.decryptBlobBytes;
    decryptMetadataJSON = libsodium.decryptMetadataJSON;
    decryptStreamBytes = libsodium.decryptStreamBytes;
    initChunkDecryption = libsodium.initChunkDecryption;
    decryptStreamChunk = libsodium.decryptStreamChunk;
    chunkHashInit = libsodium.chunkHashInit;
    chunkHashUpdate = libsodium.chunkHashUpdate;
    chunkHashFinal = libsodium.chunkHashFinal;
    boxSeal = libsodium.boxSeal;
    boxSealOpenBytes = libsodium.boxSealOpenBytes;
    deriveKey = libsodium.deriveKey;
    deriveInteractiveKey = libsodium.deriveInteractiveKey;
}

expose(CryptoWorker);

logUnhandledErrorsAndRejectionsInWorker();
