import type { EnteFile } from "ente-media/file";
import { fileCreationPhotoSortTime } from "ente-media/file-metadata";
import { useCallback, useState } from "react";
import type { JourneyPoint } from "../types";

interface UseFileViewerProps {
    files: EnteFile[];
    onSetOpenFileViewer?: (open: boolean) => void;
}

export const useFileViewer = ({
    files,
    onSetOpenFileViewer,
}: UseFileViewerProps) => {
    const [openFileViewer, setOpenFileViewer] = useState(false);
    const [currentFileIndex, setCurrentFileIndex] = useState(0);
    const [viewerFiles, setViewerFiles] = useState<EnteFile[]>([]);

    const handleOpenFileViewer = useCallback(
        (cluster: JourneyPoint[], clickedFileId: number) => {
            const clusterFileIds = cluster.map((point) => point.fileId);

            const clusterFiles = files.filter((file) =>
                clusterFileIds.includes(file.id),
            );

            const sortTimeByFile = new Map<EnteFile, number>();
            const sortTimeForFile = (file: EnteFile) => {
                const cached = sortTimeByFile.get(file);
                if (cached != undefined) return cached;
                const t = fileCreationPhotoSortTime(file);
                sortTimeByFile.set(file, t);
                return t;
            };
            const sortedClusterFiles = [...clusterFiles].sort(
                (a, b) => sortTimeForFile(a) - sortTimeForFile(b),
            );

            const clickedIndex = sortedClusterFiles.findIndex(
                (f) => f.id === clickedFileId,
            );

            if (clickedIndex !== -1 && sortedClusterFiles.length > 0) {
                setViewerFiles(sortedClusterFiles);
                setCurrentFileIndex(clickedIndex);
                setOpenFileViewer(true);
                onSetOpenFileViewer?.(true);
            }
        },
        [files, onSetOpenFileViewer],
    );

    const handleCloseFileViewer = useCallback(() => {
        setOpenFileViewer(false);
        onSetOpenFileViewer?.(false);
    }, [onSetOpenFileViewer]);

    return {
        openFileViewer,
        currentFileIndex,
        viewerFiles,
        handleOpenFileViewer,
        handleCloseFileViewer,
    };
};
