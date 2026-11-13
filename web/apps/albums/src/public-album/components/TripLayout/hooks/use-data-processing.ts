import { useBaseContext } from "ente-base/context";
import type { Collection } from "ente-media/collection";
import type { EnteFile } from "ente-media/file";
import { useEffect, useRef } from "react";

import type { JourneyPoint } from "../types";
import { loadCoverImage, processPhotosData } from "../utils/data-processing";

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
    const { onGenericError } = useBaseContext();
    const reportedCoverErrorFileIDRef = useRef<number | undefined>(undefined);

    useEffect(() => {
        const hasFilesCountChanged = files.length !== filesCountRef.current;
        filesCountRef.current = files.length;

        if (!hasFilesCountChanged && journeyData.length > 0) {
            return;
        }

        thumbnailsGeneratedRef.current = false;

        const { photoData, hasLocationData, processingError } =
            processPhotosData({ files, locationDataRef });

        if (processingError) {
            onGenericError(processingError);
        }

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
        onGenericError,
    ]);

    useEffect(() => {
        const loadCover = async () => {
            const { coverImageURL, coverImageError } = await loadCoverImage({
                journeyData,
                files,
                collection,
            });
            const coverFileID =
                collection?.pubMagicMetadata?.data.coverID ??
                journeyData[0]?.fileId;

            if (
                coverImageError &&
                reportedCoverErrorFileIDRef.current !== coverFileID
            ) {
                reportedCoverErrorFileIDRef.current = coverFileID;
                onGenericError(coverImageError);
            } else if (!coverImageError) {
                reportedCoverErrorFileIDRef.current = undefined;
            }

            if (coverImageURL) {
                setCoverImageUrl(coverImageURL);
            }
        };

        void loadCover();
    }, [journeyData, files, collection, setCoverImageUrl, onGenericError]);
};
