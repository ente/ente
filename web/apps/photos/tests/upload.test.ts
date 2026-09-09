import type { RawExifTags } from "ente-gallery/services/exif";
import {
    parseDateFromDigitGroups,
    tryParseEpochMicrosecondsFromFileName,
} from "ente-gallery/services/upload/date";
import {
    matchJSONMetadata,
    metadataJSONMapKeyForJSON,
    metadataJSONMapKeyForXMP,
    parseXMPSidecarTags,
    tryParseXMPSidecar,
} from "ente-gallery/services/upload/metadata-json";
import { describe, expect, test } from "vitest";

const dateCases = [
    ["Screenshot_20220807-195908_Firefox", "2022-08-07 19:59:08"],
    ["Screenshot_20220507-195908", "2022-05-07 19:59:08"],
    ["2022-02-18 16.00.12-DCMX.png", "2022-02-18 16:00:12"],
    ["20221107_231730", "2022-11-07 23:17:30"],
    ["2020-11-01 02.31.02", "2020-11-01 02:31:02"],
    ["IMG_20210921_144423", "2021-09-21 14:44:23"],
    ["2019-10-31 155703", "2019-10-31 00:00:00"],
    ["IMG_20210921_144423_783", "2021-09-21 14:44:23"],
    [
        "Screenshot_2022-06-21-16-51-29-164_newFormat.heic",
        "2022-06-21 16:51:29",
    ],
    [
        "Screenshot 20221106 211633.com.google.android.apps.nbu.paisa.user.jpg",
        "2022-11-06 21:16:33",
    ],
    ["signal-2022-12-17-15-16-04-718.jpg", "2022-12-17 15:16:04"],
] as const;

const epochMicrosecondCases = [
    ["20170923_220934000_iOS.jpg", "2017-09-23 22:09:34"],
] as const;

const unparseableDateFileNames = [
    "Snapchat-431959199.mp4.",
    "Snapchat-400000000.mp4",
    "Snapchat-900000000.mp4",
    "Snapchat-100-10-20-19-15-12",
] as const;

const metadataCases = [
    ["IMG20210211125718-edited.jpg", "IMG20210211125718.jpg.json"],
    ["IMG20210211174722.jpg", "IMG20210211174722.jpg.json"],
    [
        "21345678901234567890123456789012345678901234567.png",
        "2134567890123456789012345678901234567890123456.json",
    ],
    ["IMG20210211174722(1).jpg", "IMG20210211174722.jpg(1).json"],
    ["IMG2021021(4455)74722(1).jpg", "IMG2021021(4455)74722.jpg(1).json"],
    ["IMG2021021.json74722(1).jpg", "IMG2021021.json74722.jpg(1).json"],
    ["IMG2021021(1)74722(1).jpg", "IMG2021021(1)74722.jpg(1).json"],
    ["IMG_1159.HEIC", "IMG_1159.HEIC.supplemental-metadata.json"],
    [
        "PXL_20241231_151646544.MP.jpg",
        "PXL_20241231_151646544.MP.jpg.supplemental-met.json",
    ],
    [
        "PXL_20241231_151646544.MP.jpg",
        "PXL_20241231_151646544.MP.jpg.supplemental-metadata.json",
    ],
    [
        "PXL_20240827_094331806.PORTRAIT(1).jpg",
        "PXL_20240827_094331806.PORTRAIT.jpg.supplement(1).json",
    ],
    [
        "PXL_20240827_094331806.PORTRAIT(1).jpg",
        "PXL_20240827_094331806.PORTRAIT.jpg.supplemental-metadata(1).json",
    ],
    [
        "PXL_20240827_094331806.PORTRAIT(1).jpg",
        "PXL_20240827_094331806.PORTRAIT(1).jpg.supplemental-metadata.json",
    ],
    [
        "PXL_20240506_142610305.LONG_EXPOSURE-01.COVER.jpg",
        "PXL_20240506_142610305.LONG_EXPOSURE-01.COVER..json",
    ],
    [
        "PXL_20211120_223243932.MOTION-02.ORIGINAL.jpg",
        "PXL_20211120_223243932.MOTION-02.ORIGINAL.jpg..json",
    ],
    [
        "20220322_205147-edited(1).jpg",
        "20220322_205147.jpg.supplemental-metadata(1).json",
    ],
    ["skytree (2).jpg", "skytree (2).jpg.supplemental-metadata.json"],
] as const;

const formatLocalDateTime = (date: Date | undefined) => {
    if (!date) throw new Error("Expected date to parse");

    const year = date.getFullYear();
    const month = formatTwoDigits(date.getMonth() + 1);
    const day = formatTwoDigits(date.getDate());
    const hour = formatTwoDigits(date.getHours());
    const minute = formatTwoDigits(date.getMinutes());
    const second = formatTwoDigits(date.getSeconds());

    return `${year}-${month}-${day} ${hour}:${minute}:${second}`;
};

