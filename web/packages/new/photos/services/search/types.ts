import type { Location } from "ente-base/types";
import type { Collection } from "ente-media/collection";
import type { EnteFile } from "ente-media/file";
import { FileType } from "ente-media/file-type";
import type { Person } from "ente-new/photos/services/ml/people";
import type { LocationTag } from "../user-entity";

export type SidebarActionID =
    | "subscription"
    | "shortcuts.uncategorized"
    | "shortcuts.archive"
    | "shortcuts.hidden"
    | "shortcuts.trash"
    | "utility.account"
    | "utility.referrals"
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

export type SearchSuggestion = { label: string } & (
    | { type: "collection"; collectionID: number }
    | { type: "fileType"; fileType: FileType }
    | { type: "fileName"; fileIDs: number[] }
    | { type: "fileCaption"; fileIDs: number[] }
    | { type: "cameraMake"; fileIDs: number[] }
    | { type: "cameraModel"; fileIDs: number[] }
    | { type: "date"; dateComponents: SearchDateComponents }
    | { type: "noLocation" }
    | { type: "location"; locationTag: LocationTag }
    | { type: "city"; city: City }
    | { type: "clip"; clipScoreForFileID: Map<number, number> }
    | { type: "person"; person: Person }
    | { type: "sidebarAction"; actionID: SidebarActionID; path: string[] }
);

export interface SearchOption {
    suggestion: SearchSuggestion;
    fileCount: number;
    previewFiles: EnteFile[];
}

export interface SearchCollectionsAndFiles {
    currentUserID: number;
    collections: Collection[];
    // Unique by file ID.
    files: EnteFile[];
    // One entry per collection membership.
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

export interface LocalizedSearchData {
    locale: string;
    holidays: LabelledSearchDateComponents[];
    labelledFileTypes: LabelledFileType[];
    noLocationLabel: string;
}

// At least one component is always present.
// The type cannot enforce this.
export interface SearchDateComponents {
    year?: number;
    // 1-12.
    month?: number;
    day?: number;
    // 0-6, starting with Sunday.
    weekday?: number;
    // 0-23.
    hour?: number;
}

export type City = Location & { name: string };
