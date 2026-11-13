import shellescape from "any-shell-escape";
import { app } from "electron/main";
import { exec } from "node:child_process";
import path from "node:path";
import { promisify } from "node:util";
import log from "../log";

export const isDev = !app.isPackaged;

// Persisted and IPC paths use POSIX separators on every platform.
export const posixPath = (platformPath: string) =>
    path.sep == path.posix.sep
        ? platformPath
        : platformPath.split(path.sep).join(path.posix.sep);

export const execAsync = async (command: string | string[]) => {
    const escapedCommand = Array.isArray(command)
        ? shellescape(command)
        : command;
    const startTime = Date.now();
    const result = await execAsync_(
        process.platform == "win32"
            ? escapedCommand
            : `umask 077 && ${escapedCommand}`,
    );
    log.debug(() => `${escapedCommand} (${Date.now() - startTime} ms)`);
    return result;
};

const execAsync_ = promisify(exec);
