import {
    streamEncryptionChunkOverhead,
    streamEncryptionChunkSize,
} from "ente-base/crypto/types";
import type {
    FinishedUploadType,
    UploadProgressState,
} from "ente-gallery/components/upload-progress-stats";
import type { UploadPhase } from "ente-gallery/services/upload";

export class UploadProgressTracker {
    phase: UploadPhase = "preparing";
    filenames = new Map<number, string>();
    hasLivePhotos = false;
    uploadedCount = 0;
    totalCount = 0;
    inProgress = new Map<number, number>();
    finished = new Map<number, FinishedUploadType>();
    bytes = new Map<
        number,
        { total: number | undefined; uploaded: number; fileSize?: number }
    >();

    private transferredBytes = 0;
    private transferSamples: { time: number; bytes: number }[] = [];
    private lastTransferTime: number | undefined;
    private knownUploadBytes = 0;
    private knownUploadCount = 0;
    private uploadOverheadBytes = 0;
    private uploadOverheadCount = 0;

    reset(count: number) {
        this.totalCount = count;
        this.uploadedCount = 0;
        this.inProgress.clear();
        this.finished.clear();
        this.bytes.clear();
        this.transferredBytes = 0;
        this.transferSamples = [];
        this.lastTransferTime = undefined;
        this.knownUploadBytes = 0;
        this.knownUploadCount = 0;
        this.uploadOverheadBytes = 0;
        this.uploadOverheadCount = 0;
    }

    finish(localID: number, type: FinishedUploadType) {
        this.finished.set(localID, type);
        this.inProgress.delete(localID);
        this.bytes.delete(localID);
        this.uploadedCount++;
    }

    updateBytes(
        localID: number,
        uploaded: number,
        total: number,
        reset: boolean,
        now: number,
        fileSize?: number,
    ) {
        if (this.phase != "uploading") return;
        const previous = this.bytes.get(localID);
        if (!previous) return;

        uploaded = Math.max(0, Math.min(uploaded, total));
        if (previous.total === undefined) {
            this.knownUploadBytes += total;
            this.knownUploadCount++;
            const originalFileSize = fileSize ?? previous.fileSize;
            if (originalFileSize !== undefined) {
                this.uploadOverheadBytes += Math.max(
                    0,
                    total -
                        originalFileSize -
                        Math.ceil(
                            originalFileSize / streamEncryptionChunkSize,
                        ) *
                            streamEncryptionChunkOverhead,
                );
                this.uploadOverheadCount++;
            }
        }
        const delta = reset ? 0 : Math.max(0, uploaded - previous.uploaded);
        if (delta > 0) {
            if (!this.transferSamples.length)
                this.transferSamples.push({
                    time: now,
                    bytes: this.transferredBytes,
                });
            this.lastTransferTime = now;
        }
        this.transferredBytes += delta;
        this.bytes.set(localID, { total, uploaded });
    }

    snapshot(now: number): UploadProgressState {
        const perFileProgress = this.totalCount ? 100 / this.totalCount : 0;
        let percentComplete =
            perFileProgress * (this.finished.size || this.uploadedCount);
        for (const progress of this.inProgress.values()) {
            if (progress >= 0)
                percentComplete += (perFileProgress * progress) / 100;
        }

        const finishedUploads = new Map<FinishedUploadType, number[]>();
        for (const [localID, type] of this.finished) {
            const ids = finishedUploads.get(type);
            if (ids) ids.push(localID);
            else finishedUploads.set(type, [localID]);
        }

        return {
            uploadPhase: this.phase,
            uploadCounter: {
                finished: this.uploadedCount,
                total: this.totalCount,
            },
            percentComplete,
            uploadETA: this.estimateRemainingTime(now),
            inProgressUploads: Array.from(
                this.inProgress,
                ([localFileID, progress]) => ({ localFileID, progress }),
            ),
            uploadFileNames: this.filenames,
            finishedUploads,
            hasLivePhotos: this.hasLivePhotos,
        };
    }

    private estimateRemainingTime(now: number): number | undefined {
        if (this.phase != "uploading" || !this.bytes.size) return;
        if (this.transferSamples.length) {
            this.transferSamples.push({
                time: now,
                bytes: this.transferredBytes,
            });
            while (
                this.transferSamples.length > 1 &&
                this.transferSamples[1]!.time <= now - 30000
            ) {
                this.transferSamples.shift();
            }
        }

        let remainingBytes = 0;
        let knownBytes = this.knownUploadBytes;
        let knownCount = this.knownUploadCount;
        let unknownCount = 0;
        const overhead = this.uploadOverheadCount
            ? this.uploadOverheadBytes / this.uploadOverheadCount
            : 0;
        for (const { total, uploaded, fileSize } of this.bytes.values()) {
            const estimatedTotal =
                total ??
                (fileSize === undefined
                    ? undefined
                    : fileSize +
                      Math.ceil(fileSize / streamEncryptionChunkSize) *
                          streamEncryptionChunkOverhead +
                      overhead);
            if (estimatedTotal === undefined) {
                unknownCount++;
            } else {
                remainingBytes += Math.max(0, estimatedTotal - uploaded);
                if (total === undefined) {
                    knownBytes += estimatedTotal;
                    knownCount++;
                }
            }
        }
        if (unknownCount) {
            if (!knownCount) return;
            remainingBytes += (unknownCount * knownBytes) / knownCount;
        }

        const firstSample = this.transferSamples[0];
        if (
            remainingBytes > 0 &&
            this.lastTransferTime !== undefined &&
            now - this.lastTransferTime < 15000 &&
            firstSample &&
            now - firstSample.time >= 5000 &&
            this.transferredBytes > firstSample.bytes
        ) {
            return Math.ceil(
                (remainingBytes * (now - firstSample.time)) /
                    ((this.transferredBytes - firstSample.bytes) * 1000),
            );
        }
        return undefined;
    }
}
