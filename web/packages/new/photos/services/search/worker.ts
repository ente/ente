import type { Component } from "chrono-node";
import * as chrono from "chrono-node";
import { expose } from "comlink";
import { HTTPError } from "ente-base/http";
import { logUnhandledErrorsAndRejectionsInWorker } from "ente-base/log-web";
import type { Location } from "ente-base/types";
import type { Collection } from "ente-media/collection";
import type { EnteFile } from "ente-media/file";
import {
    fileCameraMake,
    fileCameraModel,
    fileCreationPhotoDate,
    fileFileName,
    fileLocation,
} from "ente-media/file-metadata";
import { nullToUndefined } from "ente-utils/transform";
import { z } from "zod";
import type { NamedPerson } from "../ml/people";
import {
    pullUserEntities,
    savedLocationTags,
    type LocationTag,
} from "../user-entity";
import type {
    City,
    LabelledFileType,
    LabelledSearchDateComponents,
    LocalizedSearchData,
    SearchCollectionsAndFiles,
    SearchDateComponents,
    SearchSuggestion,
} from "./types";

export class SearchWorker {
    private locationTags: LocationTag[] = [];
    private cities: City[] = [];
    private collectionsAndFiles: SearchCollectionsAndFiles = {
        currentUserID: 0,
        collections: [],
        files: [],
        collectionFiles: [],
    };
    private people: NamedPerson[] = [];

    async sync(masterKey: string) {
        if (this.cities.length == 0) {
            void fetchCities().then((cs) => (this.cities = cs));
        }

        return pullUserEntities("location", masterKey)
            .then(() => savedLocationTags())
            .then((ts) => (this.locationTags = ts));
    }

    setCollectionsAndFiles(cf: SearchCollectionsAndFiles) {
        this.collectionsAndFiles = cf;
    }

    setPeople(people: NamedPerson[]) {
        this.people = people;
    }

    suggestionsForString(
        s: string,
        searchString: string,
        localizedSearchData: LocalizedSearchData,
    ) {
        // \b does not handle Unicode word boundaries.
        return suggestionsForString(
            s,
            new RegExp("(^|[\\s.,!?\"'-_])" + s, "i"),
            searchString,
            this.collectionsAndFiles,
            this.people,
            localizedSearchData,
            this.locationTags,
            this.cities,
        );
    }

    filterSearchableFiles(suggestion: SearchSuggestion) {
        return filterSearchableFiles(this.collectionsAndFiles, suggestion);
    }

    filterSearchableFilesMulti(suggestions: SearchSuggestion[]) {
        const cf = this.collectionsAndFiles;
        return suggestions
            .map((sg) => [filterSearchableFiles(cf, sg), sg] as const)
            .filter(([files]) => files.length);
    }
}

expose(SearchWorker);

logUnhandledErrorsAndRejectionsInWorker();

// The caller inserts CLIP suggestions between these two groups.
const suggestionsForString = (
    s: string,
    re: RegExp,
    searchString: string,
    { collections, files }: SearchCollectionsAndFiles,
    people: NamedPerson[],
    {
        locale,
        holidays,
        labelledFileTypes,
        noLocationLabel,
    }: LocalizedSearchData,
    locationTags: LocationTag[],
    cities: City[],
): [SearchSuggestion[], SearchSuggestion[]] => [
    [peopleSuggestions(re, people)].flat(),
    [
        fileTypeSuggestions(re, labelledFileTypes),
        dateSuggestions(s, re, locale, holidays),
        noLocationSuggestion(s, noLocationLabel),
        locationSuggestions(re, locationTags, cities),
        collectionSuggestions(re, collections),
        fileNameSuggestion(s, re, searchString, files),
        fileCaptionSuggestion(re, searchString, files),
        cameraMakeSuggestions(re, files),
        cameraModelSuggestions(re, files),
    ].flat(),
];

const collectionSuggestions = (
    re: RegExp,
    collections: Collection[],
): SearchSuggestion[] =>
    collections
        .filter((c) => re.test(c.name))
        .map(({ id, name }) => ({
            type: "collection",
            collectionID: id,
            label: name,
        }));

const fileTypeSuggestions = (
    re: RegExp,
    labelledFileTypes: LabelledFileType[],
): SearchSuggestion[] =>
    labelledFileTypes
        .filter(({ label }) => re.test(label))
        .map(({ fileType, label }) => ({ type: "fileType", fileType, label }));

const fileNameSuggestion = (
    s: string,
    re: RegExp,
    searchString: string,
    files: EnteFile[],
): SearchSuggestion[] => {
    const sn = Number(s) || undefined;

    const fileIDs = files
        .filter((f) => f.id === sn || re.test(fileFileName(f)))
        .map((f) => f.id);

    return fileIDs.length
        ? [{ type: "fileName", fileIDs, label: searchString }]
        : [];
};

