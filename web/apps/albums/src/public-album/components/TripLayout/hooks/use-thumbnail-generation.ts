import { useBaseContext } from "ente-base/context";
import type { EnteFile } from "ente-media/file";
import { useEffect, useRef } from "react";

import type { JourneyPoint } from "../types";
import { generateNeededThumbnails } from "../utils/data-processing";

export interface UseThumbnailGenerationParams {
    photoClusters: JourneyPoint[][];
    journeyData: JourneyPoint[];
    files: EnteFile[];
    thumbnailsGeneratedRef: React.RefObject<boolean>;
    setJourneyData: (
        data: JourneyPoint[] | ((prev: JourneyPoint[]) => JourneyPoint[]),
    ) => void;
}

export const useThumbnailGeneration = ({
    photoClusters,
    files,
    thumbnailsGeneratedRef,
    setJourneyData,
}: UseThumbnailGenerationParams) => {
    const { onGenericError } = useBaseContext();
    const processedPhotoIdsRef = useRef<Set<number>>(new Set());

    useEffect(() => {
        const generateThumbs = async () => {
            if (photoClusters.length === 0) return;

            const currentPhotoIds = new Set(
                photoClusters.flat().map((photo) => photo.fileId),
            );

            const photosNeedingThumbnails = photoClusters
                .flat()
                .filter(
                    (photo) =>
                        !photo.image &&
                        (!processedPhotoIdsRef.current.has(photo.fileId) ||
                            !thumbnailsGeneratedRef.current),
                );

            if (photosNeedingThumbnails.length === 0) return;

            const { thumbnailUpdates, thumbnailError } =
                await generateNeededThumbnails({ photoClusters, files });

            if (thumbnailUpdates.size > 0) {
                setJourneyData((prevData) =>
                    prevData.map((photo) => {
                        const thumbnailUrl = thumbnailUpdates.get(photo.fileId);
                        if (thumbnailUrl && !photo.image) {
                            return { ...photo, image: thumbnailUrl };
                        }
                        return photo;
                    }),
                );
            }

            if (thumbnailError) {
                onGenericError(thumbnailError);
            }

            processedPhotoIdsRef.current = new Set([
                ...processedPhotoIdsRef.current,
                ...currentPhotoIds,
            ]);
            thumbnailsGeneratedRef.current = true;
        };

        void generateThumbs();
    }, [
        photoClusters,
        files,
        thumbnailsGeneratedRef,
        setJourneyData,
        onGenericError,
    ]);
};
