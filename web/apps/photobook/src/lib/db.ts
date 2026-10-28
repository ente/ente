import log from "ente-base/log";
import { openDB, type DBSchema } from "idb";
import type { AppView, BookState, Photo } from "./types";

interface Metadata {
    bookState: BookState;
    photos: Photo[];
    appView: AppView;
}

interface PhotobookDBSchema extends DBSchema {
    photo_blobs: { key: string; value: Blob };
    thumbnails: { key: string; value: Blob };
    previews: { key: string; value: Blob };
    metadata: { key: keyof Metadata; value: Metadata[keyof Metadata] };
}

let _photobookDB: ReturnType<typeof openPhotobookDB> | undefined;

const openPhotobookDB = async () => {
    const db = await openDB<PhotobookDBSchema>("photobook", 1, {
        upgrade(db) {
            db.createObjectStore("photo_blobs");
            db.createObjectStore("thumbnails");
            db.createObjectStore("previews");
            db.createObjectStore("metadata");
        },
        blocking() {
            db.close();
            _photobookDB = undefined;
        },
        blocked() {
            log.warn("Waiting for another tab to close the Photobook database");
        },
        terminated() {
            log.warn("The Photobook database connection was terminated");
            _photobookDB = undefined;
        },
    });
    return db;
};

const photobookDB = () => (_photobookDB ??= openPhotobookDB());

const getMetadata = async <K extends keyof Metadata>(key: K) => {
    const db = await photobookDB();
    return ((await db.get("metadata", key)) as Metadata[K] | undefined) ?? null;
};

const saveMetadata = async <K extends keyof Metadata>(
    key: K,
    value: Metadata[K],
) => {
    const db = await photobookDB();
    await db.put("metadata", value, key);
};

export async function savePhotoBlob(id: string, blob: Blob): Promise<void> {
    const db = await photobookDB();
    await db.put("photo_blobs", blob, id);
}

export async function getPhotoBlob(id: string): Promise<Blob | null> {
    const db = await photobookDB();
    return (await db.get("photo_blobs", id)) ?? null;
}

export async function saveThumbnail(id: string, blob: Blob): Promise<void> {
    const db = await photobookDB();
    await db.put("thumbnails", blob, id);
}

export async function getThumbnail(id: string): Promise<Blob | null> {
    const db = await photobookDB();
    return (await db.get("thumbnails", id)) ?? null;
}

export async function savePreview(id: string, blob: Blob): Promise<void> {
    const db = await photobookDB();
    await db.put("previews", blob, id);
}

export async function getPreview(id: string): Promise<Blob | null> {
    const db = await photobookDB();
    return (await db.get("previews", id)) ?? null;
}

export const saveBookState = (state: BookState) =>
    saveMetadata("bookState", state);

export const getBookState = () => getMetadata("bookState");

export const savePhotos = (photos: Photo[]) => saveMetadata("photos", photos);

export const getPhotos = () => getMetadata("photos");

export const saveAppView = (view: AppView) => saveMetadata("appView", view);

export const getAppView = () => getMetadata("appView");

export async function clearAll(): Promise<void> {
    const db = await photobookDB();
    const tx = db.transaction(
        ["photo_blobs", "thumbnails", "previews", "metadata"],
        "readwrite",
    );
    await Promise.all([
        tx.objectStore("photo_blobs").clear(),
        tx.objectStore("thumbnails").clear(),
        tx.objectStore("previews").clear(),
        tx.objectStore("metadata").clear(),
        tx.done,
    ]);
}
