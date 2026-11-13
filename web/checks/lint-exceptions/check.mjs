import { execFileSync } from "node:child_process";
import { resolve } from "node:path";

for (const script of ["lint.mjs", "test.mjs"]) {
    execFileSync(process.execPath, [resolve(import.meta.dirname, script)], {
        stdio: "inherit",
    });
}
