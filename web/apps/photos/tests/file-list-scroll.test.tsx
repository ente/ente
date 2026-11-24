import type { EnteFile } from "ente-media/file";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";

vi.hoisted(() => {
    if (typeof globalThis.self === "undefined") {
        (globalThis as any).self = { addEventListener: () => {} };
    }
});

interface HookSlot {
    value: any;
    deps?: readonly unknown[];
}

function depsChanged(
    prev: readonly unknown[] | undefined,
    next: readonly unknown[] | undefined,
) {
    if (!prev || !next || prev.length !== next.length) return true;
    return next.some((dep, index) => !Object.is(dep, prev[index]));
}

const hooks: HookSlot[] = [];
const pendingEffects: Array<{
    index: number;
    fn: () => void | (() => void);
}> = [];
let cursor = 0;

function resetHooks() {
    hooks.length = 0;
    pendingEffects.length = 0;
    cursor = 0;
}

vi.mock("react", async () => {
    const actual = await vi.importActual<typeof import("react")>("react");
    return {
        ...actual,
        default: actual,
        useState: (initial: any) => {
            const idx = cursor++;
            if (!(idx in hooks)) {
                hooks[idx] = {
                    value: typeof initial === "function" ? initial() : initial,
                };
            }
            const setState = (next: any) => {
                hooks[idx]!.value =
                    typeof next === "function"
                        ? next(hooks[idx]!.value)
                        : next;
            };
            return [hooks[idx]!.value, setState];
        },
        useDeferredValue: (val: any) => val,
        useRef: (initial: any) => {
            const idx = cursor++;
            if (!(idx in hooks)) {
                hooks[idx] = { value: { current: initial } };
            }
            return hooks[idx]!.value;
        },
        useMemo: (factory: () => any, deps: readonly unknown[]) => {
            const idx = cursor++;
            const slot = hooks[idx];
            if (!slot || depsChanged(slot.deps, deps)) {
                hooks[idx] = { value: factory(), deps };
            }
            return hooks[idx]!.value;
        },
        useCallback: (fn: any, deps: readonly unknown[]) => {
            const idx = cursor++;
            const slot = hooks[idx];
            if (!slot || depsChanged(slot.deps, deps)) {
                hooks[idx] = { value: fn, deps };
            }
            return hooks[idx]!.value;
        },
        useEffect: (
            fn: () => void | (() => void),
            deps?: readonly unknown[],
        ) => {
            const idx = cursor++;
            const slot = hooks[idx];
            if (!slot || depsChanged(slot.deps, deps)) {
                hooks[idx] = { value: undefined, deps };
                pendingEffects.push({ index: idx, fn });
            }
        },
        useContext: () => undefined,
    };
});

vi.mock("@mui/material", async () => {
    const actual =
        await vi.importActual<typeof import("@mui/material")>("@mui/material");
    return {
        ...actual,
        useTheme: () => actual.createTheme(),
        useMediaQuery: () => true,
    };
});

vi.mock("@/components/date-scrubber/timeline", async () => {
    return await vi.importActual<
        typeof import("../src/components/date-scrubber/timeline")
    >("../src/components/date-scrubber/timeline");
});

vi.mock("@/utils/file", () => ({
    selectedFavoriteCount: () => 0,
}));

vi.mock("@/utils/file-actions", () => ({
    getAvailableFileActions: () => [],
}));

vi.mock("@/utils/photoFrame", () => ({
    handleSelectCreator: vi.fn(),
    handleSelectCreatorMulti: vi.fn(),
}));

vi.mock("@/components/date-scrubber/DateScrubber", () => ({
    DateScrubber: () => null,
}));

vi.mock("@/components/FileContextMenu", () => ({
    FileContextMenu: () => null,
}));

vi.mock("@/components/gallery/sections/albums/AlbumEmptyState", () => ({
    AlbumEmptyState: () => null,
}));

vi.mock("@/components/Avatar", () => ({
    default: () => null,
}));

vi.mock("ente-gallery/services/download", () => ({
    downloadManager: {},
}));

vi.mock("comlink", () => ({
    expose: vi.fn(),
    wrap: vi.fn(),
    proxy: vi.fn((x) => x),
}));

