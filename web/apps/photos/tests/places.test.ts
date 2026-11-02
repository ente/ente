import type { EnteFile } from "ente-media/file";
import { createLocationIndex } from "ente-photos-wasm";
import { afterEach, expect, test, vi } from "vitest";

vi.mock("ente-photos-wasm", () => ({ createLocationIndex: vi.fn() }));

afterEach(() => {
    vi.unstubAllGlobals();
    vi.clearAllMocks();
    vi.resetModules();
});

test("loads places only for geotagged files and retries a failed dataset load", async () => {
    const fetch = vi.fn().mockRejectedValue(new Error("offline"));
    vi.stubGlobal("fetch", fetch);
    const { listPlaces } = await import("../src/services/places");
    const withoutLocation = { metadata: {} } as EnteFile;

    expect(await listPlaces([withoutLocation])).toEqual([]);
    expect(fetch).not.toHaveBeenCalled();

    const file = {
        metadata: { latitude: 1, longitude: 2 },
        pubMagicMetadata: { data: { lat: 9.93, long: 76.27 } },
    } as EnteFile;
    await expect(listPlaces([file])).rejects.toThrow("offline");

    fetch.mockImplementation(() =>
        Promise.resolve(new Response(new Uint8Array([1]))),
    );
    const secondFile = {
        metadata: { latitude: 12.97, longitude: 77.59 },
    } as EnteFile;
    const groups = [
        {
            city: {
                name: "Thiruvananthapuram",
                country: "India",
                latitude: 1,
                longitude: 2,
            },
            coordinateIndices: [1],
        },
        {
            city: {
                name: "Kochi",
                country: "India",
                latitude: 1,
                longitude: 2,
            },
            coordinateIndices: [0],
        },
    ];
    const groupCities = vi.fn().mockReturnValue({ groups });
    vi.mocked(createLocationIndex).mockResolvedValue({
        groupCities,
        free: vi.fn(),
        [Symbol.dispose]: vi.fn(),
    });

    const places = await listPlaces([withoutLocation, file, secondFile]);
    expect(places.map(({ city }) => city.name)).toEqual([
        "Kochi",
        "Thiruvananthapuram",
    ]);
    expect(groupCities).toHaveBeenCalledWith({
        coordinates: [
            { latitude: 9.93, longitude: 76.27 },
            { latitude: 12.97, longitude: 77.59 },
        ],
    });
    expect(places.map(({ coverFile }) => coverFile)).toEqual([
        file,
        secondFile,
    ]);

    await listPlaces([file]);
    expect(createLocationIndex).toHaveBeenCalledTimes(1);
    expect(fetch).toHaveBeenCalledTimes(4);
});
