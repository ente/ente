import { nullToUndefined } from "ente-utils/transform";

// Preserve logs across logout.
export const clearLocalStorage = () => {
    const existingLogs = nullToUndefined(localStorage.getItem("logs"));
    localStorage.clear();
    if (existingLogs) {
        localStorage.setItem("logs", existingLogs);
    }
};
