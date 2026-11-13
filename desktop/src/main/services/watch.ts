import chokidar, { type FSWatcher } from "chokidar";
import { BrowserWindow } from "electron/main";
import { FolderWatch, type CollectionMapping } from "../../types/ipc";
import log from "../log";
import { watchStore } from "../stores/watch";
import { posixPath } from "../utils/electron";
import { fsIsDir } from "./fs";

export const createWatcher = (mainWindow: BrowserWindow) => {
    const send = (eventName: string) => (path: string) =>
        mainWindow.webContents.send(eventName, ...eventData(path));

    const folderPaths = folderWatches().map((watch) => watch.folderPath);

    const watcher = chokidar.watch(folderPaths, {
        // Initial events duplicate the full scan performed at launch.
        ignoreInitial: true,
        awaitWriteFinish: true,
        // Chokidar v4 exhausts file descriptors on macOS without polling.
        // https://github.com/paulmillr/chokidar/issues/1385
        ...(process.platform == "darwin"
            ? { usePolling: true, interval: 5000, binaryInterval: 5000 }
            : {}),
    });

    watcher
        .on("add", send("watchAddFile"))
        .on("unlink", send("watchRemoveFile"))
        .on("unlinkDir", send("watchRemoveDir"))
        .on("error", (error) => log.error("Error while watching files", error));

    return watcher;
};

const eventData = (platformPath: string): [string, FolderWatch] => {
    const path = posixPath(platformPath);

    const watch = folderWatches().find((watch) =>
        path.startsWith(watch.folderPath + "/"),
    );

    if (!watch) throw new Error(`No folder watch was found for path ${path}`);

    return [path, watch];
};

export const watchGet = async (watcher: FSWatcher): Promise<FolderWatch[]> => {
    const result: FolderWatch[] = [];
    const watched = watcher.getWatched();

    for (const watch of folderWatches()) {
        const isAccessible = await fsIsDir(watch.folderPath);
        result.push({ ...watch, isAccessible });

        if (isAccessible) {
            if (!watched[watch.folderPath]) {
                watcher.add(watch.folderPath);
            }
        } else {
            watcher.unwatch(watch.folderPath);
        }
    }

    return result;
};

const folderWatches = (): FolderWatch[] => watchStore.get("mappings") ?? [];

const setFolderWatches = (watches: FolderWatch[]) =>
    watchStore.set("mappings", watches);

export const watchAdd = async (
    watcher: FSWatcher,
    folderPath: string,
    collectionMapping: CollectionMapping,
) => {
    const watches = folderWatches();

    if (!(await fsIsDir(folderPath)))
        throw new Error(
            `Attempting to add a folder watch for a folder path ${folderPath} that is not an existing directory`,
        );

    if (watches.find((watch) => watch.folderPath == folderPath))
        throw new Error(
            `A folder watch with the given folder path ${folderPath} already exists`,
        );

    watches.push({
        folderPath,
        collectionMapping,
        syncedFiles: [],
        ignoredFiles: [],
    });

    setFolderWatches(watches);

    watcher.add(folderPath);

    return await Promise.all(
        watches.map(async (watch) => ({
            ...watch,
            isAccessible: await fsIsDir(watch.folderPath),
        })),
    );
};

export const watchRemove = async (watcher: FSWatcher, folderPath: string) => {
    const watches = folderWatches();
    const filtered = watches.filter((watch) => watch.folderPath != folderPath);
    if (watches.length == filtered.length)
        throw new Error(
            `Attempting to remove a non-existing folder watch for folder path ${folderPath}`,
        );
    setFolderWatches(filtered);
    watcher.unwatch(folderPath);
    return await Promise.all(
        filtered.map(async (watch) => ({
            ...watch,
            isAccessible: await fsIsDir(watch.folderPath),
        })),
    );
};

export const watchUpdateSyncedFiles = (
    syncedFiles: FolderWatch["syncedFiles"],
    folderPath: string,
) => {
    setFolderWatches(
        folderWatches().map((watch) => {
            if (watch.folderPath == folderPath) {
                watch.syncedFiles = syncedFiles;
            }
            return watch;
        }),
    );
};

export const watchUpdateIgnoredFiles = (
    ignoredFiles: FolderWatch["ignoredFiles"],
    folderPath: string,
) => {
    setFolderWatches(
        folderWatches().map((watch) => {
            if (watch.folderPath == folderPath) {
                watch.ignoredFiles = ignoredFiles;
            }
            return watch;
        }),
    );
};

export const watchReset = (watcher: FSWatcher) => {
    watcher.unwatch(folderWatches().map((watch) => watch.folderPath));
};
