import type { PreUploadSkippedFile } from "ente-base/types/ipc";
import type {
    FinishedUploadType,
    InProgressUpload,
    SegregatedFinishedUploads,
    UploadCounter,
    UploadFileNames,
} from "ente-gallery/components/upload-progress-stats";
import type { UploadPhase } from "ente-gallery/services/upload";

interface UploadProgressSnapshot {
    open: boolean;
    uploadPhase: UploadPhase;
    uploadFileNames: UploadFileNames;
    hasLivePhotos: boolean;
    percentComplete: number;
    estimatedSecondsRemaining: number | undefined;
    uploadCounter: UploadCounter;
    inProgressUploads: InProgressUpload[];
    finishedUploads: SegregatedFinishedUploads;
    preUploadSkippedFiles: PreUploadSkippedFile[];
}

class UploadProgressTracker {
    batchID = 0;
    private snapshot: UploadProgressSnapshot = {
        open: false,
        uploadPhase: "preparing",
        uploadFileNames: new Map(),
        hasLivePhotos: false,
        percentComplete: 0,
        estimatedSecondsRemaining: undefined,
        uploadCounter: { finished: 0, total: 0 },
        inProgressUploads: [],
        finishedUploads: new Map(),
        preUploadSkippedFiles: [],
    };
    private listeners = new Set<() => void>();
    private filesUploadedCount = 0;
    private totalFilesCount = 0;
    private inProgressUploads = new Map<number, number>();
    private finishedUploads = new Map<number, FinishedUploadType>();
    private fileBytes = new Map<
        number,
        { totalBytes: number | undefined; uploadedBytes: number }
    >();
    private remainingBytes = 0;
    private unknownFileSizes = 0;
    private transferredBytes = 0;
    private byteSamples: { time: number; bytes: number }[] = [];
    private uploadStartedAt: number | undefined;

    getSnapshot = () => this.snapshot;

    subscribe = (onChange: () => void) => {
        this.listeners.add(onChange);
        return () => {
            this.listeners.delete(onChange);
        };
    };

    reset(count = 0, fileSizes?: ReadonlyMap<number, number | undefined>) {
        this.batchID++;
        this.uploadStartedAt = undefined;
        this.byteSamples = [];
        this.fileBytes.clear();
        this.remainingBytes = 0;
        this.unknownFileSizes = 0;
        this.transferredBytes = 0;
        for (const [localID, size] of fileSizes ?? []) {
            const totalBytes =
                size !== undefined && Number.isFinite(size) && size >= 0
                    ? size
                    : undefined;
            this.fileBytes.set(localID, { totalBytes, uploadedBytes: 0 });
            if (totalBytes === undefined) this.unknownFileSizes++;
            else this.remainingBytes += totalBytes;
        }
        this.totalFilesCount = count;
        this.filesUploadedCount = 0;
        this.inProgressUploads = new Map();
        this.finishedUploads = new Map();
        this.updateProgress();
    }

    setUploadPhase(uploadPhase: UploadPhase) {
        this.uploadStartedAt = undefined;
        this.byteSamples = [];
        if (uploadPhase == "uploading" && this.fileBytes.size > 0) {
            this.uploadStartedAt = performance.now();
            this.byteSamples.push({
                time: this.uploadStartedAt,
                bytes: this.transferredBytes,
            });
        }
        this.updateSnapshot({
            uploadPhase,
            estimatedSecondsRemaining: undefined,
        });
    }

    setFiles(files: { localID: number; fileName: string }[]) {
        this.updateSnapshot({
            uploadFileNames: new Map(
                files.map(({ localID, fileName }) => [localID, fileName]),
            ),
        });
    }

    setHasLivePhoto(hasLivePhotos: boolean) {
        this.updateSnapshot({ hasLivePhotos });
    }

    setPreUploadSkippedFiles(preUploadSkippedFiles: PreUploadSkippedFile[]) {
        this.updateSnapshot({ preUploadSkippedFiles });
    }

    setUploadProgressView(open: boolean) {
        this.updateSnapshot({ open });
    }

    increaseFileUploaded() {
        this.filesUploadedCount++;
        this.updateProgress(this.snapshot.estimatedSecondsRemaining);
    }

