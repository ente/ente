import { downloadManager } from "@/public-album/download/services/download-manager";
import type { EnteFile } from "ente-media/file";
import {
    fileCreationPhotoSortTime,
    fileFileName,
    fileLocation,
} from "ente-media/file-metadata";
import React from "react";

import type { JourneyPoint } from "../types";
import { getLocationName } from "./geocoding";

export interface ProcessPhotosDataParams {
    files: EnteFile[];
    locationDataRef: React.RefObject<
        Map<number, { name: string; country: string }>
    >;
}

export interface ProcessPhotosDataResult {
    photoData: JourneyPoint[];
    hasLocationData: boolean;
    processingError?: unknown;
}

export const processPhotosData = ({
    files,
    locationDataRef,
}: ProcessPhotosDataParams): ProcessPhotosDataResult => {
    const photoData: JourneyPoint[] = [];
    let processingError: unknown;

    if (files.length === 0) {
        return { photoData, hasLocationData: false };
    }

    for (const file of files) {
        try {
            const location = fileLocation(file);

            if (location) {
                const cachedLocation = locationDataRef.current.get(file.id);
                const finalName = cachedLocation?.name || fileFileName(file);
                const finalCountry = cachedLocation?.country || "Unknown";

                photoData.push({
                    lat: location.latitude,
                    lng: location.longitude,
                    name: finalName,
                    country: finalCountry,
                    timestamp: fileCreationPhotoSortTime(file),
                    image: "",
                    fileId: file.id,
                });
            }
        } catch (e) {
            processingError ??= e;
        }
    }

    photoData.sort((a, b) => a.timestamp - b.timestamp);

    return {
        photoData,
        hasLocationData: photoData.length > 0,
        processingError,
    };
};

export interface FetchLocationNamesParams {
    photoClusters: JourneyPoint[][];
    journeyData: JourneyPoint[];
    locationDataRef: React.RefObject<
        Map<number, { name: string; country: string }>
    >;
}

export interface FetchLocationNamesResult {
    updatedPhotos: Map<number, { name: string; country: string }>;
}

export const fetchLocationNames = async ({
    photoClusters,
    locationDataRef,
}: FetchLocationNamesParams): Promise<FetchLocationNamesResult> => {
    const updatedPhotos = new Map<number, { name: string; country: string }>();

    if (photoClusters.length === 0) {
        return { updatedPhotos };
    }

    const geocodingPromises = photoClusters.map(async (cluster) => {
        if (cluster.length === 0) return null;

        const representativePhoto = cluster[0];
        if (!representativePhoto) return null;

        const locationInfo = await getLocationName(
            representativePhoto.lat,
            representativePhoto.lng,
        );
        return { cluster, locationInfo };
    });

    const results = await Promise.all(geocodingPromises);

    results.forEach((result) => {
        if (!result) return;

        const { cluster, locationInfo } = result;
        cluster.forEach((photo) => {
            updatedPhotos.set(photo.fileId, {
                name: locationInfo.place,
                country: locationInfo.country,
            });
            locationDataRef.current.set(photo.fileId, {
                name: locationInfo.place,
                country: locationInfo.country,
            });
        });
    });

    return { updatedPhotos };
};

export interface GenerateThumbnailsParams {
    photoClusters: JourneyPoint[][];
    files: EnteFile[];
}

export interface GenerateThumbnailsResult {
    thumbnailUpdates: Map<number, string>;
    thumbnailError?: unknown;
}

export const generateNeededThumbnails = async ({
    photoClusters,
    files,
}: GenerateThumbnailsParams): Promise<GenerateThumbnailsResult> => {
    const thumbnailUpdates = new Map<number, string>();
    let thumbnailError: unknown;

    if (photoClusters.length === 0) {
        return { thumbnailUpdates };
    }

    const filesById = new Map(files.map((file) => [file.id, file]));
    const includedIds = new Set<number>();

    const addIfUnique = (group: EnteFile[], fileId: number) => {
        const file = filesById.get(fileId);
        if (!file) return;
        if (includedIds.has(file.id)) return;
        includedIds.add(file.id);
        group.push(file);
    };

    const priorityGroups: EnteFile[][] = [];

    const firstLocationsFiles: EnteFile[] = [];
    photoClusters.slice(0, 3).forEach((cluster) => {
        cluster.slice(0, 3).forEach((photo) => {
            addIfUnique(firstLocationsFiles, photo.fileId);
        });
    });
    if (firstLocationsFiles.length > 0) {
        priorityGroups.push(firstLocationsFiles);
    }

    const mapMarkerFiles: EnteFile[] = [];
    photoClusters.forEach((cluster) => {
        if (cluster.length > 0 && cluster[0]) {
            const firstPhoto = cluster[0];
            addIfUnique(mapMarkerFiles, firstPhoto.fileId);
        }
    });
    if (mapMarkerFiles.length > 0) {
        priorityGroups.push(mapMarkerFiles);
    }

    const remainingLocationFiles: EnteFile[] = [];
    photoClusters.slice(3).forEach((cluster) => {
        cluster.slice(0, 3).forEach((photo) => {
            addIfUnique(remainingLocationFiles, photo.fileId);
        });
    });
    if (remainingLocationFiles.length > 0) {
        priorityGroups.push(remainingLocationFiles);
    }

    for (let groupIndex = 0; groupIndex < priorityGroups.length; groupIndex++) {
        const group = priorityGroups[groupIndex];
        if (!group) continue;

        const groupPromises = group.map(async (file) => {
            try {
                const thumbnailUrl =
                    await downloadManager.renderableThumbnailURL(file);
                if (thumbnailUrl) {
                    thumbnailUpdates.set(file.id, thumbnailUrl);
                }
            } catch (e) {
                thumbnailError ??= e;
            }
        });

        await Promise.all(groupPromises);

        // Yield so thumbnails from this priority group can render.
        if (groupIndex < priorityGroups.length - 1) {
            await new Promise((resolve) => setTimeout(resolve, 50));
        }
    }

    return { thumbnailUpdates, thumbnailError };
};

export interface LoadCoverImageParams {
    journeyData: JourneyPoint[];
    files: EnteFile[];
    collection?: { pubMagicMetadata?: { data: { coverID?: number } } };
}

export interface LoadCoverImageResult {
    coverImageURL: string | null;
    coverImageError?: unknown;
}

export const loadCoverImage = async ({
    journeyData,
    files,
    collection,
}: LoadCoverImageParams): Promise<LoadCoverImageResult> => {
    if (journeyData.length === 0) return { coverImageURL: null };

    let coverFile: EnteFile | undefined;

    const coverID = collection?.pubMagicMetadata?.data.coverID;
    if (coverID) {
        coverFile = files.find((f) => f.id === coverID);
    }

    if (!coverFile) {
        const firstPhoto = journeyData[0];
        if (!firstPhoto) return { coverImageURL: null };
        coverFile = files.find((f) => f.id === firstPhoto.fileId);
    }

    if (!coverFile) return { coverImageURL: null };

    try {
        const sourceURLs =
            await downloadManager.renderableSourceURLs(coverFile);
        if (sourceURLs.type === "image") {
            return { coverImageURL: sourceURLs.imageURL };
        }
    } catch (e) {
        return { coverImageURL: null, coverImageError: e };
    }

    return { coverImageURL: null };
};
