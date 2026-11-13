export interface JourneyPoint {
    lat: number;
    lng: number;
    name: string;
    country: string;
    // Local timeline key, not an absolute UTC timestamp.
    timestamp: number;
    image: string;
    fileId: number;
}
