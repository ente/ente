import { fetchFile } from "ente-base/file-download";
import { authenticatedRequestHeaders, ensureOk } from "ente-base/http";
import log from "ente-base/log";
import { customAPIOrigin } from "ente-base/origins";
import { createStreamDecryptor, decryptBox } from "ente-locker-wasm";
import { getEncryptedFileRecord, getLockerCacheSnapshot } from "./locker-cache";
import { decryptCollectionKey } from "./sync/decrypt";

const DOWNLOAD_URL_REVOKE_DELAY_MS = 30_000;

export const downloadLockerFile = async (
    fileID: number,
    fileName: string,
    onProgress?: (progress: { loaded: number; total?: number }) => void,
): Promise<void> => {
    const fileRecord = getEncryptedFileRecord(fileID);
    if (!fileRecord) {
        log.error(`Locker download missing file record ${fileID}`);
        throw new Error(`File ${fileID} not found in cache`);
    }

    log.info(
        `Locker download start ${fileID}: hasObject=${fileRecord.hasObject} size=${fileRecord.fileSize ?? "unknown"}`,
    );

    const cacheSnapshot = getLockerCacheSnapshot();
    const collectionRecord = cacheSnapshot.collections.get(
        fileRecord.collectionID,
    );
    if (!collectionRecord) {
        log.error(
            `Locker download missing collection record ${fileID}: collectionID=${fileRecord.collectionID}`,
        );
        throw new Error(
            `Collection ${fileRecord.collectionID} not found in cache`,
        );
    }

    let fileKey: string;
    try {
        const collectionKey = await decryptCollectionKey(collectionRecord);
        fileKey = await decryptBox(
            {
                encryptedData: fileRecord.encryptedKey,
                nonce: fileRecord.keyDecryptionNonce,
            },
            collectionKey,
        );
    } catch (error) {
        log.error(
            `Locker download key preparation failed ${fileID}: collectionID=${fileRecord.collectionID}`,
            error,
        );
        throw error;
    }

    const customOrigin = await customAPIOrigin();
    const downloadSource = customOrigin ? "api" : "proxy";
    let response: Response;
    try {
        if (customOrigin) {
            response = await fetchFile(fileID, "file");
        } else {
            response = await fetch(`https://files.ente.com/?fileID=${fileID}`, {
                headers: await authenticatedRequestHeaders(),
            });
        }
    } catch (error) {
        log.error(
            `Locker download request failed ${fileID}: source=${downloadSource}`,
            error,
        );
        throw error;
    }
    ensureOk(response);
    log.info(
        `Locker download response ${fileID}: source=${downloadSource} status=${response.status} redirected=${response.redirected} contentType=${response.headers.get("Content-Type") ?? "unknown"} contentLength=${response.headers.get("Content-Length") ?? "unknown"}`,
    );

    const body = response.body;
    if (!body) {
        log.error(
            `Locker download empty response body ${fileID}: source=${downloadSource} status=${response.status}`,
        );
        throw new Error("Download response body is empty");
    }

    const reader = body.getReader();
    const contentLength =
        parseInt(response.headers.get("Content-Length") ?? "", 10) || 0;
    let downloadedBytes = 0;

    onProgress?.({
        loaded: 0,
        total: contentLength > 0 ? contentLength : undefined,
    });

    const streamDecryptor = await createStreamDecryptor(
        fileRecord.fileDecryptionHeader,
        fileKey,
    );
    let leftoverBytes = new Uint8Array();

    const decryptedStream = new ReadableStream<Uint8Array>({
        pull: async (controller) => {
            let didEnqueue = false;
            try {
                do {
                    const { done, value } = await reader.read();
                    let data: Uint8Array;
                    if (done) {
                        data = leftoverBytes;
                    } else {
                        downloadedBytes += value.length;
                        onProgress?.({
                            loaded: downloadedBytes,
                            total:
                                contentLength > 0 ? contentLength : undefined,
                        });
                        data = new Uint8Array(
                            leftoverBytes.length + value.length,
                        );
                        data.set(leftoverBytes, 0);
                        data.set(value, leftoverBytes.length);
                    }

                    while (data.length >= streamDecryptor.decryptionChunkSize) {
                        const decryptedChunk = streamDecryptor.decryptChunk(
                            data.slice(0, streamDecryptor.decryptionChunkSize),
                        );
                        controller.enqueue(decryptedChunk);
                        didEnqueue = true;
                        data = data.slice(streamDecryptor.decryptionChunkSize);
                    }

                    if (done) {
                        if (data.length > 0) {
                            const decryptedChunk =
                                streamDecryptor.decryptChunk(data);
                            controller.enqueue(decryptedChunk);
                        }
                        if (!streamDecryptor.isFinalized()) {
                            throw new Error(
                                "Download stream truncated before final chunk",
                            );
                        }
                        onProgress?.({
                            loaded:
                                contentLength > 0
                                    ? contentLength
                                    : downloadedBytes,
                            total:
                                contentLength > 0 ? contentLength : undefined,
                        });
                        streamDecryptor.free();
                        controller.close();
                        didEnqueue = true;
                    } else {
                        leftoverBytes = new Uint8Array(data);
                    }
                } while (!didEnqueue);
            } catch (error) {
                log.error(
                    `Locker download stream failed ${fileID}: source=${downloadSource} downloaded=${downloadedBytes} total=${contentLength > 0 ? contentLength : "unknown"} leftover=${leftoverBytes.length}`,
                    error,
                );
                streamDecryptor.free();
                controller.error(error);
            }
        },
        cancel: () => {
            log.warn(
                `Locker download stream cancelled ${fileID}: source=${downloadSource} downloaded=${downloadedBytes} total=${contentLength > 0 ? contentLength : "unknown"}`,
            );
            streamDecryptor.free();
            void reader.cancel();
        },
    });

    let decryptedData: Blob;
    try {
        decryptedData = await new Response(decryptedStream).blob();
    } catch (error) {
        log.error(
            `Locker download blob assembly failed ${fileID}: source=${downloadSource} downloaded=${downloadedBytes} total=${contentLength > 0 ? contentLength : "unknown"}`,
            error,
        );
        throw error;
    }
    log.info(
        `Locker download decrypted ${fileID}: source=${downloadSource} downloaded=${downloadedBytes} blobSize=${decryptedData.size}`,
    );
    const url = URL.createObjectURL(decryptedData);
    const anchor = document.createElement("a");
    anchor.style.display = "none";
    anchor.href = url;
    anchor.download = fileName;
    document.body.appendChild(anchor);
    anchor.click();
    log.info(
        `Locker download triggered save ${fileID}: source=${downloadSource}`,
    );
    setTimeout(() => URL.revokeObjectURL(url), DOWNLOAD_URL_REVOKE_DELAY_MS);
    anchor.remove();
};
