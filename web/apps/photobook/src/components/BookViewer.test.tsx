import {
    BookContext,
    createBookStore,
    type BookContextValue,
} from "@/context/book";
import { makeBlankPage } from "@/lib/bookPages";
import { applyVariant } from "@/lib/layouts";
import { getFlipPageIndex } from "@/lib/spreads";
import { act, type ReactNode } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, test, vi, type Mock } from "vitest";
import BookViewer from "./BookViewer";

const state = vi.hoisted(() => ({
    books: [] as import("page-flip").PageFlip[],
    mobile: false,
}));
vi.mock("page-flip", async (original) => {
    const { PageFlip } = await original<typeof import("page-flip")>();
    return {
        PageFlip: class extends PageFlip {
            constructor(...args: ConstructorParameters<typeof PageFlip>) {
                super(...args);
                state.books.push(this);
            }
        },
    };
});
vi.mock("@mui/material", async (original) => ({
    ...(await original<typeof import("@mui/material")>()),
    useMediaQuery: (query: string) => state.mobile && query.includes("599"),
}));
vi.mock("react-konva", () => ({
    Stage: ({ children }: { children: ReactNode }) => (
        <div data-testid="stage">{children}</div>
    ),
    Layer: ({ children }: { children: ReactNode }) => children,
}));
vi.mock("./PageCanvas", () => ({
    default: ({ page }: { page: { id: string } }) => (
        <div data-rendered-page={page.id} />
    ),
}));
vi.mock("./BookPageNavigation", () => ({ default: () => null }));

let root: Root;
let host: HTMLDivElement;
let retained: Set<string>;
let retain: Mock<(ids: string[]) => () => void>;

beforeEach(() => {
    vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
    vi.useFakeTimers();
    vi.spyOn(HTMLElement.prototype, "offsetWidth", "get").mockReturnValue(1000);
    vi.spyOn(HTMLElement.prototype, "offsetHeight", "get").mockReturnValue(500);
    state.mobile = false;
    state.books = [];
    retained = new Set();
    retain = vi.fn((ids: string[]) => {
        ids.forEach((id) => retained.add(id));
        return () => ids.forEach((id) => retained.delete(id));
    });
    host = document.createElement("div");
    document.body.append(host);
    root = createRoot(host);
});
afterEach(() => {
    act(() => root.unmount());
    host.remove();
    vi.restoreAllMocks();
    vi.unstubAllGlobals();
    vi.useRealTimers();
});

function renderBook(count: number) {
    const pages = Array.from({ length: count }, (_, index) => ({
        ...makeBlankPage(),
        id: String(index),
        slots: applyVariant("1-full", [String(index)]),
    }));
    const value = {
        book: { pages, currentSpreadIndex: 0 },
        retainPreviews: retain,
    } as unknown as BookContextValue;
    const store = createBookStore(value);
    act(() =>
        root.render(
            <BookContext.Provider value={store}>
                <BookViewer pages={pages} onSpreadChange={vi.fn()} />
            </BookContext.Provider>,
        ),
    );
    act(() => {
        vi.advanceTimersByTime(1);
    });
}

test("a 300-page preview mounts at most six page canvases and retains only neighboring images", () => {
    renderBook(300);
    const book = state.books[0]!;
    for (const page of [0, 2, 100, 200, 298, 299, 1]) {
        act(() => book.turnToPage(getFlipPageIndex(300, page)!));
        expect(
            host.querySelectorAll('[data-testid="stage"]').length,
        ).toBeLessThanOrEqual(6);
        expect(
            host.querySelector(`[data-rendered-page="${page}"]`),
        ).not.toBeNull();
        expect(retained.size).toBeLessThanOrEqual(6);
        expect(retained.has(String(page))).toBe(true);
    }
    act(() => root.unmount());
    expect(retained.size).toBe(0);
    root = createRoot(host);
});

test("overlapping preview windows preserve their existing image leases", () => {
    renderBook(300);
    const book = state.books[0]!;
    act(() => book.turnToPage(getFlipPageIndex(300, 100)!));
    retain.mockClear();
    act(() => book.turnToPage(getFlipPageIndex(300, 102)!));
    expect(retain.mock.calls.flatMap(([ids]) => ids)).toEqual(
        [104, 105].map(String),
    );
});

test("phone preview mounts only one canvas", () => {
    state.mobile = true;
    renderBook(300);
    expect(host.querySelectorAll('[data-testid="stage"]')).toHaveLength(1);
    expect(retained.size).toBeLessThanOrEqual(6);
});
