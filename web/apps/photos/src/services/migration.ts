import { getKVN, setKV } from "ente-base/kv";
import log from "ente-base/log";

// Runs cross-store migrations sequentially before normal app startup.
// Do not add work here that depends on later initialization.
export const runMigrations = async () => {
    const m = (await getKVN("migrationLevel")) ?? 0;
    const latest = 5;
    if (m < latest) {
        log.info(`Running migrations ${m} => ${latest}`);
        // Migration levels 1-5 (Aug 2024 - Feb 2025) were pruned.
        // New migrations should be 6+.
        await setKV("migrationLevel", latest);
    }
};
