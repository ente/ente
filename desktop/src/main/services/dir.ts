import { shell } from "electron/common";
import { app, dialog } from "electron/main";
import { existsSync } from "node:fs";
import path from "node:path";
import { posixPath } from "../utils/electron";

export const selectDirectory = async () => {
    const result = await dialog.showOpenDialog({
        properties: ["openDirectory"],
    });
    const dirPath = result.filePaths[0];
    return dirPath ? posixPath(dirPath) : undefined;
};

export const openDirectory = async (dirPath: string) => {
    // shell.openPath requires native separators, not our POSIX IPC paths.
    const nativePath = path.normalize(dirPath);

    // On Linux shell.openPath's promise never settles, so don't await it.
    if (process.platform == "linux") {
        if (!existsSync(nativePath))
            throw new Error(`Failed to open directory ${dirPath}`);
        void shell.openPath(nativePath);
        return;
    }

    const res = await shell.openPath(nativePath);
    // Electron resolves with an error message on failure.
    if (res) throw new Error(`Failed to open directory ${dirPath}: ${res}`);
};

export const openLogDirectory = () => openDirectory(logDirectoryPath());

// macOS: ~/Library/Logs/ente/ente.log (production)
// Linux: ~/.config/ente/logs/ente.log
// Windows: %USERPROFILE%\AppData\Roaming\ente\logs\ente.log
const logDirectoryPath = () => app.getPath("logs");
