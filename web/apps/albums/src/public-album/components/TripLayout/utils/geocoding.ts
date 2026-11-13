interface StadiaMapsGeocodingResponse {
    features?: {
        properties?: {
            locality?: string;
            neighbourhood?: string;
            county?: string;
            region?: string;
            name?: string;
            country?: string;
            [key: string]: unknown;
        };
        [key: string]: unknown;
    }[];
    [key: string]: unknown;
}

export interface LocationInfo {
    place: string;
    country: string;
}

export const iconCache = new Map<string, import("leaflet").DivIcon>();

export const throttle = <T extends (...args: unknown[]) => void>(
    func: T,
    delay: number,
): ((...args: Parameters<T>) => void) => {
    let timeoutId: NodeJS.Timeout | null = null;
    let lastExecTime = 0;

    return (...args: Parameters<T>) => {
        const currentTime = Date.now();

        if (currentTime - lastExecTime > delay) {
            func(...args);
            lastExecTime = currentTime;
        } else {
            if (timeoutId) clearTimeout(timeoutId);
            timeoutId = setTimeout(
                () => {
                    func(...args);
                    lastExecTime = Date.now();
                },
                delay - (currentTime - lastExecTime),
            );
        }
    };
};

export const getLocationName = async (
    lat: number,
    lng: number,
): Promise<LocationInfo> => {
    try {
        // Keep reverse-geocoding requests at place-level precision.
        const roundedLat = Math.round(lat * 100) / 100;
        const roundedLng = Math.round(lng * 100) / 100;

        const response = await fetch(
            `https://api.stadiamaps.com/geocoding/v1/reverse?point.lat=${roundedLat}&point.lon=${roundedLng}`,
        );

        if (!response.ok) {
            throw new Error(`HTTP error! status: ${response.status}`);
        }

        const data = (await response.json()) as StadiaMapsGeocodingResponse;

        const feature = data.features?.[0];
        let result: LocationInfo;

        if (feature?.properties) {
            const props = feature.properties;

            const city = props.locality || props.neighbourhood;

            const locationName =
                city || props.county || props.region || props.name || "Unknown";

            const country = props.country || "Unknown";

            result = { place: locationName, country };
        } else {
            result = { place: "Unknown", country: "Unknown" };
        }

        return result;
    } catch {
        return { place: "Unknown", country: "Unknown" };
    }
};
