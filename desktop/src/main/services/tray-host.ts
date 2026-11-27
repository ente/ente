import { execFile } from "node:child_process";
import { promisify } from "node:util";
import log from "../log";

export type TrayHostStatus = "present" | "absent" | "unknown";

const watcherName = "org.kde.StatusNotifierWatcher";

const execFileAsync = promisify(execFile);

const commands: [string, string[]][] = [
    [
        "gdbus",
        [
            "call",
            "--session",
            "--dest",
            "org.freedesktop.DBus",
            "--object-path",
            "/org/freedesktop/DBus",
            "--method",
            "org.freedesktop.DBus.NameHasOwner",
            watcherName,
        ],
    ],
    [
        "dbus-send",
        [
            "--session",
            "--print-reply",
            "--dest=org.freedesktop.DBus",
            "/org/freedesktop/DBus",
            "org.freedesktop.DBus.NameHasOwner",
            `string:${watcherName}`,
        ],
    ],
];

const parseNameHasOwnerOutput = (stdout: string): boolean | undefined => {
    const match = /\(\s*(true|false)\s*,\s*\)|\bboolean\s+(true|false)\b/.exec(
        stdout,
    );
    const value = match?.[1] ?? match?.[2];
    return value === undefined ? undefined : value == "true";
};

export const detectTrayHost = async (): Promise<TrayHostStatus> => {
    for (const [file, args] of commands) {
        try {
            const { stdout } = await execFileAsync(file, args, {
                timeout: 2000,
            });
            const hasOwner = parseNameHasOwnerOutput(stdout);
            if (hasOwner !== undefined) return hasOwner ? "present" : "absent";
            log.warn(`Unexpected ${file} output when detecting tray host`);
        } catch (e) {
            log.warn(`Could not detect tray host using ${file}`, e);
        }
    }
    return "unknown";
};
