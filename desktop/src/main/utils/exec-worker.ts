import shellescape from "any-shell-escape";
import { exec } from "node:child_process";
import { promisify } from "node:util";
import log from "../log-worker";

export const execAsyncWorker = async (command: string | string[]) => {
    const escapedCommand = Array.isArray(command)
        ? shellescape(command)
        : command;
    const startTime = Date.now();
    const result = await execAsync_(
        process.platform == "win32"
            ? escapedCommand
            : `umask 077 && ${escapedCommand}`,
    );
    log.debugString(`${escapedCommand} (${Date.now() - startTime} ms)`);
    return result;
};

const execAsync_ = promisify(exec);
