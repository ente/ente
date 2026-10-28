import type { Page } from "@playwright/test";
import type { AppView, BookState, Photo } from "../../src/lib/types";

export async function readSession(page: Page) {
    return page.evaluate(async () => {
        const database = await new Promise<IDBDatabase>((resolve, reject) => {
            const request = indexedDB.open("photobook");
            request.onsuccess = () => resolve(request.result);
            request.onerror = () =>
                reject(
                    new Error("Cannot open saved book", {
                        cause: request.error,
                    }),
                );
        });
        try {
            const store = database
                .transaction("metadata")
                .objectStore("metadata");
            const read = (key: string) =>
                new Promise<unknown>((resolve, reject) => {
                    const request = store.get(key);
                    request.onsuccess = () => resolve(request.result);
                    request.onerror = () =>
                        reject(
                            new Error("Cannot read saved book", {
                                cause: request.error,
                            }),
                        );
                });
            const [book, photos, view] = await Promise.all(
                ["bookState", "photos", "appView"].map(read),
            );
            return {
                book: book as BookState | undefined,
                photos: photos as Photo[] | undefined,
                view: view as AppView | undefined,
            };
        } finally {
            database.close();
        }
    });
}
