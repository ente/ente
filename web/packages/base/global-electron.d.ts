import type { Electron } from "./types/ipc";

declare global {
    // Preload injects this only in Electron renderers.
    var electron: Electron | undefined;
}
