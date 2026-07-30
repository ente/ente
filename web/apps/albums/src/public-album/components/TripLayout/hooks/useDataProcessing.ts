import type { Collection } from "ente-media/collection";
import type { EnteFile } from "ente-media/file";
import { useEffect } from "react";

import type { JourneyPoint } from "../types";
import { loadCoverImage, processPhotosData } from "../utils/dataProcessing";

export interface UseDataProcessingParams {
    files: EnteFile[];
    collection?: Collection;
    journeyData: JourneyPoint[];
    thumbnailsGeneratedRef: React.RefObject<boolean>;
    filesCountRef: React.RefObject<number>;
    locationDataRef: React.RefObject<
        Map<number, { name: string; country: string }>
    >;
    setJourneyData: (
        data: JourneyPoint[] | ((prev: JourneyPoint[]) => JourneyPoint[]),
    ) => void;
    setIsInitialLoad: (loading: boolean) => void;
    setIsLoadingLocations: (loading: boolean) => void;
    setCoverImageUrl: (url: string | null) => void;
}

export const useDataProcessing = ({
    files,
    collection,
    journeyData,
    thumbnailsGeneratedRef,
    filesCountRef,
    locationDataRef,
    setJourneyData,
    setIsInitialLoad,
    setIsLoadingLocations,
    setCoverImageUrl,
}: UseDataProcessingParams) => {
    // Process photos data when files change
    useEffect(() => {
        const hasFilesCountChanged = files.length !== filesCountRef.current;
        filesCountRef.current = files.length;

        if (!hasFilesCountChanged && journeyData.length > 0) {
            return;
        }

        thumbnailsGeneratedRef.current = false;

        const { photoData, hasLocationData } = processPhotosData({
            files,
            locationDataRef,
        });

        setJourneyData(photoData);
        setIsInitialLoad(false);

        if (hasLocationData) {
            setIsLoadingLocations(true);
        }
    }, [
        files,
        journeyData.length,
        filesCountRef,
        locationDataRef,
        thumbnailsGeneratedRef,
        setJourneyData,
        setIsInitialLoad,
        setIsLoadingLocations,
    ]);

    // Load cover image after data loads
    useEffect(() => {
        const loadCover = async () => {
            const coverUrl = await loadCoverImage({
                journeyData,
                files,
                collection,
            });
            if (coverUrl) {
                setCoverImageUrl(coverUrl);
            }
        };

        void loadCover();
    }, [journeyData, files, collection, setCoverImageUrl]);
};
