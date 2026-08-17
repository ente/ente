import exportService from "@/services/export";
import {
    accountLogout,
    logoutClearStateAgain,
} from "ente-accounts/services/logout";
import log from "ente-base/log";
import { resetSaveGroups } from "ente-gallery/components/utils/save-groups";
import { logoutFileViewerDataSource } from "ente-gallery/components/viewer/data-source";
import { downloadManager } from "ente-gallery/services/download";
import { clearFilesDB } from "ente-gallery/services/files-db";
import { resetUploadState } from "ente-gallery/services/upload";
import { resetVideoState } from "ente-gallery/services/video";
import { logoutAppLock } from "ente-new/photos/services/app-lock";
import { logoutML, terminateMLWorker } from "ente-new/photos/services/ml";
import { logoutSearch } from "ente-new/photos/services/search";
import { logoutSettings } from "ente-new/photos/services/settings";
import { logoutUserDetails } from "ente-new/photos/services/user-details";
import { uploadManager } from "./upload-manager";

// Individual cleanup failures must not abort logout.
export const photosLogout = async () => {
    const ignoreError = (label: string, e: unknown) =>
        log.error(`Ignoring error during logout (${label})`, e);

    // Stop workers before clearing databases they may still access.
    try {
        await terminateMLWorker();
    } catch (e) {
        ignoreError("ML/worker", e);
    }

    await accountLogout();

    log.info("logout (photos)");

    try {
        await clearFilesDB();
    } catch (e) {
        ignoreError("Files DB", e);
    }

    try {
        logoutSettings();
    } catch (e) {
        ignoreError("Settings", e);
    }

    try {
        logoutUserDetails();
    } catch (e) {
        ignoreError("User details", e);
    }

    try {
        resetUploadState();
    } catch (e) {
        ignoreError("Upload", e);
    }

    try {
        uploadManager.logout();
    } catch (e) {
        ignoreError("Upload", e);
    }

    try {
        downloadManager.logout();
    } catch (e) {
        ignoreError("Download", e);
    }

    try {
        resetSaveGroups();
    } catch (e) {
        ignoreError("Download UI", e);
    }

    try {
        logoutSearch();
    } catch (e) {
        ignoreError("Search", e);
    }

    try {
        resetVideoState();
    } catch (e) {
        ignoreError("Video", e);
    }

    try {
        logoutFileViewerDataSource();
    } catch (e) {
        ignoreError("File viewer", e);
    }

    const electron = globalThis.electron;
    if (electron) {
        try {
            await logoutAppLock();
        } catch (e) {
            ignoreError("App lock", e);
        }

        try {
            await logoutML();
        } catch (e) {
            ignoreError("ML", e);
        }

        try {
            exportService.disableContinuousExport();
        } catch (e) {
            ignoreError("Export", e);
        }

        try {
            await electron.logout();
        } catch (e) {
            ignoreError("Electron", e);
        }
    }

    // Clear again after in-flight work has had a chance to finish.
    await logoutClearStateAgain();

    try {
        await clearFilesDB();
    } catch (e) {
        ignoreError("Files DB", e);
    }

    // Reload to discard any requests still in flight.
    window.location.replace("/");
};
