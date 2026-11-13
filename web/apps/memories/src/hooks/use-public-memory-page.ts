import { useCallback, useEffect, useState } from "react";

import { downloadManager } from "ente-gallery/services/download";
import type { EnteFile } from "ente-media/file";
import type {
    PublicMemoryShareFrame,
    PublicMemoryShareMetadata,
} from "../services/public-memory";
import {
    loadPublicMemoryPage,
    type PublicMemoryViewerVariant,
} from "../services/public-memory-page";

export interface UsePublicMemoryPageResult {
    currentIndex: number;
    errorMessage: string;
    files: EnteFile[] | undefined;
    goToNext: () => void;
    goToPrev: () => void;
    handleSeek: (index: number) => void;
    hideContent: boolean;
    laneFrames: (PublicMemoryShareFrame | undefined)[] | undefined;
    loading: boolean;
    memoryMetadata: PublicMemoryShareMetadata | undefined;
    memoryName: string;
    viewerVariant: PublicMemoryViewerVariant;
}

export const usePublicMemoryPage = (): UsePublicMemoryPageResult => {
    const [memoryName, setMemoryName] = useState<string>("");
    const [files, setFiles] = useState<EnteFile[] | undefined>(undefined);
    const [laneFrames, setLaneFrames] = useState<
        (PublicMemoryShareFrame | undefined)[] | undefined
    >(undefined);
    const [memoryMetadata, setMemoryMetadata] = useState<
        PublicMemoryShareMetadata | undefined
    >(undefined);
    const [viewerVariant, setViewerVariant] =
        useState<PublicMemoryViewerVariant>("share");
    const [errorMessage, setErrorMessage] = useState<string>("");
    const [loading, setLoading] = useState(true);
    const [currentIndex, setCurrentIndex] = useState(0);
    const [hideContent, setHideContent] = useState(false);

    useEffect(() => {
        let cancelled = false;

        const main = async () => {
            const result = await loadPublicMemoryPage(
                new URL(window.location.href),
            );

            if (cancelled) {
                return;
            }

            switch (result.kind) {
                case "redirect":
                    setHideContent(true);
                    window.location.href = result.redirectURL;
                    return;
                case "error":
                    setErrorMessage(result.errorMessage);
                    setLoading(false);
                    return;
                case "loaded":
                    downloadManager.setPublicMemoryCredentials({
                        accessToken: result.data.accessToken,
                    });
                    setMemoryMetadata(result.data.memoryMetadata);
                    setMemoryName(result.data.memoryName);
                    setViewerVariant(result.data.viewerVariant);
                    setFiles(result.data.files);
                    setLaneFrames(result.data.laneFrames);
                    setLoading(false);
                    return;
            }
        };

        void main();
        return () => {
            cancelled = true;
            downloadManager.setPublicMemoryCredentials(undefined);
        };
    }, []);

    const goToNext = useCallback(() => {
        if (!files) return;
        setCurrentIndex((prev) => (prev < files.length - 1 ? prev + 1 : prev));
    }, [files]);

    const goToPrev = useCallback(() => {
        setCurrentIndex((prev) => (prev > 0 ? prev - 1 : prev));
    }, []);

    const handleSeek = useCallback(
        (index: number) => {
            if (!files) return;
            const max = files.length - 1;
            const clampedIndex = Math.min(Math.max(index, 0), max);
            setCurrentIndex(clampedIndex);
        },
        [files],
    );

    useEffect(() => {
        const handleKeyDown = (e: KeyboardEvent) => {
            if (e.key === "ArrowRight") goToNext();
            else if (e.key === "ArrowLeft") goToPrev();
        };
        window.addEventListener("keydown", handleKeyDown);
        return () => window.removeEventListener("keydown", handleKeyDown);
    }, [goToNext, goToPrev]);

    return {
        currentIndex,
        errorMessage,
        files,
        goToNext,
        goToPrev,
        handleSeek,
        hideContent,
        laneFrames,
        loading,
        memoryMetadata,
        memoryName,
        viewerVariant,
    };
};
