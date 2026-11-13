import type { Electron } from "./types/ipc";

declare global {
    // Preload injects this only in Electron renderers.
    declare var electron: Electron | undefined;
}