    finishFile(localID: number, type: FinishedUploadType) {
        const fileBytes = this.fileBytes.get(localID);
        if (fileBytes) {
            if (fileBytes.totalBytes === undefined) this.unknownFileSizes--;
            else {
                this.remainingBytes -=
                    fileBytes.totalBytes - fileBytes.uploadedBytes;
            }
            this.fileBytes.delete(localID);
        }
        this.finishedUploads.set(localID, type);
        this.inProgressUploads.delete(localID);
        this.filesUploadedCount++;
        this.updateProgress(this.estimateRemainingSeconds());
    }

    hasFilesInResultList() {
        return this.finishedUploads.size > 0;
    }

    updateUploadProgress(localID: number, percentage: number) {
        this.inProgressUploads.set(localID, Math.round(percentage));
        this.updateProgress(this.snapshot.estimatedSecondsRemaining);
    }

    updateUploadBytes(
        batchID: number,
        localID: number,
        uploadedBytes: number,
        totalBytes: number,
    ) {
        const fileBytes = this.fileBytes.get(localID);
        if (
            batchID != this.batchID ||
            this.snapshot.uploadPhase != "uploading" ||
            !fileBytes ||
            !Number.isFinite(uploadedBytes) ||
            !Number.isFinite(totalBytes) ||
            uploadedBytes < 0 ||
            totalBytes < Math.max(uploadedBytes, fileBytes.uploadedBytes)
        ) {
            return;
        }

        const bytes = Math.max(0, uploadedBytes - fileBytes.uploadedBytes);
        if (bytes == 0 && totalBytes == fileBytes.totalBytes) return;
        if (fileBytes.totalBytes === undefined) this.unknownFileSizes--;
        this.remainingBytes += totalBytes - (fileBytes.totalBytes ?? 0) - bytes;
        fileBytes.totalBytes = totalBytes;
        fileBytes.uploadedBytes += bytes;
        if (bytes > 0) {
            this.transferredBytes += bytes;
            const time = performance.now();
            const sample = this.byteSamples.at(-1);
            if (sample?.time == time) sample.bytes = this.transferredBytes;
            else this.byteSamples.push({ time, bytes: this.transferredBytes });
        }
        const estimatedSecondsRemaining = this.estimateRemainingSeconds();
        if (
            estimatedSecondsRemaining !==
            this.snapshot.estimatedSecondsRemaining
        ) {
            this.updateSnapshot({ estimatedSecondsRemaining });
        }
    }

    private estimateRemainingSeconds() {
        if (
            this.snapshot.uploadPhase != "uploading" ||
            this.uploadStartedAt === undefined
        ) {
            return undefined;
        }

        const now = performance.now();
        while (
            this.byteSamples.length > 2 &&
            this.byteSamples[1]!.time <= now - 30_000
        ) {
            this.byteSamples.shift();
        }
        const first = this.byteSamples[0];
        if (
            !first ||
            this.unknownFileSizes > 0 ||
            now - this.uploadStartedAt < 5000
        ) {
            return undefined;
        }

        const bytes = this.transferredBytes - first.bytes;
        const seconds = (now - first.time) / 1000;
        if (bytes <= 0 || seconds <= 0) return undefined;

        const estimate = (Math.max(0, this.remainingBytes) * seconds) / bytes;
        return Number.isFinite(estimate) ? Math.ceil(estimate) : undefined;
    }

    private updateProgress(estimatedSecondsRemaining?: number) {
        const perFileProgress =
            this.totalFilesCount > 0 ? 100 / this.totalFilesCount : 0;
        let percentComplete =
            perFileProgress *
            (this.finishedUploads.size || this.filesUploadedCount);

        for (const progress of this.inProgressUploads.values()) {
            if (progress < 0) continue;
            percentComplete += (perFileProgress * progress) / 100;
        }

        const finishedUploads: SegregatedFinishedUploads = new Map();
        for (const [localID, result] of this.finishedUploads) {
            if (!finishedUploads.has(result)) finishedUploads.set(result, []);
            finishedUploads.get(result)!.push(localID);
        }

        this.updateSnapshot({
            percentComplete,
            estimatedSecondsRemaining,
            uploadCounter: {
                finished: this.filesUploadedCount,
                total: this.totalFilesCount,
            },
            inProgressUploads: [...this.inProgressUploads].map(
                ([localFileID, progress]) => ({ localFileID, progress }),
            ),
            finishedUploads,
        });
    }

    private updateSnapshot(update: Partial<UploadProgressSnapshot>) {
        this.snapshot = { ...this.snapshot, ...update };
        this.listeners.forEach((onChange) => onChange());
    }
}

export const uploadProgress = new UploadProgressTracker();