const fileCaptionSuggestion = (
    re: RegExp,
    searchString: string,
    files: EnteFile[],
): SearchSuggestion[] => {
    const fileIDs = files
        .filter((file) => {
            // eslint-disable-next-line @typescript-eslint/no-unnecessary-condition
            const caption = file.pubMagicMetadata?.data?.caption;
            return caption && re.test(caption);
        })
        .map((f) => f.id);

    return fileIDs.length
        ? [{ type: "fileCaption", fileIDs, label: searchString }]
        : [];
};

const cameraMakeSuggestions = (
    re: RegExp,
    files: EnteFile[],
): SearchSuggestion[] => {
    const matches = new Map<string, { label: string; fileIDs: number[] }>();
    for (const file of files) {
        const label = fileCameraMake(file);
        if (!label || !re.test(label)) continue;
        const key = label.toLowerCase();
        const existing = matches.get(key);
        if (existing) {
            existing.fileIDs.push(file.id);
        } else {
            matches.set(key, { label, fileIDs: [file.id] });
        }
    }

    return Array.from(matches.values()).map(({ label, fileIDs }) => ({
        type: "cameraMake" as const,
        label,
        fileIDs,
    }));
};

const cameraModelSuggestions = (
    re: RegExp,
    files: EnteFile[],
): SearchSuggestion[] => {
    const matches = new Map<string, { label: string; fileIDs: number[] }>();
    for (const file of files) {
        const label = fileCameraModel(file);
        if (!label || !re.test(label)) continue;
        const key = label.toLowerCase();
        const existing = matches.get(key);
        if (existing) {
            existing.fileIDs.push(file.id);
        } else {
            matches.set(key, { label, fileIDs: [file.id] });
        }
    }

    return Array.from(matches.values()).map(({ label, fileIDs }) => ({
        type: "cameraModel" as const,
        label,
        fileIDs,
    }));
};

const peopleSuggestions = (
    re: RegExp,
    people: NamedPerson[],
): SearchSuggestion[] =>
    people
        .filter(({ name }) => re.test(name))
        .map((person) => ({ type: "person", person, label: person.name }));

const dateSuggestions = (
    s: string,
    re: RegExp,
    locale: string,
    holidays: LabelledSearchDateComponents[],
): SearchSuggestion[] =>
    parseDateComponents(s, re, locale, holidays).map(
        ({ components, label }) => ({
            type: "date",
            dateComponents: components,
            label,
        }),
    );

const parseDateComponents = (
    s: string,
    re: RegExp,
    locale: string,
    holidays: LabelledSearchDateComponents[],
): LabelledSearchDateComponents[] =>
    [
        parseChrono(s, locale),
        parseYearComponents(s),
        holidays.filter((h) => re.test(h.label)),
    ].flat();

const parseChrono = (
    s: string,
    locale: string,
): LabelledSearchDateComponents[] => {
    const isUSLocale =
        locale.toLowerCase().includes("en-us") || locale.toLowerCase() === "en";

    let chronoInstance;
    if (isUSLocale) {
        chronoInstance = chrono;
    } else {
        chronoInstance = new chrono.Chrono(chrono.en.GB);

        chronoInstance.parsers.push({
            pattern: () => /\b(\d{1,2})\.(\d{1,2})\.(\d{2,4})\b/,
            extract: (_context, match) => {
                if (!match[1] || !match[2] || !match[3]) return null;

                const day = parseInt(match[1]);
                const month = parseInt(match[2]);
                let year = parseInt(match[3]);

                if (year < 100) {
                    year = year > 50 ? 1900 + year : 2000 + year;
                }

                if (day < 1 || day > 31 || month < 1 || month > 12) {
                    return null;
                }

                return { day, month, year };
            },
        });
    }

    return chronoInstance
        .parse(s)
        .map((result) => {
            const p = result.start;
            const component = (s: Component) =>
                p.isCertain(s) ? nullToUndefined(p.get(s)) : undefined;

            const year = component("year");
            const month = component("month");
            const day = component("day");
            const weekday = component("weekday");
            const hour = component("hour");

            if (!year && !month && !day && !weekday && !hour) return undefined;
            const components = { year, month, day, weekday, hour };

            const format: Intl.DateTimeFormatOptions = {};
            if (year) format.year = "numeric";
            if (month) format.month = "long";
            if (day) format.day = "numeric";
            if (weekday) format.weekday = "long";
            if (hour) {
                format.hour = "numeric";
                format.dayPeriod = "short";
            }

            const formatter = new Intl.DateTimeFormat(locale, format);
            const label = formatter.format(p.date());
            return { components, label };
        })
        .filter((x) => x !== undefined);
};

// chrono does not parse bare years such as "2024".
const parseYearComponents = (s: string): LabelledSearchDateComponents[] => {
    if (s.length == 4) {
        const year = parseInt(s);
        if (year && year <= 9999) {
            const components = { year };
            return [{ components, label: s }];
        }
    }
    return [];
};

