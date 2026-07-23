import { getKVN, setKV } from "ente-base/kv";
import log from "ente-base/log";

/**
 * App specific migrations.
 *
 * The app stores data in multiple places: local storage, IndexedDB, OPFS, and
 * not all of these support DB migrations. And even when they do, those are
 * rather heavy weight and complicated (e.g. IndexedDB).
 *
 * Further, there are various app level migrations, e.g. resetting the diff
 * fetch times, that don't correspond to DB migrations, these are just changes
 * we need to make to our locally persisted values and not the schemas
 * themselves.
 *
 * Thus we introduce the concept of app level migrations. This is some code
 * which runs early in the page load, and runs arbitrary blocks of code until it
 * reaches the last migration number.
 *
 * We can put all sorts of changes here: cleanup of legacy keys, re-triggers for
 * various fetches etc.
 *
 * This code usually runs fairly early on page load, but if you need specific
 * guarantees or have dependencies in the order of operations (beyond what is
 * captured by the sequential flow here), then this might not be appropriate.
 */
export const runMigrations = async () => {
    const m = (await getKVN("migrationLevel")) ?? 0;
    const latest = 5;
    if (m < latest) {
        log.info(`Running migrations ${m} => ${latest}`);
        // Migration levels 1-5 (Aug 2024 - Feb 2025) were pruned.
        // New migrations should be 6+. e.g.,
        // if (m < 6) await m6();
        await setKV("migrationLevel", latest);
    }
};

// const m6 = () => {
//     // See git history for other examples.
// }
