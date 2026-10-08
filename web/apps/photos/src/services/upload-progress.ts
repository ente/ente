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
    uploadCounter: UploadCounter;
    inProgressUploads: InProgressUpload[];
    finishedUploads: SegregatedFinishedUploads;
    preUploadSkippedFiles: PreUploadSkippedFile[];
}

class UploadProgressTracker {
    private snapshot: UploadProgressSnapshot = {
        open: false,
        uploadPhase: "preparing",
        uploadFileNames: new Map(),
        hasLivePhotos: false,
        percentComplete: 0,
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

    getSnapshot = () => this.snapshot;

    subscribe = (onChange: () => void) => {
        this.listeners.add(onChange);
        return () => {
            this.listeners.delete(onChange);
        };
    };

    reset(count = 0) {
        this.totalFilesCount = count;
        this.filesUploadedCount = 0;
        this.inProgressUploads = new Map();
        this.finishedUploads = new Map();
        this.updateProgress();
    }

    setUploadPhase(uploadPhase: UploadPhase) {
        this.updateSnapshot({ uploadPhase });
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
        this.updateProgress();
    }

    finishFile(localID: number, type: FinishedUploadType) {
        this.finishedUploads.set(localID, type);
        this.inProgressUploads.delete(localID);
        this.filesUploadedCount++;
        this.updateProgress();
    }

    hasFilesInResultList() {
        return this.finishedUploads.size > 0;
    }

    updateUploadProgress(localID: number, percentage: number) {
        this.inProgressUploads.set(localID, Math.round(percentage));
        this.updateProgress();
    }

    private updateProgress() {
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
