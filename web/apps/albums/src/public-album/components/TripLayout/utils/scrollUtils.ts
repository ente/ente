import { startTransition } from "react";

import { calculateDistance, getLocationPosition } from "../mapHelpers";
import type { JourneyPoint } from "../types";

export interface PositionInfo {
    top: number;
    center: number;
}

export interface UpdateLocationPositionsParams {
    locationRefs: (HTMLDivElement | null)[];
    setLocationPositions: (positions: PositionInfo[]) => void;
}

export const updateLocationPositions = ({
    locationRefs,
    setLocationPositions,
}: UpdateLocationPositionsParams) => {
    if (locationRefs.length === 0) return;

    const positions = locationRefs.map((ref) => {
        if (!ref) return { top: 0, center: 0 };
        const rect = ref.getBoundingClientRect();
        const top = ref.offsetTop;
        const center = top + rect.height / 2;
        return { top, center };
    });

    startTransition(() => {
        setLocationPositions(positions);
    });
};

export interface HandleTimelineScrollParams {
    timelineRef: React.RefObject<HTMLDivElement | null>;
    photoClusters: JourneyPoint[][];
    locationPositions: PositionInfo[];
    mapRef: import("leaflet").Map | null;
    isClusterClickScrollingRef: React.RefObject<boolean>;
    setHasUserScrolled: (scrolled: boolean) => void;
    setScrollProgress: (progress: number) => void;
    previousActiveLocationRef: React.RefObject<number>;
    isMobileOrTablet: boolean;
    setTargetZoom: (zoom: number | null) => void;
}

export const handleTimelineScroll = ({
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
}: HandleTimelineScrollParams) => {
    if (
        !timelineRef.current ||
        photoClusters.length === 0 ||
        locationPositions.length === 0
    )
        return;

    const timelineContainer = timelineRef.current;
    const scrollHeight = timelineContainer.scrollHeight;
    const clientHeight = timelineContainer.clientHeight;
    const scrollTop = timelineContainer.scrollTop;

    // Calculate scroll progress (0 to 1)
    const isAtBottom = scrollTop + clientHeight >= scrollHeight - 10;
    const maxScrollableDistance = scrollHeight - clientHeight;
    const progress = isAtBottom
        ? 1
        : maxScrollableDistance > 0
          ? scrollTop / maxScrollableDistance
          : 0;
    const clampedProgress = Math.min(1, Math.max(0, progress));

    if (isClusterClickScrollingRef.current) {
        return;
    }

    setHasUserScrolled(true);
    startTransition(() => {
        setScrollProgress(clampedProgress);
    });

    // Calculate current active location index based on scroll progress
    let currentActiveLocationIndex = -1; // Start with no location selected
    if (photoClusters.length > 0) {
        if (isMobileOrTablet) {
            // Mobile: Slower progression - stay on each location longer
            currentActiveLocationIndex = Math.floor(
                clampedProgress * (photoClusters.length - 0.5),
            );
        } else {
            // Desktop: Use original logic
            currentActiveLocationIndex = Math.round(
                clampedProgress * Math.max(0, photoClusters.length - 1),
            );
        }
    }
    const previousActiveLocationIndex = previousActiveLocationRef.current;

    // Only pan map when active location changes (discrete panning)
    if (
        mapRef?.getContainer() &&
        currentActiveLocationIndex !== previousActiveLocationIndex
    ) {
        previousActiveLocationRef.current = currentActiveLocationIndex;

        // Skip panning if no location is selected (mobile default view)
        if (currentActiveLocationIndex === -1) return;

        const clusterCenters = photoClusters.map((cluster) => {
            const avgLat =
                cluster.reduce((sum, p) => sum + p.lat, 0) / cluster.length;
            const avgLng =
                cluster.reduce((sum, p) => sum + p.lng, 0) / cluster.length;
            return { lat: avgLat, lng: avgLng };
        });

        const targetCluster = clusterCenters[currentActiveLocationIndex];
        if (!targetCluster) return;

        // Position active location at 20% from right edge
        const [positionedLat, positionedLng] = getLocationPosition(
            targetCluster.lat,
            targetCluster.lng,
        );

        // Check if this is a distant location (>500km from previous)
        let isDistantLocation = false;
        if (
            previousActiveLocationIndex !== -1 &&
            previousActiveLocationIndex !== currentActiveLocationIndex
        ) {
            const previousCluster = clusterCenters[previousActiveLocationIndex];
            if (previousCluster) {
                const distance = calculateDistance(
                    previousCluster.lat,
                    previousCluster.lng,
                    targetCluster.lat,
                    targetCluster.lng,
                );
                isDistantLocation = distance > 500; // 500km threshold
            }
        }

        const targetZoom = isMobileOrTablet ? 8 : 10; // Touch device-aware zoom level

        try {
            // Super cluster logic disabled - simple zoom transitions
            if (isDistantLocation) {
                // For distant locations not in super cluster: zoom out → pan → zoom in
                const intermediateZoom = isMobileOrTablet ? 2 : 4;

                // Use event listener for smoother animation chaining with pause
                const onZoomEnd = () => {
                    mapRef.off("zoomend", onZoomEnd);
                    // Small pause to let user see the zoomed out view
                    setTimeout(() => {
                        setTargetZoom(targetZoom);
                        mapRef.flyTo(
                            [positionedLat, positionedLng],
                            targetZoom,
                            {
                                animate: true,
                                duration: 1.2,
                                easeLinearity: 0.2,
                            },
                        );
                    }, 150);
                };

                mapRef.once("zoomend", onZoomEnd);
                setTargetZoom(intermediateZoom);
                mapRef.flyTo([positionedLat, positionedLng], intermediateZoom, {
                    animate: true,
                    duration: 1.2,
                    easeLinearity: 0.2,
                });
            } else {
                // For nearby locations not in super cluster: simple pan to target location
                const currentMapZoom = mapRef.getZoom();
                if (Math.abs(currentMapZoom - targetZoom) > 0.5) {
                    mapRef.flyTo([positionedLat, positionedLng], targetZoom, {
                        animate: true,
                        duration: 0.8,
                        easeLinearity: 0.3,
                    });
                } else {
                    mapRef.panTo([positionedLat, positionedLng], {
                        animate: true,
                        duration: 0.8,
                        easeLinearity: 0.3,
                    });
                }
            }
        } catch (error) {
            console.warn("Map operation failed:", error);
        }
    }
};

