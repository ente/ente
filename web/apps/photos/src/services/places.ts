import { HTTPError } from "ente-base/http";
import type { EnteFile } from "ente-media/file";
import { fileLocation } from "ente-media/file-metadata";
import { createLocationIndex } from "ente-photos-wasm";

let locationIndex: ReturnType<typeof createLocationIndex> | undefined;

export const listPlaces = async (files: EnteFile[]) => {
    const locatedFiles = files.flatMap((file) => {
        const coordinate = fileLocation(file);
        return coordinate ? [{ file, coordinate }] : [];
    });
    if (!locatedFiles.length) return [];

    const index = await (locationIndex ??= Promise.all([
        fetchLocationData("cities.bin"),
        fetchLocationData("urban-centres.bin"),
    ])
        .then(([cities, urbanCenters]) =>
            createLocationIndex(cities, urbanCenters),
        )
        .catch((error: unknown) => {
            locationIndex = undefined;
            throw error;
        }));

    return index
        .groupCities({
            coordinates: locatedFiles.map(({ coordinate }) => coordinate),
        })
        .groups.map((group) => ({
            ...group,
            coverFile: locatedFiles[group.coordinateIndices[0] ?? -1]?.file,
        }))
        .sort((a, b) => a.city.name.localeCompare(b.city.name));
};

const fetchLocationData = async (name: string) => {
    const response = await fetch(`https://assets.ente.com/location/v2/${name}`);
    if (!response.ok) throw new HTTPError(response);
    return new Uint8Array(await response.arrayBuffer());
};
