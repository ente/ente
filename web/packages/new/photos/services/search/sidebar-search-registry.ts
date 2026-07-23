import { isDesktop } from "ente-base/app";
import { isHLSGenerationSupported } from "ente-gallery/services/video";
import { wait } from "ente-utils/promise";
import { t } from "i18next";
import { isMLSupported } from "../ml";
import type { SearchOption, SidebarActionID } from "./types";

export interface SidebarAction {
    id: SidebarActionID;
    label: string;
    path: string[];
    keywords?: string[];
    available?: () => boolean;
}

export interface SidebarActionContext {
    // top-level sidebar controls
    onClose: () => void;
    onShowCollectionSummary: (
        collectionSummaryID: number,
        isHidden?: boolean,
    ) => Promise<void>;
    showAccount: () => void;
    showPreferences: () => void;
    showHelp: () => void;
    showFreeUpSpace: () => void;
    onShowExport: () => void;
    onShowPlanSelector: () => void;
    onLogout: () => void;
    onShowWatchFolder: () => void;
    pseudoIDs: {
        uncategorized: number;
        archive: number;
        hidden: number;
        trash: number;
    };

    // nested drawer hooks
    setPendingAccountAction: (a: SidebarActionID | undefined) => void;
    setPendingPreferencesAction: (a: SidebarActionID | undefined) => void;
    setPendingHelpAction: (a: SidebarActionID | undefined) => void;
    setPendingFreeUpSpaceAction: (a: SidebarActionID | undefined) => void;
}

