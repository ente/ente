import { makeBlankPage } from "@/lib/bookPages";
import * as db from "@/lib/db";
import { applyVariant } from "@/lib/layouts";
import type { BookState, Photo } from "@/lib/types";
import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, test, vi } from "vitest";
import { useBook } from "./book";
import { BookProvider } from "./BookContext";

vi.mock("@/lib/db");
vi.mock("@/lib/images", () => ({
    createThumbnail: vi.fn(),
    extractExifDate: vi.fn(),
    normalizeImportedImageBlob: vi.fn(),
}));

const savedPhotos: Photo[] = [
    {
        id: "photo-1",
        fileName: "holiday.jpg",
        width: 1200,
        height: 800,
        dateTaken: 0,
    },
];
let savedBook: BookState;
let container: HTMLDivElement;
let root: Root;
let bookContext: ReturnType<typeof useBook>;

function Editor() {
    bookContext = useBook();
    return <div data-testid="editor">{bookContext.book.title}</div>;
}

async function renderBook() {
    await act(async () => {
        root.render(
            <BookProvider>
                <Editor />
            </BookProvider>,
        );
        await Promise.resolve();
    });
}

async function runAutosave() {
    await act(async () => {
        await vi.advanceTimersByTimeAsync(1000);
    });
}

beforeEach(() => {
    vi.resetAllMocks();
    vi.useFakeTimers({ toFake: ["setTimeout", "clearTimeout"] });
    vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
    vi.spyOn(console, "error").mockImplementation(() => undefined);
    Object.defineProperty(document, "fonts", {
        configurable: true,
        value: { ready: Promise.resolve() },
    });
    savedBook = {
        title: "Our holiday",
        currentSpreadIndex: 1,
        pages: [
            {
                ...makeBlankPage(),
                slots: applyVariant("1-full", ["photo-1"]),
                layoutVariant: "1-full",
                topCaption: "Summer memories",
            },
            makeBlankPage(),
        ],
    };
    vi.mocked(db.getAppView).mockResolvedValue("edit");
    vi.mocked(db.getPhotos).mockResolvedValue(savedPhotos);
    vi.mocked(db.getBookState).mockResolvedValue(savedBook);
    vi.mocked(db.getThumbnail).mockResolvedValue(null);
    container = document.createElement("div");
    document.body.appendChild(container);
    root = createRoot(container);
});

afterEach(() => {
    act(() => {
        root.unmount();
    });
    container.remove();
    vi.useRealTimers();
    vi.restoreAllMocks();
    vi.unstubAllGlobals();
});

test.each(["getAppView", "getPhotos", "getBookState", "getThumbnail"] as const)(
    "preserves the saved book when %s fails",
    async (read) => {
        vi.mocked(db[read]).mockRejectedValueOnce(new Error("Read failed"));

        await renderBook();
        await runAutosave();

        expect(db.saveBookState).not.toHaveBeenCalled();
        expect(db.savePhotos).not.toHaveBeenCalled();
        expect(db.saveAppView).not.toHaveBeenCalled();
        expect(db.clearAll).not.toHaveBeenCalled();
        expect(container.querySelector('[data-testid="editor"]')).toBeNull();
        expect(
            document.querySelector('[role="alertdialog"]')?.textContent,
        ).toContain("Couldn't open photobook");
        const reload = vi
            .spyOn(window.location, "reload")
            .mockImplementation(() => undefined);
        document
            .querySelector<HTMLButtonElement>('[role="alertdialog"] button')!
            .click();
        expect(reload).toHaveBeenCalledOnce();
    },
);

test("restores and autosaves the saved layout, captions and photos", async () => {
    await renderBook();
    await runAutosave();

    expect(bookContext.loading).toBe(false);
    expect(bookContext.book).toEqual(savedBook);
    expect(bookContext.photos).toEqual(savedPhotos);
    expect(db.saveBookState).toHaveBeenCalledWith(savedBook);
    expect(db.savePhotos).toHaveBeenCalledWith(savedPhotos);

    act(() => {
        bookContext.setBook({ ...bookContext.book, title: "Edited holiday" });
    });
    await runAutosave();
    expect(db.saveBookState).toHaveBeenLastCalledWith({
        ...savedBook,
        title: "Edited holiday",
    });
});

test("allows a new book when no saved session exists", async () => {
    vi.mocked(db.getAppView).mockResolvedValue(null);
    vi.mocked(db.getPhotos).mockResolvedValue(null);
    vi.mocked(db.getBookState).mockResolvedValue(null);

    await renderBook();
    await runAutosave();

    expect(document.querySelector('[role="alertdialog"]')).toBeNull();
    expect(bookContext.loading).toBe(false);
    expect(db.saveBookState).toHaveBeenCalledWith({
        pages: [],
        currentSpreadIndex: 0,
    });
    expect(db.savePhotos).toHaveBeenCalledWith([]);
});

test("restores the saved book after reloading following a failed read", async () => {
    vi.mocked(db.getThumbnail).mockRejectedValueOnce(new Error("Read failed"));
    await renderBook();
    await runAutosave();
    expect(db.saveBookState).not.toHaveBeenCalled();

    act(() => {
        root.unmount();
    });
    root = createRoot(container);
    await renderBook();
    await runAutosave();

    expect(document.querySelector('[role="alertdialog"]')).toBeNull();
    expect(bookContext.book).toEqual(savedBook);
    expect(bookContext.photos).toEqual(savedPhotos);
    expect(db.saveBookState).toHaveBeenCalledWith(savedBook);
    expect(db.savePhotos).toHaveBeenCalledWith(savedPhotos);
});
