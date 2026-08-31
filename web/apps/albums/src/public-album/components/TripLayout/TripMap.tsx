import { Box, styled, useMediaQuery, useTheme } from "@mui/material";
import "leaflet/dist/leaflet.css";
import { useEffect, useState } from "react";

import { MapEvents } from "./MapEvents";
import { createIcon, getMapCenter } from "./map-helpers";
import type { JourneyPoint } from "./types";

interface MapComponentsType {
    MapContainer: typeof import("react-leaflet").MapContainer;
    TileLayer: typeof import("react-leaflet").TileLayer;
    Marker: typeof import("react-leaflet").Marker;
}

interface TripMapProps {
    journeyData: JourneyPoint[];
    photoClusters: JourneyPoint[][];
    hasPhotoData: boolean;
    optimalZoom: number;
    scrollProgress: number;
    setMapRef: (map: import("leaflet").Map | null) => void;
    setCurrentZoom: (zoom: number) => void;
    setTargetZoom: (zoom: number | null) => void;
    onMarkerClick: (
        clusterIndex: number,
        clusterLat: number,
        clusterLng: number,
    ) => void;
}

export const TripMap: React.FC<TripMapProps> = ({
    journeyData,
    photoClusters,
    hasPhotoData,
    optimalZoom,
    scrollProgress,
    setMapRef,
    setCurrentZoom,
    setTargetZoom,
    onMarkerClick,
}) => {
    const theme = useTheme();
    const isMobileOrTablet = useMediaQuery(theme.breakpoints.down("md"));

    // Leaflet must be loaded client-side.
    const [mapComponents, setMapComponents] =
        useState<MapComponentsType | null>(null);

    useEffect(() => {
        void import("react-leaflet")
            .then((mod) => {
                setMapComponents({
                    MapContainer: mod.MapContainer,
                    TileLayer: mod.TileLayer,
                    Marker: mod.Marker,
                });
            })
            .catch((error: unknown) => {
                console.error("Failed to load react-leaflet:", error);
            });
    }, []);

    let currentActiveLocationIndex = -1;
    if (photoClusters.length > 0) {
        if (isMobileOrTablet) {
            // Mobile keeps each location active longer.
            currentActiveLocationIndex = Math.floor(
                scrollProgress * (photoClusters.length - 0.5),
            );
        } else {
            currentActiveLocationIndex = Math.round(
                scrollProgress * Math.max(0, photoClusters.length - 1),
            );
        }
    }

    const visibleClustersWithIndices = photoClusters.map(
        (cluster, originalIndex) => ({ cluster, originalIndex }),
    );

    if (!mapComponents) {
        return <MapContainerWrapper hasPhotoData={false} />;
    }

    const { MapContainer, TileLayer, Marker } = mapComponents;

    return (
        <MapContainerWrapper hasPhotoData={hasPhotoData}>
            {hasPhotoData ? (
                <MapContainer
                    center={getMapCenter(photoClusters, journeyData)}
                    zoom={
                        isMobileOrTablet
                            ? Math.max(1, optimalZoom - 2)
                            : optimalZoom
                    }
                    scrollWheelZoom={true}
                    zoomControl={false}
                    attributionControl={!isMobileOrTablet}
                    style={{ width: "100%", height: "100%" }}
                >
                    <MapEvents
                        setMapRef={setMapRef}
                        setCurrentZoom={setCurrentZoom}
                        setTargetZoom={setTargetZoom}
                    />
                    <TileLayer
                        attribution={
                            isMobileOrTablet
                                ? ""
                                : '&copy; <a href="https://stadiamaps.com/" target="_blank" rel="noopener noreferrer">Stadia Maps</a>, &copy; <a href="https://openmaptiles.org/" target="_blank" rel="noopener noreferrer">OpenMapTiles</a> &copy; <a href="http://openstreetmap.org" target="_blank" rel="noopener noreferrer">OpenStreetMap</a> contributors'
                        }
                        url="https://tiles.stadiamaps.com/tiles/alidade_satellite/{z}/{x}/{y}{r}.jpg"
                        maxZoom={20}
                        updateWhenZooming={true}
                        keepBuffer={isMobileOrTablet ? 3 : 1}
                    />

                    {visibleClustersWithIndices.map((item, index) => {
                        const { cluster, originalIndex } = item;
                        const firstPhoto = cluster[0];
                        if (!firstPhoto) return null;
                        const avgLat =
                            cluster.reduce((sum, p) => sum + p.lat, 0) /
                            cluster.length;
                        const avgLng =
                            cluster.reduce((sum, p) => sum + p.lng, 0) /
                            cluster.length;

                        const originalClusterIndex = originalIndex;
                        const isActive =
                            originalClusterIndex === currentActiveLocationIndex;

                        const icon = createIcon(
                            firstPhoto.image,
                            isMobileOrTablet ? 30 : 55,
                            "#ffffff",
                            cluster.length,
                            isActive,
                        );

                        return icon ? (
                            <Marker
                                key={`cluster-${index}`}
                                position={[avgLat, avgLng]}
                                icon={icon}
                                zIndexOffset={isActive ? 1000 : 0}
                                eventHandlers={{
                                    click: () => {
                                        const avgLat =
                                            cluster.reduce(
                                                (sum, p) => sum + p.lat,
                                                0,
                                            ) / cluster.length;
                                        const avgLng =
                                            cluster.reduce(
                                                (sum, p) => sum + p.lng,
                                                0,
                                            ) / cluster.length;
                                        onMarkerClick(
                                            originalClusterIndex,
                                            avgLat,
                                            avgLng,
                                        );
                                    },
                                }}
                            />
                        ) : null;
                    })}
                </MapContainer>
            ) : null}
        </MapContainerWrapper>
    );
};

const MapContainerWrapper = styled(Box, {
    shouldForwardProp: (prop) => prop !== "hasPhotoData",
})<{ hasPhotoData: boolean }>(({ hasPhotoData }) => ({
    width: "100%",
    height: "100%",
    backgroundColor: hasPhotoData ? "transparent" : "#000000",
}));