// Construct sidebar actions at call time so we always use initialized i18n
// strings instead of whatever was available when this module was first loaded.
const sidebarActions = (): SidebarAction[] => {
    const shortcutsCategory = t("shortcuts", { defaultValue: "Shortcuts" });
    const preferencesCategory = t("preferences");
    const accountCategory = t("account");
    const helpCategory = t("help");

    return [
        {
            id: "account.subscription",
            label: t("manage_plan"),
            path: [accountCategory, t("manage_plan")],
            keywords: ["subscription", "plan", "upgrade", "billing", "pricing"],
        },
        {
            id: "shortcuts.uncategorized",
            label: t("section_uncategorized"),
            path: [shortcutsCategory, t("section_uncategorized")],
            keywords: ["uncategorized", "ungrouped"],
        },
        {
            id: "shortcuts.archive",
            label: t("section_archive"),
            path: [shortcutsCategory, t("section_archive")],
            keywords: ["archive", "archived"],
        },
        {
            id: "shortcuts.hidden",
            label: t("section_hidden"),
            path: [shortcutsCategory, t("section_hidden")],
            keywords: ["hidden", "private"],
        },
        {
            id: "shortcuts.trash",
            label: t("section_trash"),
            path: [shortcutsCategory, t("section_trash")],
            keywords: ["trash", "bin", "deleted"],
        },
        {
            id: "utility.account",
            label: t("account"),
            path: [preferencesCategory, t("account")],
            keywords: ["profile", "user"],
        },
        {
            id: "utility.watchFolders",
            label: t("watch_folders"),
            path: [preferencesCategory, t("watch_folders")],
            keywords: ["watch", "folder", "desktop"],
            available: () => isDesktop,
        },
        {
            id: "utility.freeUpSpace",
            label: t("free_up_space"),
            path: [preferencesCategory, t("free_up_space")],
            keywords: ["free", "space", "storage", "clean"],
        },
        {
            id: "freeUpSpace.deduplicate",
            label: t("deduplicate_files"),
            path: [
                preferencesCategory,
                t("free_up_space"),
                t("deduplicate_files"),
            ],
            keywords: ["duplicate", "dedupe"],
        },
        {
            id: "freeUpSpace.largeFiles",
            label: t("large_files_title"),
            path: [
                preferencesCategory,
                t("free_up_space"),
                t("large_files_title"),
            ],
            keywords: ["large", "big", "files", "size", "space"],
        },
        {
            id: "utility.preferences",
            label: t("preferences"),
            path: [preferencesCategory],
            keywords: ["settings"],
        },
        {
            id: "utility.help",
            label: t("help"),
            path: [helpCategory],
            keywords: ["support", "docs"],
        },
        {
            id: "utility.export",
            label: t("export_data"),
            path: [preferencesCategory, t("export_data")],
            keywords: ["export", "download"],
            available: () => isDesktop,
        },
        {
            id: "account.recoveryKey",
            label: t("recovery_key"),
            path: [accountCategory, t("recovery_key")],
            keywords: ["recovery", "key", "backup"],
        },
        {
            id: "account.twoFactor",
            label: t("two_factor"),
            path: [accountCategory, t("two_factor")],
            keywords: ["2fa", "otp", "mfa", "two", "factor", "two factor"],
        },
        {
            id: "account.twoFactor.reconfigure",
            label: t("reconfigure"),
            path: [accountCategory, t("two_factor"), t("reconfigure")],
            keywords: ["reconfigure", "update", "2fa", "two factor"],
        },
        {
            id: "account.passkeys",
            label: t("passkeys"),
            path: [accountCategory, t("passkeys")],
            keywords: ["webauthn", "security key"],
        },
        {
            id: "account.changePassword",
            label: t("change_password"),
            path: [accountCategory, t("change_password")],
            keywords: ["password"],
        },
        {
            id: "account.changeEmail",
            label: t("change_email"),
            path: [accountCategory, t("change_email")],
            keywords: ["email"],
        },
        {
            id: "account.deleteAccount",
            label: t("delete_account"),
            path: [accountCategory, t("delete_account")],
            keywords: ["delete", "remove"],
        },
        {
            id: "account.sessions",
            label: t("active_sessions"),
            path: [accountCategory, t("active_sessions")],
            keywords: ["sessions", "devices", "logout"],
        },
        {
            id: "preferences.language",
            label: t("language"),
            path: [preferencesCategory, t("language")],
            keywords: ["locale"],
        },
        {
            id: "preferences.theme",
            label: t("theme"),
            path: [preferencesCategory, t("theme")],
            keywords: ["appearance", "dark mode", "light mode"],
        },
        {
            id: "preferences.appLock",
            label: t("app_lock"),
            path: [preferencesCategory, t("app_lock")],
            keywords: ["lock", "pin", "password", "biometric", "privacy"],
            available: () => isDesktop,
        },
        {
            id: "preferences.customDomains",
            label: t("custom_domains"),
            path: [preferencesCategory, t("custom_domains")],
            keywords: ["domain", "link"],
        },
        {
            id: "preferences.map",
            label: t("map"),
            path: [preferencesCategory, t("map")],
            keywords: ["maps", "location"],
        },
        {
            id: "preferences.advanced",
            label: t("advanced"),
            path: [preferencesCategory, t("advanced")],
            keywords: ["advanced", "proxy", "upload"],
        },
        {
            id: "preferences.fasterUpload",
            label: t("faster_upload"),
            path: [preferencesCategory, t("advanced"), t("faster_upload")],
            keywords: ["faster", "upload", "proxy"],
        },
        {
            id: "preferences.openOnStartup",
            label: t("open_ente_on_startup"),
            path: [
                preferencesCategory,
                t("advanced"),
                t("open_ente_on_startup"),
            ],
            keywords: ["open", "startup", "launch", "auto launch"],
            available: () => isDesktop,
        },
        {
            id: "preferences.mlSearch",
            label: t("ml_search"),
            path: [preferencesCategory, t("ml_search")],
            keywords: ["ml", "search", "magic"],
            available: () => isMLSupported,
        },
        {
            id: "preferences.streamableVideos",
            label: t("streamable_videos"),
            path: [preferencesCategory, t("streamable_videos")],
            keywords: ["hls", "video", "stream"],
            available: () => isHLSGenerationSupported,
        },
        {
            id: "help.helpCenter",
            label: t("ente_help"),
            path: [helpCategory, t("ente_help")],
            keywords: ["help", "docs"],
        },
        {
            id: "help.blog",
            label: t("blog"),
            path: [helpCategory, t("blog")],
            keywords: ["news"],
        },
        {
            id: "help.requestFeature",
            label: t("request_feature"),
            path: [helpCategory, t("request_feature")],
            keywords: ["feature", "feedback"],
        },
        {
            id: "help.support",
            label: t("support"),
            path: [helpCategory, t("support")],
            keywords: ["contact", "support"],
        },
        {
            id: "help.viewLogs",
            label: t("view_logs"),
            path: [helpCategory, t("view_logs")],
            keywords: ["logs", "debug"],
        },
        {
            id: "utility.logout",
            label: t("logout"),
            path: [preferencesCategory, t("logout")],
            keywords: ["sign out", "signout"],
        },
    ];
};

