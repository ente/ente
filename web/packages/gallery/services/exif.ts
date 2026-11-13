import { inWorker } from "ente-base/env";
import {
    parseMetadataDate,
    type ParsedMetadata,
    type ParsedMetadataDate,
} from "ente-media/file-metadata";
import ExifReader from "exifreader";

export const extractExif = async (file: File) =>
    await extractRawExif(file).then(parseExif);

export const parseExif = (tags: RawExifTags) => {
    const location = parseLocation(tags);
    const creationDate = parseCreationDate(tags);
    const dimensions = parseDimensions(tags);
    const description = parseDescription(tags);
    const camera = parseCamera(tags);

    const metadata: ParsedMetadata = dimensions ?? {};
    if (creationDate) metadata.creationDate = creationDate;
    if (location) metadata.location = location;
    if (description) metadata.description = description;
    if (camera?.make) metadata.cameraMake = camera.make;
    if (camera?.model) metadata.cameraModel = camera.model;
    return metadata;
};

const parseLocation = (tags: RawExifTags) => {
    const latitude = tags.gps?.Latitude;
    const longitude = tags.gps?.Longitude;

    if (latitude === undefined || longitude === undefined) return undefined;
    if (Number.isNaN(latitude) || Number.isNaN(longitude)) return undefined;

    return { latitude, longitude };
};

const parseCreationDate = (tags: RawExifTags) => {
    const { DateTimeOriginal, DateTimeDigitized, MetadataDate, DateTime } =
        parseDates(tags);
    return DateTimeOriginal ?? DateTimeDigitized ?? MetadataDate ?? DateTime;
};

interface ParsedExifDates {
    DateTimeOriginal: ParsedMetadataDate | undefined;
    DateTimeDigitized: ParsedMetadataDate | undefined;
    DateTime: ParsedMetadataDate | undefined;
    MetadataDate: ParsedMetadataDate | undefined;
}

export const extractExifDates = (file: File): Promise<ParsedExifDates> =>
    extractRawExif(file).then(parseDates);

const parseDates = (tags: RawExifTags) => {
    const valid = (d: ParsedMetadataDate | undefined) => {
        // Real files use epoch zero and year 4501 as corrupt sentinel dates.
        if (!d?.timestamp) return undefined;
        if (d.dateTime === "4501-01-01T00:00:00.000") return undefined;
        return d;
    };

    const exif = parseExifDates(tags);
    const iptc = parseIPTCDates(tags);
    const xmp = parseXMPDates(tags);

    return {
        DateTimeOriginal:
            valid(xmp.DateTimeOriginal) ??
            valid(iptc.DateTimeOriginal) ??
            valid(exif.DateTimeOriginal) ??
            valid(xmp.DateCreated),
        DateTimeDigitized:
            valid(xmp.DateTimeDigitized) ??
            valid(iptc.DateTimeDigitized) ??
            valid(exif.DateTimeDigitized) ??
            valid(xmp.CreateDate),
        DateTime: valid(xmp.DateTime ?? exif.DateTime ?? xmp.ModifyDate),
        MetadataDate: valid(xmp.MetadataDate),
    };
};

const parseExifDates = ({ exif }: RawExifTags) => ({
    DateTimeOriginal: parseExifDate(
        exif?.DateTimeOriginal,
        exif?.SubSecTimeOriginal,
        exif?.OffsetTimeOriginal,
    ),
    DateTimeDigitized: parseExifDate(
        exif?.DateTimeDigitized,
        exif?.SubSecTimeDigitized,
        exif?.OffsetTimeDigitized,
    ),
    DateTime: parseExifDate(exif?.DateTime, exif?.SubSecTime, exif?.OffsetTime),
});

const parseExifDate = (
    dateTag: ExifReader.StringArrayTag | undefined,
    subSecTag: ExifReader.StringArrayTag | undefined,
    offsetTag: ExifReader.StringArrayTag | undefined,
) => {
    const [dateString] = dateTag?.value ?? [];
    if (!dateString) return undefined;

    const [subSecString] = subSecTag?.value ?? [];
    const [offsetString] = offsetTag?.value ?? [];

    // Without an offset, Date intentionally interprets the camera time as local.
    return parseMetadataDate(
        dateString.replace(":", "-").replace(":", "-").replace(" ", "T") +
            (subSecString ? "." + subSecString : "") +
            (offsetString ?? ""),
    );
};

const parseXMPDates = ({ xmp }: RawExifTags) => ({
    DateTimeOriginal: parseXMPDate(xmp?.DateTimeOriginal),
    DateTimeDigitized: parseXMPDate(xmp?.DateTimeDigitized),
    DateTime: parseXMPDate(xmp?.DateTime),
    CreateDate: parseXMPDate(xmp?.CreateDate),
    ModifyDate: parseXMPDate(xmp?.ModifyDate),
    MetadataDate: parseXMPDate(xmp?.MetadataDate),
    DateCreated: parseXMPDate(xmp?.DateCreated),
});

const parseXMPDate = (xmpTag: ExifReader.XmpTag | undefined) => {
    if (!xmpTag) return undefined;
    const s = xmpTag.value;
    if (typeof s != "string") return undefined;

    return parseMetadataDate(s);
};

