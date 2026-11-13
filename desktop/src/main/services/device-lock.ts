import { systemPreferences } from "electron/main";
import type { NativeDeviceLockCapability } from "../../types/ipc";
import log from "../log";

export const getNativeDeviceLockCapability = (): NativeDeviceLockCapability => {
    switch (process.platform) {
        case "darwin":
            try {
                if (systemPreferences.canPromptTouchID()) {
                    return { available: true, provider: "touchid" };
                }

                return {
                    available: false,
                    provider: "none",
                    // canPromptTouchID() can be false during transient lockouts.
                    reason: "touchid-temporarily-unavailable",
                };
            } catch (e) {
                log.warn(
                    "Failed to determine native device lock availability",
                    e,
                );
                return {
                    available: false,
                    provider: "none",
                    reason: "touchid-api-error",
                };
            }

        default:
            return {
                available: false,
                provider: "none",
                reason: "unsupported-platform",
            };
    }
};

export const promptDeviceLock = async (reason: string) => {
    if (process.platform !== "darwin") {
        log.warn("Native device lock prompt is unavailable on this OS");
        return false;
    }

    try {
        await systemPreferences.promptTouchID(reason);
        return true;
    } catch (e) {
        log.info("Native device lock prompt not completed", e);
        return false;
    }
};
