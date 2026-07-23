/**
 * @file types shared between the main thread interface to search (`index.ts`)
 * and the search worker that does the actual searching (`worker.ts`).
 */

import type { Location } from "ente-base/types";
import type { Collection } from "ente-media/collection";
import type { EnteFile } from "ente-media/file";
import { FileType } from "ente-media/file-type";
import type { Person } from "ente-new/photos/services/ml/people";
import type { LocationTag } from "../user-entity";

/**
 * Represents the unique identifiers for various sidebar actions in the application.
 *
 * These IDs are organized into categories:
 * - `shortcuts.*`: Quick access actions like uncategorized items, archive, hidden items, and trash
 * - `utility.*`: General utility actions such as account management, folder watching, deduplication, preferences, help, export, and logout
 * - `account.*`: Account-specific settings including recovery key, two-factor authentication, passkeys, password/email management, and account deletion
 * - `preferences.*`: User preference options like language, theme, app lock, custom domains, map settings, advanced options, ML search, and streamable videos
 * - `help.*`: Help-related actions including help center, blog, feature requests, support, log viewing, and test upload
 *
 * @remarks
 * This type is used to ensure type safety when referencing sidebar actions throughout the application.
 */
export type SidebarActionID =
    | "shortcuts.uncategorized"
    | "shortcuts.archive"
    | "shortcuts.hidden"
    | "shortcuts.trash"
    | "utility.account"
    | "utility.watchFolders"
    | "utility.freeUpSpace"
    | "utility.preferences"
    | "utility.help"
    | "utility.export"
    | "utility.logout"
    | "freeUpSpace.deduplicate"
    | "freeUpSpace.largeFiles"
    | "account.subscription"
    | "account.recoveryKey"
    | "account.twoFactor"
    | "account.twoFactor.reconfigure"
    | "account.passkeys"
    | "account.changePassword"
    | "account.changeEmail"
    | "account.deleteAccount"
    | "account.sessions"
    | "preferences.language"
    | "preferences.theme"
    | "preferences.appLock"
    | "preferences.customDomains"
    | "preferences.map"
    | "preferences.advanced"
    | "preferences.fasterUpload"
    | "preferences.openOnStartup"
    | "preferences.mlSearch"
    | "preferences.streamableVideos"
    | "help.helpCenter"
    | "help.blog"
    | "help.requestFeature"
    | "help.support"
    | "help.viewLogs";

/**
 * A search suggestion.
 *
 * These (wrapped up in {@link SearchOption}s) are shown in the search results
 * dropdown, and can also be used to filter the list of files that are shown.
 */
export type SearchSuggestion = { label: string } & (
    | { type: "collection"; collectionID: number }
    | { type: "fileType"; fileType: FileType }
    | { type: "fileName"; fileIDs: number[] }
    | { type: "fileCaption"; fileIDs: number[] }
    | { type: "cameraMake"; fileIDs: number[] }
    | { type: "cameraModel"; fileIDs: number[] }
    | { type: "date"; dateComponents: SearchDateComponents }
    | { type: "location"; locationTag: LocationTag }
    | { type: "city"; city: City }
    | { type: "clip"; clipScoreForFileID: Map<number, number> }
    | { type: "person"; person: Person }
    | { type: "sidebarAction"; actionID: SidebarActionID; path: string[] }
);

/**
 * An option shown in the the search bar's select dropdown.
 *
 * The {@link SearchOption} wraps a {@link SearchSuggestion} with some metadata
 * used when showing a corresponding entry in the dropdown.
 *
 * If the user selects the option, then we will re-run the search using the
 * {@link suggestion} to filter the list of files shown to the user.
 */
export interface SearchOption {
    suggestion: SearchSuggestion;
    /**
     * The count of files that matched the search option when it was initially
     * computed.
     */
    fileCount: number;
    previewFiles: EnteFile[];
}

/**
 * The collections and files over which we should search.
 */
export interface SearchCollectionsAndFiles {
    collections: Collection[];
    /**
     * Unique files (by ID).
     *
     * @see {@link uniqueFilesByID}.
     */
    files: EnteFile[];
    /**
     * One entry per collection/file pair.
     *
     * Whenever the same file (ID) is in multiple collections, the
     * {@link collectionFiles} will have multiple entries with the same file ID,
     * one per collection in which that file (ID) occurs.
     */
    collectionFiles: EnteFile[];
}

export interface LabelledSearchDateComponents {
    components: SearchDateComponents;
    label: string;
}

export interface LabelledFileType {
    fileType: FileType;
    label: string;
}

/**
 * Various bits of static but locale specific data that the search worker needs
 * during searching.
 */
export interface LocalizedSearchData {
    locale: string;
    holidays: LabelledSearchDateComponents[];
    labelledFileTypes: LabelledFileType[];
}

/**
 * A parsed version of a potential natural language date time string.
 *
 * All attributes which were parsed will be set. The type doesn't enforce this,
 * but it is guaranteed that at least one attribute will be present.
 */
export interface SearchDateComponents {
    /**
     * The year, if the search string specified one. e.g. `2024`.
     */
    year?: number;
    /**
     * The month (1 to 12, with December being 12), if the search string
     * specified one.
     */
    month?: number;
    /**
     * The day of the month (1 to 31), if the search string specified one.
     */
    day?: number;
    /**
     * The day of the week (0 to 6, with Sunday being 0), if the search string
     * specified one.
     */
    weekday?: number;
    /**
     * The hour of the day (0 to 23, with 0 as midnight), if the search string
     * specified one.
     */
    hour?: number;
}

/**
 * A city as identified by a static dataset.
 *
 * Each city is represented by its latitude and longitude. The dataset does not
 * have information about the city's estimated radius.
 */
export type City = Location & {
    /** Name of the city. */
    name: string;
};
