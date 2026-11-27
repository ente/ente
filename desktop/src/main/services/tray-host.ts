import { execFile } from "node:child_process";
import { promisify } from "node:util";
import log from "../log";

/**
 * Whether the desktop session has a StatusNotifier host, i.e. somewhere for
 * our tray icon to appear.
 *
 * On Linux, Electron's tray icon is a StatusNotifierItem. GNOME without the
 * AppIndicator extension has no host, so the icon never shows. Desktops with
 * only a legacy XEmbed tray may still show one and are reported as absent;
 * they just see the close prompt. Hosts
 * (KDE Plasma, the GNOME AppIndicator extension, XFCE, Cinnamon, ...) own the
 * well-known `org.kde.StatusNotifierWatcher` name on the session bus.
 *
 * `"unknown"` means neither D-Bus CLI worked; callers keep the existing
 * hide-to-tray behaviour in that case.
 */
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

/**
 * Parse the reply of a `NameHasOwner` call printed by either `gdbus` (e.g.
 * "(true,)") or `dbus-send --print-reply` (e.g. "... boolean true").
 */
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
