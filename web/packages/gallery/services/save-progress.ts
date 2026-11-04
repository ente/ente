import type { EnteFile } from "ente-media/file";
import type { UpdateSaveGroup } from "../components/utils/save-groups";
import type { FileDownloadProgress } from "./download-core";

export const createSaveProgress = (
    files: EnteFile[],
    updateSaveGroup: UpdateSaveGroup,
) => {
    const progress = new Map(
        files.map((file) => [
            file.id,
            { loaded: 0, total: file.info?.fileSize || undefined },
        ]),
    );
    let lastUpdate = -Infinity;

    const publish = (force = false) => {
        const now = performance.now();
        if (!force && now - lastUpdate < 100) return;
        lastUpdate = now;

        let loaded = 0;
        let total = 0;
        for (const item of progress.values()) {
            if (!item.total) {
                updateSaveGroup((g) => ({ ...g, downloadProgress: undefined }));
                return;
            }
            loaded += Math.min(item.loaded, item.total);
            total += item.total;
        }
        updateSaveGroup((g) => ({
            ...g,
            downloadProgress: total ? loaded / total : undefined,
        }));
    };

    return {
        start: (file: EnteFile) => {
            const previous = progress.get(file.id);
            progress.set(file.id, { loaded: 0, total: previous?.total });
            publish(true);
        },
        update: (file: EnteFile, next: FileDownloadProgress) => {
            const previous = progress.get(file.id);
            progress.set(file.id, {
                loaded: next.loaded,
                total: next.total ?? previous?.total,
            });
            publish(next.loaded === next.total);
        },
    };
};