export const sidebarSearchOptionsForString = (
    searchString: string,
): SearchOption[] => {
    const normalized = searchString.trim().toLowerCase();
    if (normalized.length < 2) return []; // avoid noisy single-letter matches

    return sidebarActions()
        .filter(({ available }) => !available || available())
        .filter(({ label, path, keywords }) =>
            matchesSearch(normalized, label, path, keywords),
        )
        .map(({ id, label, path }) => ({
            suggestion: { type: "sidebarAction", actionID: id, path, label },
            fileCount: 0,
            previewFiles: [],
        }));
};

export const performSidebarAction = async (
    actionID: SidebarActionID,
    ctx: SidebarActionContext,
): Promise<void> => {
    switch (actionID) {
        case "shortcuts.uncategorized":
            return ctx
                .onShowCollectionSummary(ctx.pseudoIDs.uncategorized, false)
                .then(() => ctx.onClose());
        case "shortcuts.archive":
            return ctx
                .onShowCollectionSummary(ctx.pseudoIDs.archive, false)
                .then(() => ctx.onClose());
        case "shortcuts.hidden":
            return (
                ctx
                    .onShowCollectionSummary(ctx.pseudoIDs.hidden, true)
                    // See: [Note: Workarounds for unactionable ARIA warnings]
                    .then(() => wait(10))
                    .then(() => ctx.onClose())
            );
        case "shortcuts.trash":
            return ctx
                .onShowCollectionSummary(ctx.pseudoIDs.trash, false)
                .then(() => ctx.onClose());

        case "utility.account":
            ctx.showAccount();
            return Promise.resolve();

        case "utility.watchFolders":
            ctx.onShowWatchFolder();
            return Promise.resolve();

        case "utility.freeUpSpace":
            ctx.showFreeUpSpace();
            return Promise.resolve();

        case "freeUpSpace.deduplicate":
        case "freeUpSpace.largeFiles":
            ctx.setPendingFreeUpSpaceAction(actionID);
            ctx.showFreeUpSpace();
            return Promise.resolve();

        case "utility.preferences":
            ctx.showPreferences();
            return Promise.resolve();

        case "utility.help":
            ctx.showHelp();
            return Promise.resolve();

        case "utility.export":
            ctx.onShowExport();
            ctx.onClose();
            return Promise.resolve();

        case "utility.logout":
            ctx.onLogout();
            return Promise.resolve();

        case "account.subscription":
        case "account.recoveryKey":
        case "account.twoFactor":
        case "account.twoFactor.reconfigure":
        case "account.passkeys":
        case "account.changePassword":
        case "account.changeEmail":
        case "account.deleteAccount":
        case "account.sessions":
            ctx.setPendingAccountAction(actionID);
            ctx.showAccount();
            return Promise.resolve();

        case "preferences.language":
        case "preferences.theme":
        case "preferences.appLock":
        case "preferences.customDomains":
        case "preferences.map":
        case "preferences.advanced":
        case "preferences.fasterUpload":
        case "preferences.openOnStartup":
        case "preferences.mlSearch":
        case "preferences.streamableVideos":
            ctx.setPendingPreferencesAction(actionID);
            ctx.showPreferences();
            return Promise.resolve();

        case "help.helpCenter":
        case "help.blog":
        case "help.requestFeature":
        case "help.support":
        case "help.viewLogs":
            ctx.setPendingHelpAction(actionID);
            ctx.showHelp();
            return Promise.resolve();
    }
};

const matchesSearch = (
    normalized: string,
    label: string,
    path: string[],
    keywords: string[] = [],
) => {
    const searchVariants = getSearchVariants(normalized);
    const haystack = [label, ...path, ...keywords]
        .filter(Boolean)
        .map((s) => s.toLowerCase());

    const re = new RegExp(
        "(^|[\\s.,!?\"'-_])(" +
            searchVariants.map((s) => escapeRegex(s)).join("|") +
            ")",
    );
    return haystack.some((h) => re.test(h));
};

const getSearchVariants = (search: string) => {
    const variants = new Set<string>([search]);
    if (search.endsWith("ies")) variants.add(search.slice(0, -3) + "y");
    if (search.endsWith("es")) variants.add(search.slice(0, -2));
    if (search.endsWith("s")) variants.add(search.slice(0, -1));

    return [...variants].filter((v) => v.length > 1);
};

const escapeRegex = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
