import { ensureLocalUser } from "ente-accounts/services/user";
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

let _comlinkWorker: ComlinkWorker<typeof SearchWorker> | undefined;

const worker = () => (_comlinkWorker ??= createComlinkWorker()).remote;

const createComlinkWorker = () =>
    new ComlinkWorker<typeof SearchWorker>(
        "search",
        new Worker(new URL("worker.ts", import.meta.url)),
    );

export const logoutSearch = () => {
    if (_comlinkWorker) {
        _comlinkWorker.terminate();
        _comlinkWorker = undefined;
    }
    _localizedSearchData = undefined;
};

export const searchDataSync = () =>
    worker().then((w) => ensureMasterKeyFromSession().then((k) => w.sync(k)));

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
            currentUserID: ensureLocalUser().id,
            collections: normalCollections,
            files: uniqueFilesByID(normalCollectionFiles),
            collectionFiles: normalCollectionFiles,
        }),
    );
};

export const setSearchPeople = (people: NamedPerson[]) =>
    void worker().then((w) => w.setPeople(people));

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
    const s = searchString.trim().toLowerCase();
    if (s.length == 0) return [];

    // CLIP uses the ML worker, so run it alongside the search worker.
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

    const matches = await clipMatches(s).catch((e: unknown) => {
        log.warn("Ignoring CLIP matches failure", e);
        return undefined;
    });
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

export const filterSearchableFiles = async (suggestion: SearchSuggestion) =>
    worker().then((w) => w.filterSearchableFiles(suggestion));

// Batching avoids per-suggestion worker IPC and is about 10× faster for broad searches.
const filterSearchableFilesMulti = async (suggestions: SearchSuggestion[]) =>
    worker().then((w) => w.filterSearchableFilesMulti(suggestions));

let _localizedSearchData: LocalizedSearchData | undefined;

// Workers cannot use t(), so build localized labels on the main thread.
// Build them at runtime because the locale is user-selected.
// Locale changes reload the page; logout explicitly clears this cache.
const localizedSearchData = () =>
    (_localizedSearchData ??= {
        locale: i18n.language,
        holidays: holidays(),
        labelledFileTypes: labelledFileTypes(),
        noLocationLabel: t("no_location"),
    });

const holidays = (): LabelledSearchDateComponents[] => [
    { components: { month: 12, day: 25 }, label: t("christmas") },
    { components: { month: 12, day: 24 }, label: t("christmas_eve") },
    { components: { month: 1, day: 1 }, label: t("new_year") },
    { components: { month: 12, day: 31 }, label: t("new_year_eve") },
];

const labelledFileTypes = (): LabelledFileType[] => [
    { fileType: FileType.image, label: t("image") },
    { fileType: FileType.video, label: t("video") },
    { fileType: FileType.livePhoto, label: t("live_photo") },
];