vi.mock("ente-base/log", async (importOriginal) => {
    const actual = await importOriginal<typeof import("ente-base/log")>();
    return {
        ...actual,
        logUnhandledErrorsAndRejectionsInWorker: vi.fn(),
        default: { info: vi.fn(), warn: vi.fn(), error: vi.fn() },
    };
});

import { FileList, type FileListAnnotatedFile } from "../src/components/FileList";

function makeAnnotatedFiles(count: number, favoriteIds = new Set<number>()): FileListAnnotatedFile[] {
    const baseTime = Date.UTC(2026, 9, 1) * 1000;
    return Array.from({ length: count }, (_, idx) => {
        const id = idx + 1;
        const creationTime = baseTime + idx * 86_400_000_000;
        const file = {
            id,
            collectionID: 1,
            ownerID: 1,
            fileType: 0,
            creationTime,
            metadata: {
                creationTime,
                fileType: 0,
                title: `photo-${id}.jpg`,
            },
            isFavorite: favoriteIds.has(id),
        } as unknown as EnteFile;
        return {
            file,
            timelineDateString: `2026-10-${String((idx % 28) + 1).padStart(2, "0")}`,
        };
    });
}

function renderFileList(props: Parameters<typeof FileList>[0]) {
    for (let pass = 0; pass < 4; pass++) {
        cursor = 0;
        pendingEffects.length = 0;
        FileList(props);
        if (pendingEffects.length === 0) break;
        const effects = pendingEffects.splice(0);
        for (const effect of effects) {
            effect.fn();
        }
    }
}

describe("FileList scroll preservation on timeline updates", () => {
    beforeEach(() => {
        resetHooks();
        vi.stubGlobal("document", {
            addEventListener: vi.fn(),
            removeEventListener: vi.fn(),
        });
        vi.stubGlobal("window", {
            addEventListener: vi.fn(),
            removeEventListener: vi.fn(),
        });
    });

    afterEach(() => {
        vi.unstubAllGlobals();
    });

    test("preserves scroll position when annotatedFiles updates (e.g. favoriting) and clamps when list shrinks", () => {
        const scrollTo = vi.fn();
        const scrollToItem = vi.fn();
        const resetAfterIndex = vi.fn();
        const outerEl = { scrollTop: 0 };

        const baseProps = {
            width: 1000,
            height: 200,
            enableDateScrubber: true,
            selected: { count: 0, ownCount: 0, collectionID: 1 },
            setSelected: vi.fn(),
            activeCollectionID: 1,
            onItemClick: vi.fn(),
        };

        const initialFiles = makeAnnotatedFiles(30);
        renderFileList({ ...baseProps, annotatedFiles: initialFiles });

        // Attach mocked VariableSizeList and outer scroll container refs
        const refSlots = hooks.filter(
            (slot) =>
                slot.value &&
                typeof slot.value === "object" &&
                "current" in slot.value,
        );
        const listRefSlot = refSlots[2]!;
        const outerRefSlot = refSlots[3]!;
        listRefSlot.value.current = { scrollTo, scrollToItem, resetAfterIndex };
        outerRefSlot.value.current = outerEl;

        // Simulate user having scrolled down to offset 300
        outerEl.scrollTop = 300;
        scrollTo.mockClear();
        scrollToItem.mockClear();

        // Update annotatedFiles (e.g., favoriting a photo triggers timeline recalculation)
        const updatedFiles = makeAnnotatedFiles(30, new Set([1]));
        renderFileList({ ...baseProps, annotatedFiles: updatedFiles });

        expect(scrollToItem).not.toHaveBeenCalled();
        expect(scrollTo).not.toHaveBeenCalled();

        // Shrink list so maxOffset < current scrollTop (300) while scrubber stays active
        const fewerFiles = makeAnnotatedFiles(6);
        renderFileList({ ...baseProps, annotatedFiles: fewerFiles });

        expect(scrollToItem).not.toHaveBeenCalled();
        expect(scrollTo).toHaveBeenCalledTimes(1);
        const clampedOffset = scrollTo.mock.calls[0]![0] as number;
        expect(clampedOffset).toBeGreaterThan(0);
        expect(clampedOffset).toBeLessThan(300);
    });
});
