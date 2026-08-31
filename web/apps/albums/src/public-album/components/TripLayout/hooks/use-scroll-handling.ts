import { useCallback, useEffect, useMemo } from "react";

import type { JourneyPoint } from "../types";
import { throttle } from "../utils/geocoding";
import {
    handleMarkerClick,
    handleTimelineScroll,
    scrollTimelineToLocation,
    updateLocationPositions,
    type PositionInfo,
} from "../utils/scroll-utils";

export interface UseScrollHandlingParams {
    timelineRef: React.RefObject<HTMLDivElement | null>;
    photoClusters: JourneyPoint[][];
    locationPositions: PositionInfo[];
    mapRef: L.Map | null;
    locationRefs: React.RefObject<(HTMLDivElement | null)[]>;
    isClusterClickScrollingRef: React.RefObject<boolean>;
    clusterClickTimeoutRef: React.RefObject<NodeJS.Timeout | null>;
    previousActiveLocationRef: React.RefObject<number>;
    setLocationPositions: (positions: PositionInfo[]) => void;
    setHasUserScrolled: (scrolled: boolean) => void;
    setScrollProgress: (progress: number) => void;
    setTargetZoom: (zoom: number | null) => void;
    isMobileOrTablet: boolean;
}

export const useScrollHandling = ({
    timelineRef,
    photoClusters,
    locationPositions,
    mapRef,
    locationRefs,
    isClusterClickScrollingRef,
    clusterClickTimeoutRef,
    previousActiveLocationRef,
    setLocationPositions,
    setHasUserScrolled,
    setScrollProgress,
    setTargetZoom,
    isMobileOrTablet,
}: UseScrollHandlingParams) => {
    const updatePositions = useCallback(() => {
        updateLocationPositions({
            locationRefs: locationRefs.current,
            setLocationPositions,
        });
    }, [locationRefs, setLocationPositions]);

    const timelineScrollHandler = useCallback(() => {
        handleTimelineScroll({
            timelineRef,
            photoClusters,
            locationPositions,
            mapRef,
            isClusterClickScrollingRef,
            setHasUserScrolled,
            setScrollProgress,
            previousActiveLocationRef,
            isMobileOrTablet,
            setTargetZoom,
        });
    }, [
        timelineRef,
        photoClusters,
        locationPositions,
        mapRef,
        isClusterClickScrollingRef,
        setHasUserScrolled,
        setScrollProgress,
        previousActiveLocationRef,
        isMobileOrTablet,
        setTargetZoom,
    ]);

    const throttledTimelineScroll = useMemo(
        () => throttle(timelineScrollHandler, 16),
        [timelineScrollHandler],
    );

    const scrollToLocation = useCallback(
        (locationIndex: number) => {
            scrollTimelineToLocation({
                timelineRef,
                locationIndex,
                photoClusters,
                locationPositions,
                isMobileOrTablet,
            });
        },
        [timelineRef, photoClusters, locationPositions, isMobileOrTablet],
    );

    const markerClickHandler = useCallback(
        (clusterIndex: number, clusterLat: number, clusterLng: number) => {
            handleMarkerClick({
                clusterIndex,
                clusterLat,
                clusterLng,
                photoClusters,
                mapRef,
                isClusterClickScrollingRef,
                clusterClickTimeoutRef,
                setScrollProgress,
                setHasUserScrolled,
                scrollTimelineToLocation: scrollToLocation,
                isMobileOrTablet,
                setTargetZoom,
                previousActiveLocationRef,
            });
        },
        [
            photoClusters,
            mapRef,
            isClusterClickScrollingRef,
            clusterClickTimeoutRef,
            setScrollProgress,
            setHasUserScrolled,
            scrollToLocation,
            isMobileOrTablet,
            setTargetZoom,
            previousActiveLocationRef,
        ],
    );

    useEffect(() => {
        if (
            locationRefs.current.length === photoClusters.length &&
            photoClusters.length > 0
        ) {
            const timer = setTimeout(updatePositions, 100);
            return () => clearTimeout(timer);
        }
        return undefined;
    }, [photoClusters, updatePositions, locationRefs]);

    useEffect(() => {
        const timelineContainer = timelineRef.current;
        if (!timelineContainer) return;

        timelineContainer.addEventListener("scroll", throttledTimelineScroll);

        return () => {
            timelineContainer.removeEventListener(
                "scroll",
                throttledTimelineScroll,
            );
        };
    }, [throttledTimelineScroll, timelineRef]);

    useEffect(() => {
        return () => {
            if (clusterClickTimeoutRef.current) {
                clearTimeout(clusterClickTimeoutRef.current);
                clusterClickTimeoutRef.current = null;
            }
        };
    }, [clusterClickTimeoutRef]);

    return { updatePositions, scrollToLocation, markerClickHandler };
};
