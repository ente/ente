import type { AddPhotosOptions } from "@/lib/photoPlacement";
import type {
    AppView,
    BookPage,
    BookState,
    Photo,
    PhotoSlot,
    TextBlock,
} from "@/lib/types";
import {
    createContext,
    useContext,
    useRef,
    useSyncExternalStore,
    type Dispatch,
    type SetStateAction,
} from "react";

export interface BookContextValue {
    appView: AppView;
    setAppView: (view: AppView) => void;
    loading: boolean;

    photos: Photo[];
    getPhoto: (id: string) => Photo | undefined;
    thumbnailUrls: Map<string, string>;
    photoUrls: Map<string, string>;
    retainPreviews: (photoIds: string[]) => () => void;
    addPhotos: (
        files: File[],
        options?: AddPhotosOptions,
    ) => Promise<string | undefined>;
    addEntePhotos: (
        albumUrl: string,
        requestPassword: () => Promise<string | null>,
    ) => Promise<void>;
    processingPhotos: boolean;
    processingProgress: number;
    processingMessage: string;
    importNotice: string | null;
    clearImportNotice: () => void;
    pendingEnteOriginals: Set<string>;
    waitForEnteOriginals: (
        photoIds: string[],
        onProgress?: (done: number, total: number) => void,
    ) => Promise<boolean>;

    book: BookState;
    setBook: Dispatch<SetStateAction<BookState>>;
    currentSpreadIndex: number;
    setCurrentSpreadIndex: (idx: number) => void;

    undo: () => void;
    redo: () => void;
    canUndo: boolean;
    canRedo: boolean;

    addPage: (afterIndex?: number) => string;
    removePage: (pageId: string) => void;
    reorderPages: (fromIndex: number, toIndex: number) => void;
    updatePage: (pageId: string, updates: Partial<BookPage>) => void;
    updateSlot: (
        pageId: string,
        slotId: string,
        updates: Partial<PhotoSlot>,
    ) => void;
    removeSlot: (pageId: string, slotId: string) => void;
    swapPhotos: (
        fromPageId: string,
        fromSlotId: string,
        toPageId: string,
        toSlotId: string,
    ) => void;
    movePhotoToPage: (
        fromPageId: string,
        fromSlotId: string,
        toPageId: string,
    ) => void;
    setPageLayout: (pageId: string, variantKey: string) => void;
    addTextBlock: (pageId: string) => TextBlock;
    updateTextBlock: (
        pageId: string,
        blockId: string,
        updates: Partial<TextBlock>,
    ) => void;
    removeTextBlock: (pageId: string, blockId: string) => void;

    startOver: () => Promise<void>;
}

export function createBookStore(initial: BookContextValue) {
    let value = initial;
    const listeners = new Set<() => void>();
    return {
        getSnapshot: () => value,
        subscribe: (listener: () => void) => {
            listeners.add(listener);
            return () => {
                listeners.delete(listener);
            };
        },
        update: (next: BookContextValue) => {
            value = next;
            listeners.forEach((listener) => listener());
        },
    };
}

export const BookContext = createContext<ReturnType<
    typeof createBookStore
> | null>(null);

export function useBookSelector<T>(
    selector: (state: BookContextValue) => T,
    equal: (a: T, b: T) => boolean = Object.is,
): T {
    const store = useContext(BookContext);
    if (!store) throw new Error("useBook must be used within BookProvider");
    const previous = useRef<{ value: T } | undefined>(undefined);
    const getSnapshot = () => {
        const selected = selector(store.getSnapshot());
        if (previous.current && equal(previous.current.value, selected))
            return previous.current.value;
        previous.current = { value: selected };
        return selected;
    };
    return useSyncExternalStore(store.subscribe, getSnapshot, getSnapshot);
}

export function useBook<K extends keyof BookContextValue>(
    ...keys: [K, ...K[]]
): Pick<BookContextValue, K> {
    return useBookSelector(
        (state) =>
            Object.fromEntries(keys.map((key) => [key, state[key]])) as Pick<
                BookContextValue,
                K
            >,
        (a, b) =>
            Object.keys(a).length === keys.length &&
            keys.every((key) => Object.is(a[key], b[key])),
    );
}
