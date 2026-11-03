import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, test, vi } from "vitest";
import {
    BookContext,
    createBookStore,
    useBook,
    useBookSelector,
    type BookContextValue,
} from "./book";

let root: Root;
beforeEach(() => {
    vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
    root = createRoot(document.createElement("div"));
});
afterEach(() => {
    act(() => root.unmount());
    vi.unstubAllGlobals();
});

test("navigation and import progress do not rerender book content subscribers", () => {
    const value = {
        book: { pages: [], currentSpreadIndex: 0 },
        currentSpreadIndex: 0,
        processingProgress: 0,
    } as unknown as BookContextValue;
    const store = createBookStore(value);
    const rendered = vi.fn();
    function Content() {
        const { book } = useBook("book");
        rendered(book);
        return null;
    }
    act(() =>
        root.render(
            <BookContext.Provider value={store}>
                <Content />
            </BookContext.Provider>,
        ),
    );
    act(() =>
        store.update({
            ...value,
            currentSpreadIndex: 100,
            processingProgress: 50,
        }),
    );
    expect(rendered).toHaveBeenCalledTimes(1);
    act(() =>
        store.update({ ...value, book: { ...value.book, title: "Changed" } }),
    );
    expect(rendered).toHaveBeenCalledTimes(2);
});

test("image subscribers update only for their photo, including after changing the selected photo", () => {
    const value = {
        photoUrls: new Map([
            ["a", "blob:a"],
            ["b", "blob:b"],
        ]),
    } as BookContextValue;
    const store = createBookStore(value);
    const rendered = vi.fn();
    function Photo({ id }: { id: string }) {
        const url = useBookSelector((state) => state.photoUrls.get(id));
        rendered(url);
        return null;
    }
    const render = (id: string) =>
        root.render(
            <BookContext.Provider value={store}>
                <Photo id={id} />
            </BookContext.Provider>,
        );
    act(() => render("a"));
    const next = {
        ...value,
        photoUrls: new Map(value.photoUrls).set("b", "blob:b2"),
    };
    act(() => store.update(next));
    expect(rendered).toHaveBeenCalledTimes(1);
    act(() => render("b"));
    expect(rendered).toHaveBeenLastCalledWith("blob:b2");
    act(() =>
        store.update({
            ...next,
            photoUrls: new Map(next.photoUrls).set("b", "blob:b3"),
        }),
    );
    expect(rendered).toHaveBeenLastCalledWith("blob:b3");
});