export interface ScrollTimelineToLocationParams {
    timelineRef: React.RefObject<HTMLDivElement | null>;
    locationIndex: number;
    photoClusters: JourneyPoint[][];
    locationPositions: PositionInfo[];
    isMobileOrTablet: boolean;
}

export const scrollTimelineToLocation = ({
    timelineRef,
    locationIndex,
    photoClusters,
    locationPositions,
    isMobileOrTablet,
}: ScrollTimelineToLocationParams) => {
    if (
        !timelineRef.current ||
        locationIndex < 0 ||
        locationIndex >= photoClusters.length ||
        locationPositions.length === 0
    )
        return;

    const timelineContainer = timelineRef.current;
    const scrollHeight = timelineContainer.scrollHeight;
    const clientHeight = timelineContainer.clientHeight;
    const maxScrollableDistance = scrollHeight - clientHeight;

    // Calculate target progress using the same formula as scroll progress calculation
    let targetProgress;
    if (isMobileOrTablet) {
        // Mobile: Use inverse of the slower progression formula
        // If active index = Math.floor(progress * (length - 0.5))
        // Then progress = (index + 0.5) / (length - 0.5) for accurate inverse
        targetProgress =
            (locationIndex + 0.5) / Math.max(1, photoClusters.length - 0.5);
    } else {
        // Desktop: Use original formula
        targetProgress = locationIndex / Math.max(1, photoClusters.length - 1);
    }

    // Clamp progress to valid range
    targetProgress = Math.min(1, Math.max(0, targetProgress));
    const targetScrollTop = targetProgress * maxScrollableDistance;

    timelineContainer.scrollTo({
        top: Math.max(0, Math.min(targetScrollTop, maxScrollableDistance)),
        behavior: "smooth",
    });
};

export interface HandleMarkerClickParams {
    clusterIndex: number;
    clusterLat: number;
    clusterLng: number;
    photoClusters: JourneyPoint[][];
    mapRef: import("leaflet").Map | null;
    isClusterClickScrollingRef: React.RefObject<boolean>;
    clusterClickTimeoutRef: React.RefObject<NodeJS.Timeout | null>;
    setScrollProgress: (progress: number) => void;
    setHasUserScrolled: (scrolled: boolean) => void;
    scrollTimelineToLocation: (locationIndex: number) => void;
    isMobileOrTablet: boolean;
    setTargetZoom: (zoom: number | null) => void;
    previousActiveLocationRef: React.RefObject<number>;
}

export const handleMarkerClick = ({
    clusterIndex,
    clusterLat,
    clusterLng,
    photoClusters,
    mapRef,
    isClusterClickScrollingRef,
    clusterClickTimeoutRef,
    setScrollProgress,
    setHasUserScrolled,
    scrollTimelineToLocation,
    isMobileOrTablet,
    setTargetZoom,
    previousActiveLocationRef,
}: HandleMarkerClickParams) => {
    const targetProgress = clusterIndex / Math.max(1, photoClusters.length - 1);

    if (clusterClickTimeoutRef.current) {
        clearTimeout(clusterClickTimeoutRef.current);
    }

    isClusterClickScrollingRef.current = true;
    setScrollProgress(targetProgress);
    setHasUserScrolled(true);

    // Update the previous active location to the target cluster
    previousActiveLocationRef.current = clusterIndex;

    if (mapRef?.getContainer()) {
        try {
            // Super cluster logic disabled - simple fly to target with standard zoom
            const [positionedLat, positionedLng] = getLocationPosition(
                clusterLat,
                clusterLng,
            );
            const targetZoomLevel = isMobileOrTablet ? 8 : 10;
            // Set target zoom before animation
            setTargetZoom(targetZoomLevel);

            // Clear target zoom after animation completes
            const onMoveEnd = () => {
                mapRef.off("moveend", onMoveEnd);
                setTargetZoom(null);
            };
            mapRef.once("moveend", onMoveEnd);

            mapRef.flyTo([positionedLat, positionedLng], targetZoomLevel, {
                animate: true,
                duration: 1.0,
                easeLinearity: 0.3,
            });
        } catch (error) {
            console.warn("Map operation failed:", error);
        }
    }

    setTimeout(() => {
        scrollTimelineToLocation(clusterIndex);
    }, 50);

    clusterClickTimeoutRef.current = setTimeout(() => {
        isClusterClickScrollingRef.current = false;
        clusterClickTimeoutRef.current = null;
    }, 1500);
};
