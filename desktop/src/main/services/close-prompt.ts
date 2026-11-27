import { dialog, type BrowserWindow } from "electron/main";
import type { SavedCloseAction } from "../../types/ipc";
import { uploadStatusStore } from "../stores/upload-status";
import { watchStore } from "../stores/watch";

interface BackgroundWorkSummary {
    watchedFolderCount: number;
    pendingUploadCount: number;
}

/**
 * Background work the main process knows about without asking the renderer.
 *
 * Reads the raw store values; `pendingUploads()` would stat every path.
 */
const backgroundWorkSummary = (): BackgroundWorkSummary => {
    const watchedFolderCount = watchStore.get("mappings")?.length ?? 0;
    const pendingUploadCount =
        (uploadStatusStore.get("filePaths")?.length ?? 0) +
        (uploadStatusStore.get("zipItems")?.length ?? 0);
    return { watchedFolderCount, pendingUploadCount };
};

const plural = (count: number, singular: string, plural: string) =>
    `${count.toLocaleString()} ${count == 1 ? singular : plural}`;

const backgroundWorkLines = ({
    watchedFolderCount,
    pendingUploadCount,
}: BackgroundWorkSummary) => {
    const lines: string[] = [];
    if (pendingUploadCount > 0) {
        const items = plural(pendingUploadCount, "file is", "files are");
        lines.push(`${items} still uploading.`);
    }
    if (watchedFolderCount > 0) {
        const folders = plural(watchedFolderCount, "folder", "folders");
        lines.push(`Ente is watching ${folders} for new photos.`);
    }
    return lines;
};

/**
 * Ask the user what closing the window should do when there is no tray icon
 * to get the window back from.
 */
export const showNoTrayCloseDialog = async (
    window: BrowserWindow,
): Promise<{ action: SavedCloseAction | "cancel"; remember: boolean }> => {
    const workLines = backgroundWorkLines(backgroundWorkSummary());

    const detail = [
        "There's no system tray on this desktop, so Ente can't show an icon while it runs in the background.",
        ...(workLines.length
            ? [
                  "",
                  ...workLines,
                  "Quitting will stop this until you open Ente again.",
              ]
            : []),
        "",
        "Quit – Ente closes completely.",
        "Run in background – Ente keeps running with no window or icon. Open Ente again to bring it back.",
    ].join("\n");

    const buttons = ["Quit", "Run in background", "Cancel"] as const;
    const { response, checkboxChecked } = await dialog.showMessageBox(window, {
        type: "question",
        buttons: [...buttons],
        defaultId: 0,
        cancelId: 2,
        title: "Close Ente?",
        message: "Close Ente?",
        detail,
        checkboxLabel: "Remember my choice",
        checkboxChecked: false,
        noLink: true,
    });

    const action =
        response == 0 ? "quit" : response == 1 ? "background" : "cancel";
    return { action, remember: action != "cancel" && checkboxChecked };
};
