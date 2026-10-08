import { beforeEach, expect, test, vi } from "vitest";
import {
    performSidebarAction,
    sidebarSearchOptionsForString,
} from "../src/services/search/sidebar-search-registry";

const capabilities = vi.hoisted(() => ({
    desktop: true,
    ml: true,
    video: true,
}));
vi.mock("ente-base/app", () => ({
    get isDesktop() {
        return capabilities.desktop;
    },
}));
vi.mock("ente-new/photos/services/ml", () => ({
    get isMLSupported() {
        return capabilities.ml;
    },
}));
vi.mock("ente-gallery/services/video", () => ({
    get isHLSGenerationSupported() {
        return capabilities.video;
    },
}));
vi.mock("i18next", () => ({ t: (key: string) => `label ${key}` }));
vi.mock("ente-utils/promise", () => ({ wait: () => Promise.resolve() }));

beforeEach(() => {
    capabilities.desktop = capabilities.ml = capabilities.video = true;
});

test("retains all 38 registered actions and the two-character minimum", () => {
    const rows = sidebarSearchOptionsForString("label");
    expect(rows).toHaveLength(38);
    expect(
        new Set(
            rows.map(
                (o) =>
                    o.suggestion.type === "sidebarAction" &&
                    o.suggestion.actionID,
            ),
        ).size,
    ).toBe(38);
    expect(
        rows.every(
            (o) =>
                o.suggestion.type === "sidebarAction" &&
                o.suggestion.path.length > 0,
        ),
    ).toBe(true);
    expect(sidebarSearchOptionsForString(" l ")).toEqual([]);
});

test("keeps Desktop, ML and video restrictions", () => {
    capabilities.desktop = capabilities.ml = capabilities.video = false;
    const ids = sidebarSearchOptionsForString("label").map(
        (o) => o.suggestion.type === "sidebarAction" && o.suggestion.actionID,
    );
    expect(ids).toHaveLength(32);
    for (const id of [
        "utility.watchFolders",
        "utility.export",
        "preferences.appLock",
        "preferences.openOnStartup",
        "preferences.mlSearch",
        "preferences.streamableVideos",
    ])
        expect(ids).not.toContain(id);
    expect(ids).toContain("freeUpSpace.deduplicate");
    expect(ids).toContain("freeUpSpace.largeFiles");
    expect(ids).toContain("shortcuts.hidden");
});

const context = () => ({
    onClose: vi.fn(),
    onShowCollectionSummary: vi.fn().mockResolvedValue(undefined),
    showAccount: vi.fn(),
    showReferrals: vi.fn(),
    showPreferences: vi.fn(),
    showHelp: vi.fn(),
    showFreeUpSpace: vi.fn(),
    onShowExport: vi.fn(),
    onShowPlanSelector: vi.fn(),
    onLogout: vi.fn(),
    onShowWatchFolder: vi.fn(),
    pseudoIDs: { uncategorized: -1, archive: -2, hidden: -3, trash: -4 },
    setPendingAccountAction: vi.fn(),
    setPendingPreferencesAction: vi.fn(),
    setPendingHelpAction: vi.fn(),
    setPendingFreeUpSpaceAction: vi.fn(),
});

test("Export retains the owning sidebar across authentication", async () => {
    const ctx = context();
    await performSidebarAction("utility.export", ctx);
    expect(ctx.onShowExport).toHaveBeenCalledOnce();
    expect(ctx.onClose).not.toHaveBeenCalled();
});

test("Hidden uses the existing protected navigation and closes after it completes", async () => {
    const ctx = context();
    await performSidebarAction("shortcuts.hidden", ctx);
    expect(ctx.onShowCollectionSummary).toHaveBeenCalledWith(-3, true);
    expect(ctx.onClose).toHaveBeenCalledOnce();
});

test.each(["freeUpSpace.deduplicate", "freeUpSpace.largeFiles"] as const)(
    "%s retains its dedicated destination",
    async (id) => {
        const ctx = context();
        await performSidebarAction(id, ctx);
        expect(ctx.setPendingFreeUpSpaceAction).toHaveBeenCalledWith(id);
        expect(ctx.showFreeUpSpace).toHaveBeenCalledOnce();
        expect(ctx.onClose).not.toHaveBeenCalled();
    },
);