const parseIPTCDates = ({ iptc }: RawExifTags) => ({
    DateTimeOriginal: parseIPTCDate(
        iptc?.["Date Created"],
        iptc?.["Time Created"],
    ),
    DateTimeDigitized: parseIPTCDate(
        iptc?.["Digital Creation Date"],
        iptc?.["Digital Creation Time"],
    ),
});

const parseIPTCDate = (
    dateTag: ExifReader.NumberArrayTag | undefined,
    timeTag: ExifReader.NumberArrayTag | undefined,
) => {
    if (!dateTag) return undefined;
    let s = dateTag.description;

    if (timeTag) s = s + "T" + timeTag.description;

    return parseMetadataDate(s);
};

const parseDimensions = (tags: RawExifTags) => {
    const pair = (w: number | undefined, h: number | undefined) =>
        w && h ? { width: w, height: h } : undefined;

    // Orientations 5-8 swap the displayed width and height.
    const shouldSwapForExifOrientation = (orientation: number | undefined) => {
        switch (orientation) {
            case 5:
            case 6:
            case 7:
            case 8:
                return true;
            default:
                return false;
        }
    };

    const shouldSwapForXMPOrientation = (
        orientation: ExifReader.XmpTag["value"] | undefined,
    ) => {
        if (typeof orientation != "string") return false;
        switch (orientation) {
            case "5":
            case "6":
            case "7":
            case "8":
                return true;
            default:
                return false;
        }
    };

    let wh =
        pair(
            tags.file?.["Image Width"]?.value,
            tags.file?.["Image Height"]?.value,
        ) ??
        pair(
            tags.pngFile?.["Image Width"]?.value,
            tags.pngFile?.["Image Height"]?.value,
        ) ??
        pair(
            tags.gif?.["Image Width"]?.value,
            tags.gif?.["Image Height"]?.value,
        ) ??
        pair(tags.riff?.ImageWidth?.value, tags.riff?.ImageHeight?.value);
    if (wh) {
        const shouldSwap =
            shouldSwapForExifOrientation(tags.exif?.Orientation?.value) ||
            (tags.exif?.Orientation?.value == undefined &&
                shouldSwapForXMPOrientation(tags.xmp?.Orientation?.value));
        return shouldSwap ? { width: wh.height, height: wh.width } : wh;
    }

    wh =
        pair(tags.exif?.ImageWidth?.value, tags.exif?.ImageLength?.value) ??
        pair(
            tags.exif?.PixelXDimension?.value,
            tags.exif?.PixelYDimension?.value,
        );
    if (wh) {
        const swap = shouldSwapForExifOrientation(
            tags.exif?.Orientation?.value,
        );

        return swap ? { width: wh.height, height: wh.width } : wh;
    }

    wh =
        pair(
            parseXMPNum(tags.xmp?.ImageWidth),
            parseXMPNum(tags.xmp?.ImageLength),
        ) ??
        pair(
            parseXMPNum(tags.xmp?.PixelXDimension),
            parseXMPNum(tags.xmp?.PixelYDimension),
        );

    if (wh) {
        const swap = shouldSwapForXMPOrientation(tags.xmp?.Orientation?.value);

        return swap ? { width: wh.height, height: wh.width } : wh;
    }

    return undefined;
};

const parseXMPNum = (xmpTag: ExifReader.XmpTag | undefined) => {
    if (!xmpTag) return undefined;
    const s = xmpTag.value;
    if (typeof s != "string") return undefined;

    const n = parseInt(s, 10);
    if (isNaN(n)) return undefined;
    return n;
};

export type RawExifTags = Omit<ExifReader.ExpandedTags, "Thumbnail" | "xmp"> & {
    xmp?: ExifReader.XmpTags;
};

export const extractRawExif = async (blob: Blob): Promise<RawExifTags> => {
    // ExifReader needs DOMParser for XMP; its optional worker polyfill is absent.
    if (inWorker())
        throw new Error("DOMParser is not available in web workers");

    // Preserve namespaces, but do not include unknown tags with unbounded payloads.
    const tags = await ExifReader.load(await blob.arrayBuffer(), {
        async: true,
        expanded: true,
    });

    // Never retain embedded image payloads in metadata JSON.
    delete tags.Thumbnail;
    delete tags.exif?.Thumbnail;

    // MPF entries can contain more embedded images.
    delete (tags as Record<string, unknown>).mpf;

    // Parsed XMP entries already retain the useful data.
    delete (tags.xmp as Partial<typeof tags.xmp>)?._raw;

    return tags;
};

export const tagNumericValue = (
    tag: ExifReader.NumberTag | ExifReader.NumberArrayTag,
) => {
    const v = tag.value;
    return Array.isArray(v) ? (v[0] ?? 0) / (v[1] ?? 1) : v;
};

const parseCamera = (tags: RawExifTags) => {
    const makeDescription = tags.exif?.Make?.description;
    const modelDescription = tags.exif?.Model?.description;
    const make = makeDescription?.trim();
    const model = modelDescription?.trim();
    if (!make && !model) return undefined;
    return { make, model };
};

const parseDescription = (tags: RawExifTags) =>
    tags.xmp?.description?.description ??
    tags.iptc?.["Caption/Abstract"]?.description ??
    tags.exif?.ImageDescription?.description;
