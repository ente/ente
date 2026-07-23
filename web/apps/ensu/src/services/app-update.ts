import { isTauriRuntime } from "@/services/tauri-runtime";
import type { MiniDialogAttributes } from "ente-base/components/MiniDialog";
import { buildEnvIsProductionBuild } from "ente-base/env";
import log from "ente-base/log";

const oneDay = 24 * 60 * 60 * 1000;

let intervalId: number | undefined;
let inFlightUpdateCheck: Promise<AppUpdateCheckResult> | undefined;
let promptedVersion: string | undefined;

type ShowMiniDialog = (attributes: MiniDialogAttributes) => void;

type AppUpdateCheckResult =
    | { kind: "not-supported" }
    | { kind: "up-to-date" }
    | { kind: "available"; version: string }
    | { kind: "error" };

export const checkForAppUpdates = async (): Promise<AppUpdateCheckResult> => {
    if (!isTauriRuntime()) return { kind: "not-supported" };
    if (inFlightUpdateCheck) return inFlightUpdateCheck;

    const run = async (): Promise<AppUpdateCheckResult> => {
        try {
            const { check } = await import("@tauri-apps/plugin-updater");
            const update = await check();
            if (!update) {
                log.debug(() => "Ensu is already on the latest version");
                return { kind: "up-to-date" };
            }

            const { version } = update;
            try {
                await update.close();
            } catch (e) {
                log.warn("Failed to close Ensu update check", e);
            }
            return { kind: "available", version };
        } catch (e) {
            log.error("Failed to auto-update Ensu", e);
            return { kind: "error" };
        }
    };

    inFlightUpdateCheck = run().finally(() => {
        inFlightUpdateCheck = undefined;
    });

    return inFlightUpdateCheck;
};

const installAppUpdate = async (version: string) => {
    try {
        const [{ check }, { relaunch }] = await Promise.all([
            import("@tauri-apps/plugin-updater"),
            import("@tauri-apps/plugin-process"),
        ]);

        log.info(`Installing Ensu update ${version}`);
        const update = await check();
        if (!update) {
            throw new Error(`Ensu update ${version} is no longer available`);
        }
        await update.downloadAndInstall();
        log.info(`Installed Ensu update ${version}, relaunching`);
        await relaunch();
    } catch (e) {
        log.error(`Failed to install Ensu update ${version}`, e);
        throw e;
    }
};

const showUpdatePrompt = (showMiniDialog: ShowMiniDialog, version: string) => {
    showMiniDialog({
        title: "Update available",
        message: `Ensu ${version} is available. Would you like to update now?`,
        continue: {
            text: "Update now",
            autoFocus: true,
            action: async () => {
                await installAppUpdate(version);
            },
        },
        cancel: "Later",
        buttonDirection: "row",
    });
};

const checkAndPromptForAppUpdates = async (showMiniDialog: ShowMiniDialog) => {
    const result = await checkForAppUpdates();
    if (result?.kind !== "available") return result;
    if (promptedVersion === result.version) return result;
    promptedVersion = result.version;
    showUpdatePrompt(showMiniDialog, result.version);
    return result;
};

export const handleManualAppUpdateCheck = async (
    showMiniDialog: ShowMiniDialog,
) => {
    const result = await checkForAppUpdates();
    if (!result || result.kind === "not-supported") return;

    if (result.kind === "up-to-date") {
        showMiniDialog({
            title: "Ensu is up to date",
            message: "You're already running the latest available version.",
        });
        return;
    }

    if (result.kind === "available") {
        promptedVersion = result.version;
        showUpdatePrompt(showMiniDialog, result.version);
        return;
    }

    showMiniDialog({
        title: "Update check failed",
        message:
            "We could not check for updates right now. Please try again in a moment.",
    });
};

export const setupAutoAppUpdates = (showMiniDialog: ShowMiniDialog) => {
    if (!isTauriRuntime() || !buildEnvIsProductionBuild || intervalId) {
        return () => {};
    }

    void checkAndPromptForAppUpdates(showMiniDialog);
    intervalId = window.setInterval(() => {
        void checkAndPromptForAppUpdates(showMiniDialog);
    }, oneDay);

    return () => {
        if (intervalId) {
            window.clearInterval(intervalId);
            intervalId = undefined;
        }
    };
};
