import { haveWindow } from "ente-base/env";

// Leaflet reads window during import.
export const getLeaflet = () => {
    if (!haveWindow()) return null;
    // eslint-disable-next-line @typescript-eslint/no-require-imports
    return require("leaflet") as typeof import("leaflet");
};

export const getLeafletWithDefaultIcons = () => {
    if (!haveWindow()) return null;
    // eslint-disable-next-line @typescript-eslint/no-require-imports
    require("leaflet-defaulticon-compatibility");
    return getLeaflet();
};