const formatTwoDigits = (value: number) => value.toString().padStart(2, "0");

const xmpTag = (value: string) => ({
    value,
    description: value,
    attributes: {},
});

const xmpDescriptionTag = (description: string) => ({
    value: [xmpTag(description)],
    description,
    attributes: {},
});

describe("upload filename metadata", () => {
    test.each(dateCases)("parses %s", (fileName, expected) => {
        expect(formatLocalDateTime(parseDateFromDigitGroups(fileName))).toBe(
            expected,
        );
    });

    test.each(epochMicrosecondCases)(
        "parses epoch microseconds from %s",
        (fileName, expected) => {
            const epochMicroseconds =
                tryParseEpochMicrosecondsFromFileName(fileName);
            if (epochMicroseconds == undefined)
                throw new Error("Expected epoch microseconds to parse");

            expect(
                formatLocalDateTime(new Date(epochMicroseconds / 1000)),
            ).toBe(expected);
        },
    );

    test.each(unparseableDateFileNames)("does not parse %s", (fileName) => {
        expect(parseDateFromDigitGroups(fileName)).toBeUndefined();
    });

    test.each(metadataCases)("matches %s to %s", (fileName, jsonFileName) => {
        const metadata = { description: fileName };
        const map = new Map([
            [metadataJSONMapKeyForJSON(undefined, 0, jsonFileName), metadata],
        ]);

        expect(matchJSONMetadata(undefined, 0, fileName, map)).toBe(metadata);
    });

    test.each([
        [
            "PXL_20241231_151646544.MP.jpg",
            "PXL_20241231_151646544.MP.jpg.supplemental-metadata.json",
            "PXL_20241231_151646544.MP.jpg.supplemental-met.json",
        ],
        [
            "PXL_20240827_094331806.PORTRAIT(1).jpg",
            "PXL_20240827_094331806.PORTRAIT.jpg.supplemental-metadata(1).json",
            "PXL_20240827_094331806.PORTRAIT.jpg.supplement(1).json",
        ],
        [
            "PXL_20240827_094331806.PORTRAIT(1).jpg",
            "PXL_20240827_094331806.PORTRAIT(1).jpg.supplemental-metadata.json",
            "PXL_20240827_094331806.PORTRAIT(1).jpg.supplem.json",
        ],
        [
            "PXL_20240827_094331806.PORTRAIT(1).jpg",
            "PXL_20240827_094331806.PORTRAIT.jpg.supplemental-metadata(1).json",
            "PXL_20240827_094331806.PORTRAIT(1).jpg.supplem.json",
        ],
        [
            "PXL_20240827_094331806.PORTRAIT(1).jpg",
            "PXL_20240827_094331806.PORTRAIT(1).jpg.supplemental-metadata.json",
            "PXL_20240827_094331806.PORTRAIT.jpg.supplement(1).json",
        ],
    ])(
        "for %s uses %s only when %s is absent",
        (fileName, fullJSONFileName, clippedJSONFileName) => {
            const fullMetadata = { description: "full" };
            const clippedMetadata = { description: "clipped" };
            const map = new Map([
                [
                    metadataJSONMapKeyForJSON(undefined, 0, fullJSONFileName),
                    fullMetadata,
                ],
                [
                    metadataJSONMapKeyForJSON(
                        undefined,
                        0,
                        clippedJSONFileName,
                    ),
                    clippedMetadata,
                ],
            ]);

            expect(matchJSONMetadata(undefined, 0, fileName, map)).toBe(
                clippedMetadata,
            );

            map.delete(
                metadataJSONMapKeyForJSON(undefined, 0, clippedJSONFileName),
            );
            expect(matchJSONMetadata(undefined, 0, fileName, map)).toBe(
                fullMetadata,
            );
        },
    );
});

