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
    bytes = new Map<number, { total: number | undefined; uploaded: number }>();

    private transferredBytes = 0;
    private transferSamples: { time: number; bytes: number }[] = [];
    private lastTransferTime: number | undefined;

    reset(count: number) {
        this.totalCount = count;
        this.uploadedCount = 0;
        this.inProgress.clear();
        this.finished.clear();
        this.bytes.clear();
        this.transferredBytes = 0;
        this.transferSamples = [];
        this.lastTransferTime = undefined;
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
    ) {
        if (this.phase != "uploading") return;
        const previous = this.bytes.get(localID);
        if (!previous) return;

        uploaded = Math.max(0, Math.min(uploaded, total));
        const delta = uploaded - previous.uploaded;
        if (reset) {
            this.transferSamples = [];
            this.lastTransferTime = undefined;
        }
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
        let unknownSize = false;
        for (const { total, uploaded } of this.bytes.values()) {
            if (total === undefined) unknownSize = true;
            else remainingBytes += Math.max(0, total - uploaded);
        }

        const firstSample = this.transferSamples[0];
        if (
            !unknownSize &&
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
