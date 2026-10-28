"use client";

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
    type Dispatch,
    type SetStateAction,
} from "react";

interface BookContextValue {
    appView: AppView;
    setAppView: (view: AppView) => void;
    loading: boolean;

    photos: Photo[];
    thumbnailUrls: Map<string, string>;
    photoUrls: Map<string, string>;
    loadPreviews: (photoIds: string[]) => Promise<void>;
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
        photoIds?: string[],
        onProgress?: (done: number, total: number) => void,
    ) => Promise<void>;

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

export const BookContext = createContext<BookContextValue | null>(null);

export function useBook() {
    const ctx = useContext(BookContext);
    if (!ctx) throw new Error("useBook must be used within BookProvider");
    return ctx;
}