describe("Apple Photos XMP sidecars", () => {
    test("parses a wrapperless sidecar with a BOM and XML declaration", async () => {
        const sidecar = new File(
            [
                `\uFEFF  <?xml version="1.0" encoding="UTF-8"?>
<x:xmpmeta xmlns:x="adobe:ns:meta/" xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#" xmlns:photoshop="http://ns.adobe.com/photoshop/1.0/">
    <rdf:RDF>
        <rdf:Description photoshop:DateCreated="2023-04-27T14:51:16+05:30" />
    </rdf:RDF>
</x:xmpmeta>`,
            ],
            "278.xmp",
        );

        await expect(tryParseXMPSidecar(sidecar)).resolves.toMatchObject({
            creationDate: {
                dateTime: "2023-04-27T14:51:16.000",
                offset: "+05:30",
            },
        });
    });

    test("parses DateCreated with an offset", () => {
        const metadata = parseXMPSidecarTags({
            xmp: { DateCreated: xmpTag("2023-04-27T14:51:16+05:30") },
        });

        expect(metadata?.creationDate).toMatchObject({
            dateTime: "2023-04-27T14:51:16.000",
            offset: "+05:30",
        });
        expect(metadata?.creationTime).toBe(metadata?.creationDate?.timestamp);
    });

    test("parses a Z offset date", () => {
        expect(
            parseXMPSidecarTags({
                xmp: { DateCreated: xmpTag("2023-04-27T09:21:16Z") },
            })?.creationDate,
        ).toMatchObject({ dateTime: "2023-04-27T09:21:16.000", offset: "Z" });
    });

    test("prefers DateTimeOriginal over DateCreated", () => {
        expect(
            parseXMPSidecarTags({
                xmp: {
                    DateTimeOriginal: xmpTag("2022-01-02T03:04:05Z"),
                    DateCreated: xmpTag("2023-04-27T09:21:16Z"),
                },
            })?.creationDate?.dateTime,
        ).toBe("2022-01-02T03:04:05.000");
    });

    test.each([
        ["12.97236N", "77.59457E", 12.97236, 77.59457],
        ["33.8688S", "151.2093W", -33.8688, -151.2093],
        ["37,46.5N", "122,25W", 37.775, -(122 + 25 / 60)],
        ["33,52.128S", "151,12.558E", -(33 + 52.128 / 60), 151 + 12.558 / 60],
    ])("parses GPS coordinates %s, %s", (lat, long, latitude, longitude) => {
        expect(
            parseXMPSidecarTags({
                xmp: { GPSLatitude: xmpTag(lat), GPSLongitude: xmpTag(long) },
            })?.location,
        ).toEqual({ latitude, longitude });
    });

    test.each([
        [
            "8.5683539130357",
            "N",
            "76.873247987321",
            "E",
            8.5683539130357,
            76.873247987321,
        ],
        ["33.448889", "S", "70.669265", "W", -33.448889, -70.669265],
    ])(
        "parses decimal GPS coordinates with separate %s/%s references",
        (lat, latRef, long, longRef, latitude, longitude) => {
            expect(
                parseXMPSidecarTags({
                    xmp: {
                        GPSLatitude: xmpTag(lat),
                        GPSLatitudeRef: xmpTag(latRef),
                        GPSLongitude: xmpTag(long),
                        GPSLongitudeRef: xmpTag(longRef),
                    },
                })?.location,
            ).toEqual({ latitude, longitude });
        },
    );

    test("omits a location with only one GPS axis", () => {
        expect(
            parseXMPSidecarTags({ xmp: { GPSLatitude: xmpTag("12.97236N") } }),
        ).toBeUndefined();
    });

    test("parses the caption", () => {
        expect(
            parseXMPSidecarTags({
                xmp: { description: xmpDescriptionTag("Sunset at the lake") },
            })?.description,
        ).toBe("Sunset at the lake");
    });

    test.each([{ xmp: {} }, {}] satisfies RawExifTags[])(
        "ignores empty tags",
        (tags) => {
            expect(parseXMPSidecarTags(tags)).toBeUndefined();
        },
    );

    test("keys and matches sidecars by original stem and upload scope", () => {
        const metadata = { description: "original" };
        const duplicateMetadata = { description: "duplicate" };
        const uppercaseMetadata = { description: "uppercase" };
        const jsonMetadata = { description: "json" };
        const map = new Map([
            [metadataJSONMapKeyForXMP(undefined, 0, "IMG_1234.xmp"), metadata],
            [
                metadataJSONMapKeyForXMP(undefined, 0, "IMG_1234 (1).xmp"),
                duplicateMetadata,
            ],
            [
                metadataJSONMapKeyForXMP(undefined, 0, "IMG_9.XMP"),
                uppercaseMetadata,
            ],
            [
                metadataJSONMapKeyForJSON(undefined, 0, "photo.json"),
                jsonMetadata,
            ],
        ]);

        expect(matchJSONMetadata(undefined, 0, "IMG_1234.HEIC", map)).toBe(
            metadata,
        );
        expect(matchJSONMetadata(undefined, 0, "IMG_1234.MOV", map)).toBe(
            metadata,
        );
        expect(matchJSONMetadata(undefined, 0, "IMG_1234 (1).HEIC", map)).toBe(
            duplicateMetadata,
        );
        expect(matchJSONMetadata("other", 0, "IMG_1234.HEIC", map)).toBe(
            undefined,
        );
        expect(matchJSONMetadata(undefined, 1, "IMG_1234.HEIC", map)).toBe(
            undefined,
        );
        expect(matchJSONMetadata(undefined, 0, "photo.jpg", map)).toBe(
            undefined,
        );
        expect(matchJSONMetadata(undefined, 0, "IMG_9.HEIC", map)).toBe(
            uppercaseMetadata,
        );
    });
});
