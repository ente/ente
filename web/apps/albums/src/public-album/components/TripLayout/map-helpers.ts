import { haveWindow } from "ente-base/env";
import type { JourneyPoint } from "./types";
import { iconCache } from "./utils/geocoding";

const isMobileDevice = () => {
    if (typeof window === "undefined") return false;
    // Keep this aligned with MUI's md breakpoint.
    return window.innerWidth < 960;
};

// Leaflet reads window during import.
const getLeaflet = () => {
    if (haveWindow()) {
        // eslint-disable-next-line @typescript-eslint/no-require-imports
        return require("leaflet") as typeof import("leaflet");
    }
    return null;
};

// Haversine distance in kilometers.
export const calculateDistance = (
    lat1: number,
    lng1: number,
    lat2: number,
    lng2: number,
): number => {
    const R = 6371;
    const dLat = (lat2 - lat1) * (Math.PI / 180);
    const dLng = (lng2 - lng1) * (Math.PI / 180);
    const a =
        Math.sin(dLat / 2) * Math.sin(dLat / 2) +
        Math.cos(lat1 * (Math.PI / 180)) *
            Math.cos(lat2 * (Math.PI / 180)) *
            Math.sin(dLng / 2) *
            Math.sin(dLng / 2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    return R * c;
};

export const clusterPhotosByProximity = (photos: JourneyPoint[]) => {
    if (photos.length === 0) return [];

    // Approximate five kilometers in coordinate degrees.
    const distanceThreshold = 0.05;

    // Never cluster photos across local calendar days.
    const photosByDay = new Map<string, JourneyPoint[]>();
    photos.forEach((photo) => {
        const date = new Date(photo.timestamp);
        const dayKey = `${date.getFullYear()}-${date.getMonth()}-${date.getDate()}`;

        if (!photosByDay.has(dayKey)) {
            photosByDay.set(dayKey, []);
        }
        photosByDay.get(dayKey)!.push(photo);
    });

    const allClusters: JourneyPoint[][] = [];

    photosByDay.forEach((dayPhotos) => {
        const visited = new Set<number>();

        dayPhotos.forEach((photo, i) => {
            if (visited.has(i)) return;

            const cluster = [photo];
            visited.add(i);

            dayPhotos.forEach((otherPhoto, j) => {
                if (i === j || visited.has(j)) return;

                const distance = Math.sqrt(
                    Math.pow(photo.lat - otherPhoto.lat, 2) +
                        Math.pow(photo.lng - otherPhoto.lng, 2),
                );

                if (distance < distanceThreshold) {
                    cluster.push(otherPhoto);
                    visited.add(j);
                }
            });

            allClusters.push(cluster);
        });
    });

    return allClusters;
};

export const calculateOptimalZoom = (): number => {
    return 10;
};

export const createIcon = (
    imageSrc: string,
    size = 40,
    borderColor = "#ffffff",
    _clusterCount?: number,
    isReached = false,
): import("leaflet").DivIcon | null => {
    const leaflet = getLeaflet();
    if (typeof window === "undefined" || !leaflet) {
        return null;
    }

    const pinSize = size + 16;
    const triangleHeight = size <= 30 ? 7 : 10;
    const pinHeight = pinSize + triangleHeight + 2;
    const hasImage = imageSrc && imageSrc.trim() !== "";

    const outerBorderRadius = size <= 30 ? 14 : 16;
    const innerBorderRadius = size <= 30 ? 10 : 12;

    const cacheKey = `icon_${imageSrc}_${size}_${borderColor}_${isReached}_${outerBorderRadius}_${innerBorderRadius}_${triangleHeight}`;

    const cachedIcon = iconCache.get(cacheKey);
    if (cachedIcon) {
        return cachedIcon;
    }

    const icon = leaflet.divIcon({
        html: `
        <div class="photo-pin${isReached ? " reached" : ""}" style="
          width: ${pinSize}px;
          height: ${pinHeight}px;
          position: relative;
          cursor: pointer;
          transition: all 0.3s ease;
        ">
          <div style="
            width: ${pinSize}px;
            height: ${pinSize}px;
            border-radius: ${outerBorderRadius}px;
            background: ${isReached ? "#22c55e" : "white"};
            border: 2px solid ${isReached ? "#22c55e" : borderColor};
            padding: 4px;
            position: relative;
            overflow: hidden;
            transition: background-color 0.3s ease, border-color 0.3s ease;
          "
          onmouseover="this.style.background='#22c55e'; this.style.borderColor='#22c55e'; this.nextElementSibling.style.borderTopColor='#22c55e';"
          onmouseout="this.style.background='${isReached ? "#22c55e" : "white"}'; this.style.borderColor='${isReached ? "#22c55e" : "#ffffff"}'; this.nextElementSibling.style.borderTopColor='${isReached ? "#22c55e" : "white"}';"
          >
            ${
                hasImage
                    ? `
              <img
                src="${imageSrc}"
                style="
                  width: 100%;
                  height: 100%;
                  object-fit: cover;
                  border-radius: ${innerBorderRadius}px;
                "
                alt="Location"
              />
            `
                    : `
              <div style="
                width: 100%;
                height: 100%;
                border-radius: ${innerBorderRadius}px;
                animation: skeleton-pulse 1.5s ease-in-out infinite;
              "></div>
              <style>
                @keyframes skeleton-pulse {
                  0% { background-color: #ffffff; }
                  50% { background-color: #f0f0f0; }
                  100% { background-color: #ffffff; }
                }
              </style>
            `
            }
          </div>
          <div style="
            position: absolute;
            bottom: 2px;
            left: 50%;
            transform: translateX(-50%);
            width: 0;
            height: 0;
            border-left: ${triangleHeight}px solid transparent;
            border-right: ${triangleHeight}px solid transparent;
            border-top: ${triangleHeight}px solid ${isReached ? "#22c55e" : "white"};
            transition: border-top-color 0.3s ease;
          "></div>
        </div>
      `,
        className: "custom-pin-marker",
        iconSize: [pinSize, pinHeight],
        iconAnchor: [pinSize / 2, pinHeight],
        popupAnchor: [0, -pinHeight],
    });

    iconCache.set(cacheKey, icon);
    return icon;
};

// Offset markers right to leave room for the desktop timeline.
// The constants below are tuned around zoom level 10.
export const getMapCenter = (
    photoClusters: JourneyPoint[][],
    journeyData: JourneyPoint[],
): [number, number] => {
    if (photoClusters.length === 0) {
        const firstPoint = journeyData[0];
        if (!firstPoint) return [0, 0];
        return [firstPoint.lat, firstPoint.lng];
    }

    const firstCluster = photoClusters[0];
    if (!firstCluster || firstCluster.length === 0) return [0, 0];

    const firstLat =
        firstCluster.reduce((sum, p) => sum + p.lat, 0) / firstCluster.length;
    const firstLng =
        firstCluster.reduce((sum, p) => sum + p.lng, 0) / firstCluster.length;

    return offsetLocation(firstLat, firstLng);
};

export const getLocationPosition = (
    lat: number,
    lng: number,
): [number, number] => offsetLocation(lat, lng);

const offsetLocation = (lat: number, lng: number): [number, number] => {
    const isMobile = isMobileDevice();
    const timelineWidthRatio = isMobile ? 0.0 : 0.5;
    const degreesPerPixelAtZoom10 = 0.35 / 1000;

    const basePixelsToShift =
        (window.innerWidth || 1400) * (1 - timelineWidthRatio);
    const pixelsToShiftFor20Percent = isMobile
        ? basePixelsToShift * 0.6
        : basePixelsToShift * 3.0;
    const lngShift = pixelsToShiftFor20Percent * degreesPerPixelAtZoom10;

    return [lat, lng - lngShift];
};
