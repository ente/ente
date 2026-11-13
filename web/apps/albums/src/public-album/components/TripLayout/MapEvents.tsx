import { memo, useEffect } from "react";
import { useMap } from "react-leaflet";

interface MapEventsProps {
    setMapRef: (map: import("leaflet").Map) => void;
    setCurrentZoom: (zoom: number) => void;
    setTargetZoom: (zoom: number | null) => void;
}

export const MapEvents = memo<MapEventsProps>(
    ({ setMapRef, setCurrentZoom, setTargetZoom }) => {
        const map = useMap();

        useEffect(() => {
            setMapRef(map);

            const handleZoomEnd = () => {
                setCurrentZoom(map.getZoom());
                setTargetZoom(null);
            };

            map.on("zoomend", handleZoomEnd);

            return () => {
                map.off("zoomend", handleZoomEnd);
            };
        }, [map, setMapRef, setCurrentZoom, setTargetZoom]);

        return null;
    },
);
