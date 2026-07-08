import log from "ente-base/log";
import { ensureMasterKeyFromSession } from "ente-base/session";
import { ComlinkWorker } from "ente-base/worker/comlink-worker";
import { uniqueFilesByID } from "ente-gallery/utils/file";
import type { Collection } from "ente-media/collection";
import type { EnteFile } from "ente-media/file";
import { FileType } from "ente-media/file-type";
import i18n, { t } from "i18next";
import { clipMatches, isMLEnabled, isMLSupported } from "../ml";
import type { NamedPerson } from "../ml/people";
import type {
    LabelledFileType,
    LabelledSearchDateComponents,
    LocalizedSearchData,
    SearchSuggestion,
} from "./types";
import type { SearchWorker } from "./worker";

/**
 * Cached instance of the {@link ComlinkWorker} that wraps our web worker.
 */
let _comlinkWorker: ComlinkWorker<typeof SearchWorker> | undefined;

/**
 * Lazily created, cached, instance of {@link SearchWorker}.
 */
const worker = () => (_comlinkWorker ??= createComlinkWorker()).remote;

/**
 * Create a new instance of a comlink worker that wraps a {@link SearchWorker}
 * web worker.
 */
const createComlinkWorker = () =>
    new ComlinkWorker<typeof SearchWorker>(
        "search",
        new Worker(new URL("worker.ts", import.meta.url)),
    );

/**
 * Perform any logout specific cleanup for the search subsystem.
 */
export const logoutSearch = () => {
    if (_comlinkWorker) {
        _comlinkWorker.terminate();
        _comlinkWorker = undefined;
    }
    _localizedSearchData = undefined;
};

/**
 * Fetch any data that would be needed if the user were to search.
 */
export const searchDataSync = () =>
    worker().then((w) => ensureMasterKeyFromSession().then((k) => w.sync(k)));

/**
 * Update the collections and files over which we should search.
 */
export const updateSearchCollectionsAndFiles = (
    collections: Collection[],
    collectionFiles: EnteFile[],
    hiddenCollectionIDs: Set<number>,
    hiddenFileIDs: Set<number>,
) => {
    const normalCollections = collections.filter(
        (c) => !hiddenCollectionIDs.has(c.id),
    );
    const normalCollectionFiles = collectionFiles.filter(
        (f) => !hiddenFileIDs.has(f.id),
    );
    void worker().then((w) =>
        w.setCollectionsAndFiles({
            collections: normalCollections,
            files: uniqueFilesByID(normalCollectionFiles),
            collectionFiles: normalCollectionFiles,
        }),
    );
};

/**
 * Set the (named) people that we should search across.
 */
export const setSearchPeople = (people: NamedPerson[]) =>
    void worker().then((w) => w.setPeople(people));

/**
 * Convert a search string into (annotated) suggestions that can be shown in the
 * search results dropdown.
 *
 * @param searchString The string we want to search for.
 */
export const searchOptionsForString = async (searchString: string) => {
    const t = Date.now();
    const suggestions = await suggestionsForString(searchString);
    const options = await suggestionsToOptions(suggestions);
    log.debug(() => [
        "search",
        { searchString, options, duration: `${Date.now() - t} ms` },
    ]);
    return options;
};

const suggestionsForString = async (searchString: string) => {
    // Normalize it by trimming whitespace and converting to lowercase.
    const s = searchString.trim().toLowerCase();
    if (s.length == 0) return [];

    // The CLIP matching code already runs in the ML worker, so let that run
    // separately, in parallel with the rest of the search query construction in
    // the search worker, then combine the two.
    const [clip, [restPre, restPost]] = await Promise.all([
        clipSuggestion(s, searchString).then((s) => s ?? []),
        worker().then((w) =>
            w.suggestionsForString(s, searchString, localizedSearchData()),
        ),
    ]);
    return [restPre, clip, restPost].flat();
};

const clipSuggestion = async (
    s: string,
    searchString: string,
): Promise<SearchSuggestion | undefined> => {
    if (!isMLSupported) return undefined;
    if (!isMLEnabled()) return undefined;

    const matches = await clipMatches(s);
    if (!matches) return undefined;
    return { type: "clip", clipScoreForFileID: matches, label: searchString };
};

const suggestionsToOptions = (suggestions: SearchSuggestion[]) =>
    filterSearchableFilesMulti(suggestions).then((res) =>
        res.map(([files, suggestion]) => ({
            suggestion,
            fileCount: files.length,
            previewFiles: files.slice(0, 3),
        })),
    );

/**
 * Return the list of {@link EnteFile}s (from amongst the previously set
 * {@link SearchCollectionsAndFiles}) that match the given search {@link suggestion}.
 */
export const filterSearchableFiles = async (suggestion: SearchSuggestion) =>
    worker().then((w) => w.filterSearchableFiles(suggestion));

/**
 * A batched variant of {@link filterSearchableFiles}.
 *
 * This has drastically (10x) better performance when filtering files for a
 * large number of suggestions (e.g. single letter searches that lead to a large
 * number of city prefix matches), likely because of reduced worker IPC.
 */
const filterSearchableFilesMulti = async (suggestions: SearchSuggestion[]) =>
    worker().then((w) => w.filterSearchableFilesMulti(suggestions));

/**
 * Cached value of {@link localizedSearchData}.
 */
let _localizedSearchData: LocalizedSearchData | undefined;

/*
 * For searching, the web worker needs a bunch of otherwise static data that has
 * names and labels formed by localized strings.
 *
 * Since it would be tricky to get the t() function to work in a web worker, we
 * instead pass this from the main thread (lazily initialized and cached).
 *
 * Note that these need to be evaluated at runtime, and cannot be static
 * constants since t() depends on the user's locale.
 *
 * We currently clear the cached data on logout, but this is not necessary. The
 * only point we necessarily need to clear this data is if the user changes their
 * preferred locale, but currently we reload the page in such cases so any in
 * memory state would be reset that way.
 */
const localizedSearchData = () =>
    (_localizedSearchData ??= {
        locale: i18n.language,
        holidays: holidays(),
        labelledFileTypes: labelledFileTypes(),
    });

/**
 * A list of holidays - their yearly dates and localized names.
 */
const holidays = (): LabelledSearchDateComponents[] => [
    { components: { month: 12, day: 25 }, label: t("christmas") },
    { components: { month: 12, day: 24 }, label: t("christmas_eve") },
    { components: { month: 1, day: 1 }, label: t("new_year") },
    { components: { month: 12, day: 31 }, label: t("new_year_eve") },
];

/**
 * A list of file types with their localized names.
 */
const labelledFileTypes = (): LabelledFileType[] => [
    { fileType: FileType.image, label: t("image") },
    { fileType: FileType.video, label: t("video") },
    { fileType: FileType.livePhoto, label: t("live_photo") },
];