const RemoteWorldCities = z.object({
    data: z.array(
        z.object({ city: z.string(), lat: z.number(), lng: z.number() }),
    ),
});

const fetchCities = async () => {
    const res = await fetch("https://assets.ente.com/world_cities.json");
    if (!res.ok) throw new HTTPError(res);
    return RemoteWorldCities.parse(await res.json()).data.map(
        ({ city, lat, lng }) => ({ name: city, latitude: lat, longitude: lng }),
    );
};

const locationSuggestions = (
    re: RegExp,
    locationTags: LocationTag[],
    cities: City[],
): SearchSuggestion[] => {
    const matchingLocationTags = locationTags.filter((t) => re.test(t.name));

    const matchingLocationTagLNames = new Set(
        matchingLocationTags.map((t) => t.name.toLowerCase()),
    );

    const matchingCities = cities
        .filter((c) => re.test(c.name))
        .filter((c) => !matchingLocationTagLNames.has(c.name.toLowerCase()));

    return [
        matchingLocationTags.map((locationTag): SearchSuggestion => ({
            type: "location",
            locationTag,
            label: locationTag.name,
        })),
        matchingCities.map((city): SearchSuggestion => ({
            type: "city",
            city,
            label: city.name,
        })),
    ].flat();
};

const noLocationSuggestion = (s: string, label: string): SearchSuggestion[] =>
    s.length > 2 && label.toLowerCase().startsWith(s)
        ? [{ type: "noLocation", label }]
        : [];

const filterSearchableFiles = (
    { currentUserID, files, collectionFiles }: SearchCollectionsAndFiles,
    suggestion: SearchSuggestion,
) => {
    if (suggestion.type == "sidebarAction") return [];

    return sortMatchesIfNeeded(
        (suggestion.type == "collection" ? collectionFiles : files).filter(
            (f) => isMatchingFile(f, suggestion, currentUserID),
        ),
        suggestion,
    );
};

const isMatchingFile = (
    file: EnteFile,
    suggestion: SearchSuggestion,
    currentUserID: number,
) => {
    switch (suggestion.type) {
        case "collection":
            return suggestion.collectionID === file.collectionID;

        case "fileType":
            return suggestion.fileType == file.metadata.fileType;

        case "fileName":
            return suggestion.fileIDs.includes(file.id);

        case "fileCaption":
        case "cameraMake":
        case "cameraModel":
            return suggestion.fileIDs.includes(file.id);

        case "date":
            return isDateComponentsMatch(
                suggestion.dateComponents,
                fileCreationPhotoDate(file),
            );

        case "noLocation":
            return file.ownerID == currentUserID && !fileLocation(file);

        case "location": {
            const location = fileLocation(file);
            if (!location) return false;

            return isInsideLocationTag(location, suggestion.locationTag);
        }

        case "city": {
            const location = fileLocation(file);
            if (!location) return false;

            return isInsideCity(location, suggestion.city);
        }

        case "clip":
            return suggestion.clipScoreForFileID.has(file.id);

        case "person":
            return suggestion.person.fileIDs.includes(file.id);

        case "sidebarAction":
            return false;
    }
};

const isDateComponentsMatch = (
    { year, month, day, weekday, hour }: SearchDateComponents,
    date: Date,
) => {
    let match = true;

    if (year) match = date.getFullYear() == year;
    if (match && month) match = date.getMonth() + 1 == month;
    if (match && day) match = date.getDate() == day;
    if (match && weekday) match = date.getDay() == weekday;
    if (match && hour) match = date.getHours() == hour;

    return match;
};

const defaultCityRadius = 10;
const kmsPerDegree = 111.16;

const isInsideLocationTag = (location: Location, locationTag: LocationTag) =>
    isWithinRadius(location, locationTag.centerPoint, locationTag.radius);

const isInsideCity = (location: Location, city: City) =>
    isWithinRadius(location, city, defaultCityRadius);

const isWithinRadius = (
    location: Location,
    center: Location,
    radius: number,
) => {
    const a = (radius * radiusScaleFactor(center.latitude)) / kmsPerDegree;
    const b = radius / kmsPerDegree;
    const x = center.latitude - location.latitude;
    const y = center.longitude - location.longitude;
    return (x * x) / (a * a) + (y * y) / (b * b) <= 1;
};

const radiusScaleFactor = (lat: number) => 1 / Math.cos(lat * (Math.PI / 180));

const sortMatchesIfNeeded = (
    files: EnteFile[],
    suggestion: SearchSuggestion,
) => {
    if (suggestion.type != "clip") return files;
    const score = ({ id }: EnteFile) => suggestion.clipScoreForFileID.get(id)!;
    return files.sort((a, b) => score(b) - score(a));
};
