import {
    parseDateFromDigitGroups,
    tryParseEpochMicrosecondsFromFileName,
} from "ente-gallery/services/upload/date";
import {
    matchJSONMetadata,
    metadataJSONMapKeyForJSON,
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
        "PXL_20240827_094331806.PORTRAIT(1).jpg",
        "PXL_20240827_094331806.PORTRAIT.jpg.supplement(1).json",
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
});
